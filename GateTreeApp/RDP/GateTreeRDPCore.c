// SPDX-License-Identifier: Apache-2.0
#include "GateTreeRDPCore.h"

#include <freerdp/client.h>
#include <freerdp/freerdp.h>
#include <freerdp/gdi/gdi.h>
#include <freerdp/input.h>
#include <freerdp/settings.h>
#include <winpr/synch.h>
#include <openssl/provider.h>

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    rdpClientContext common;
    GateTreeRDPCore *core;
} GateTreeRDPContext;

struct GateTreeRDPCore {
    rdpContext *context;
    pthread_t thread;
    int started;
    volatile int stopping;
    GateTreeRDPFrameCallback onFrame;
    GateTreeRDPDisconnectCallback onDisconnect;
    void *callbackContext;
};

static pthread_once_t openssl_provider_once = PTHREAD_ONCE_INIT;

static void initialize_openssl_providers(void) {
    // RDP with NLA commonly uses NTLM, whose MD4 digest lives in OpenSSL 3's
    // legacy provider. Without it a GUI FreeRDP client can report a generic
    // logon failure although the same credentials work in another client.
    OSSL_PROVIDER_load(NULL, "default");
    OSSL_PROVIDER_load(NULL, "legacy");
}

static GateTreeRDPCore *core_from(rdpContext *context) {
    return ((GateTreeRDPContext *)context)->core;
}

static BOOL begin_paint(rdpContext *context) { (void)context; return TRUE; }

static BOOL end_paint(rdpContext *context) {
    rdpGdi *gdi = context->gdi;
    GateTreeRDPCore *core = core_from(context);
    if (gdi && gdi->primary_buffer && core && core->onFrame)
        core->onFrame(core->callbackContext, gdi->primary_buffer, (int)gdi->width,
                      (int)gdi->height, (int)gdi->stride);
    return TRUE;
}

static BOOL post_connect(freerdp *instance) {
    if (!gdi_init(instance, PIXEL_FORMAT_BGRA32)) return FALSE;
    rdpContext *context = instance->context;
    context->update->BeginPaint = begin_paint;
    context->update->EndPaint = end_paint;
    return TRUE;
}

static void post_disconnect(freerdp *instance) { gdi_free(instance); }

static DWORD verify_certificate(freerdp *instance, const char *host, UINT16 port,
                                const char *commonName, const char *subject, const char *issuer,
                                const char *fingerprint, DWORD flags) {
    (void)instance; (void)host; (void)port; (void)commonName; (void)subject;
    (void)issuer; (void)fingerprint; (void)flags;
    return 2; // Accept for this GateTree session; no terminal prompt is ever used.
}

static DWORD verify_changed_certificate(freerdp *instance, const char *host, UINT16 port,
                                        const char *commonName, const char *subject, const char *issuer,
                                        const char *newFingerprint, const char *oldSubject,
                                        const char *oldIssuer, const char *oldFingerprint, DWORD flags) {
    (void)instance; (void)host; (void)port; (void)commonName; (void)subject; (void)issuer;
    (void)newFingerprint; (void)oldSubject; (void)oldIssuer; (void)oldFingerprint; (void)flags;
    return 2;
}

static BOOL client_new(freerdp *instance, rdpContext *context) {
    (void)context;
    instance->PostConnect = post_connect;
    instance->PostDisconnect = post_disconnect;
    instance->VerifyCertificateEx = verify_certificate;
    instance->VerifyChangedCertificateEx = verify_changed_certificate;
    return TRUE;
}

static void *connection_thread(void *argument) {
    GateTreeRDPCore *core = argument;
    freerdp *instance = core->context->instance;
    if (!freerdp_connect(instance)) {
        if (!core->stopping && core->onDisconnect) {
            UINT32 error = freerdp_get_last_error(core->context);
            const char *name = freerdp_get_last_error_name(error);
            char message[256];
            snprintf(message, sizeof(message), "RDP connection failed: %s", name ? name : "unknown error");
            core->onDisconnect(core->callbackContext, message);
        }
        return NULL;
    }

    while (!core->stopping && !freerdp_shall_disconnect_context(core->context)) {
        HANDLE handles[64];
        DWORD count = freerdp_get_event_handles(core->context, handles, 64);
        if (count == 0) break;
        DWORD result = WaitForMultipleObjects(count, handles, FALSE, 200);
        if (result == WAIT_FAILED || !freerdp_check_event_handles(core->context)) break;
    }
    freerdp_disconnect(instance);
    if (!core->stopping && core->onDisconnect)
        core->onDisconnect(core->callbackContext, "RDP session disconnected.");
    return NULL;
}

GateTreeRDPCore *gatetree_rdp_create(const char *host, int port, const char *username,
                                     const char *domain, const char *password, int width, int height,
                                     GateTreeRDPFrameCallback onFrame,
                                     GateTreeRDPDisconnectCallback onDisconnect, void *callbackContext) {
    GateTreeRDPCore *core = calloc(1, sizeof(*core));
    if (!core) return NULL;
    pthread_once(&openssl_provider_once, initialize_openssl_providers);
    core->onFrame = onFrame;
    core->onDisconnect = onDisconnect;
    core->callbackContext = callbackContext;

    RDP_CLIENT_ENTRY_POINTS entryPoints;
    memset(&entryPoints, 0, sizeof(entryPoints));
    entryPoints.Size = sizeof(entryPoints);
    entryPoints.Version = RDP_CLIENT_INTERFACE_VERSION;
    entryPoints.ContextSize = sizeof(GateTreeRDPContext);
    entryPoints.ClientNew = client_new;
    core->context = freerdp_client_context_new(&entryPoints);
    if (!core->context) { free(core); return NULL; }
    ((GateTreeRDPContext *)core->context)->core = core;

    rdpSettings *settings = core->context->settings;
    freerdp_settings_set_string(settings, FreeRDP_ServerHostname, host);
    freerdp_settings_set_uint32(settings, FreeRDP_ServerPort, (UINT32)(port > 0 ? port : 3389));
    freerdp_settings_set_string(settings, FreeRDP_Username, username ? username : "");
    freerdp_settings_set_string(settings, FreeRDP_Domain, domain ? domain : "");
    freerdp_settings_set_string(settings, FreeRDP_Password, password ? password : "");
    freerdp_settings_set_uint32(settings, FreeRDP_DesktopWidth, (UINT32)(width > 0 ? width : 1280));
    freerdp_settings_set_uint32(settings, FreeRDP_DesktopHeight, (UINT32)(height > 0 ? height : 800));
    freerdp_settings_set_uint32(settings, FreeRDP_ColorDepth, 32);
    freerdp_settings_set_bool(settings, FreeRDP_SoftwareGdi, TRUE);
    return core;
}

void gatetree_rdp_start(GateTreeRDPCore *core) {
    if (core && !core->started) { core->started = 1; pthread_create(&core->thread, NULL, connection_thread, core); }
}

void gatetree_rdp_stop(GateTreeRDPCore *core) {
    if (!core) return;
    core->stopping = 1;
    if (core->context) freerdp_abort_connect_context(core->context);
    if (core->started) pthread_join(core->thread, NULL);
    if (core->context) freerdp_client_context_free(core->context);
    free(core);
}

void gatetree_rdp_mouse_move(GateTreeRDPCore *core, int x, int y) {
    if (core && core->context && core->context->input)
        freerdp_input_send_mouse_event(core->context->input, PTR_FLAGS_MOVE, (UINT16)x, (UINT16)y);
}
void gatetree_rdp_mouse_button(GateTreeRDPCore *core, int button, int down, int x, int y) {
    if (!core || !core->context || !core->context->input) return;
    UINT16 flag = button == 2 ? PTR_FLAGS_BUTTON2 : (button == 3 ? PTR_FLAGS_BUTTON3 : PTR_FLAGS_BUTTON1);
    if (down) flag |= PTR_FLAGS_DOWN;
    freerdp_input_send_mouse_event(core->context->input, flag, (UINT16)x, (UINT16)y);
}
void gatetree_rdp_unicode(GateTreeRDPCore *core, uint16_t character) {
    if (!core || !core->context || !core->context->input) return;
    freerdp_input_send_unicode_keyboard_event(core->context->input, 0, character);
    freerdp_input_send_unicode_keyboard_event(core->context->input, KBD_FLAGS_RELEASE, character);
}
