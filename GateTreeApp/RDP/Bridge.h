// SPDX-License-Identifier: Apache-2.0
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@protocol GateTreeRDPClientDelegate <NSObject>
- (void)rdpClientDidUpdateFrame:(CGImageRef)image;
- (void)rdpClientDidDisconnect:(nullable NSString *)message;
@end

@interface GateTreeRDPClient : NSObject
@property (nonatomic, weak) id<GateTreeRDPClientDelegate> delegate;
- (instancetype)initWithHost:(NSString *)host port:(NSInteger)port username:(NSString *)username domain:(NSString *)domain password:(NSString *)password width:(NSInteger)width height:(NSInteger)height;
- (void)start;
- (void)stop;
- (void)sendMouseMoveX:(NSInteger)x y:(NSInteger)y;
- (void)sendMouseButton:(NSInteger)button down:(BOOL)down x:(NSInteger)x y:(NSInteger)y;
- (void)sendUnicode:(unichar)character;
@end
