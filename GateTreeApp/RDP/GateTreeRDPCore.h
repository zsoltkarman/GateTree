// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <stdint.h>

typedef struct GateTreeRDPCore GateTreeRDPCore;

typedef void (*GateTreeRDPFrameCallback)(void *context, const uint8_t *pixels, int width, int height, int stride);
typedef void (*GateTreeRDPDisconnectCallback)(void *context, const char *message);

GateTreeRDPCore *gatetree_rdp_create(const char *host, int port, const char *username,
                                     const char *domain, const char *password, int width, int height,
                                     GateTreeRDPFrameCallback onFrame,
                                     GateTreeRDPDisconnectCallback onDisconnect, void *callbackContext);
void gatetree_rdp_start(GateTreeRDPCore *core);
void gatetree_rdp_stop(GateTreeRDPCore *core);
void gatetree_rdp_mouse_move(GateTreeRDPCore *core, int x, int y);
void gatetree_rdp_mouse_button(GateTreeRDPCore *core, int button, int down, int x, int y);
void gatetree_rdp_unicode(GateTreeRDPCore *core, uint16_t character);
