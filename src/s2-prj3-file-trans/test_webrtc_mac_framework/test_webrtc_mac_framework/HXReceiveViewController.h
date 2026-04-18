//
//  HXReceiveViewController.h
//  test_webrtc_mac_framework
//
//  Created by Cursor AI on 2026/3/17.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface HXReceiveViewController : NSViewController

@property(nonatomic,copy,nullable) void (^onAccept)(void);
@property(nonatomic,copy,nullable) void (^onReject)(void);

- (void)presentIncomingOfferWithName:(NSString *)name size:(uint64_t)size;
- (void)beginReceivingWithName:(NSString *)name size:(uint64_t)size;
- (void)setReceiveProgress:(double)progress bytesReceived:(uint64_t)bytesReceived totalBytes:(uint64_t)totalBytes;
- (void)updatePeerInfo:(NSString *)info;
- (void)resetToIdleWithStatus:(NSString *)status;

@end

NS_ASSUME_NONNULL_END

