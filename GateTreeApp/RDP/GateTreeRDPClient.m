// SPDX-License-Identifier: Apache-2.0
#import "Bridge.h"
#import "GateTreeRDPCore.h"

static void did_receive_frame(void *context, const uint8_t *pixels, int width, int height, int stride) {
    GateTreeRDPClient *client = (__bridge GateTreeRDPClient *)context;
    size_t length = (size_t)stride * (size_t)height;
    NSData *data = [NSData dataWithBytes:pixels length:length];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGImageRef image = CGImageCreate(width, height, 8, 32, stride, colorSpace,
                                     kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little,
                                     provider, NULL, false, kCGRenderingIntentDefault);
    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);
    if (!image) return;
    CFRetain(image);
    dispatch_async(dispatch_get_main_queue(), ^{
        id<GateTreeRDPClientDelegate> delegate = client.delegate;
        if (delegate) [delegate rdpClientDidUpdateFrame:image];
        CGImageRelease(image);
    });
    CGImageRelease(image);
}

static void did_disconnect(void *context, const char *message) {
    GateTreeRDPClient *client = (__bridge GateTreeRDPClient *)context;
    NSString *text = message ? [NSString stringWithUTF8String:message] : nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        id<GateTreeRDPClientDelegate> delegate = client.delegate;
        if (delegate) [delegate rdpClientDidDisconnect:text];
    });
}

@implementation GateTreeRDPClient {
    NSString *_host, *_username, *_domain, *_password;
    NSInteger _port, _width, _height;
    GateTreeRDPCore *_core;
}

- (instancetype)initWithHost:(NSString *)host port:(NSInteger)port username:(NSString *)username domain:(NSString *)domain password:(NSString *)password width:(NSInteger)width height:(NSInteger)height {
    if ((self = [super init])) { _host = host; _port = port; _username = username; _domain = domain; _password = password; _width = width; _height = height; }
    return self;
}

- (void)start {
    if (_core) return;
    _core = gatetree_rdp_create(_host.UTF8String, (int)_port, _username.UTF8String,
                                _domain.UTF8String, _password.UTF8String, (int)_width, (int)_height,
                                did_receive_frame, did_disconnect, (__bridge void *)self);
    if (_core) gatetree_rdp_start(_core);
    else if (self.delegate) [self.delegate rdpClientDidDisconnect:@"Could not initialize the embedded FreeRDP client."];
}

- (void)stop { if (_core) { gatetree_rdp_stop(_core); _core = NULL; } }
- (void)dealloc { [self stop]; }
- (void)sendMouseMoveX:(NSInteger)x y:(NSInteger)y { gatetree_rdp_mouse_move(_core, (int)x, (int)y); }
- (void)sendMouseButton:(NSInteger)button down:(BOOL)down x:(NSInteger)x y:(NSInteger)y { gatetree_rdp_mouse_button(_core, (int)button, down, (int)x, (int)y); }
- (void)sendUnicode:(unichar)character { gatetree_rdp_unicode(_core, character); }
@end
