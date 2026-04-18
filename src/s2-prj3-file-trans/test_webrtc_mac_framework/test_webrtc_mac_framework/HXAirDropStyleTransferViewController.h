//
//  HXAirDropStyleTransferViewController.h
//  test_webrtc_mac_framework
//
//  Created by Cursor AI on 2026/3/17.
//

#import <Cocoa/Cocoa.h>
#import "RTCClient.h"

NS_ASSUME_NONNULL_BEGIN

@interface HXAirDropStyleTransferViewController : NSViewController <RTCClientDelegate>

- (instancetype)initWithRTCClient:(RTCClient *)client NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(NSNibName _Nullable)nibNameOrNil bundle:(NSBundle * _Nullable)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

