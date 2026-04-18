//
//  HXSendViewController.h
//  test_webrtc_mac_framework
//
//  Created by Cursor AI on 2026/3/17.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface HXSendViewController : NSViewController

@property(nonatomic,strong,nullable) NSURL *selectedFileURL;

@property(nonatomic,copy,nullable) void (^onChooseFile)(void);
@property(nonatomic,copy,nullable) void (^onChooseFolder)(void);
@property(nonatomic,copy,nullable) void (^onSend)(void);
@property(nonatomic,copy,nullable) void (^onCancel)(void);
@property(nonatomic,copy,nullable) void (^onTapDevice)(void);
@property(nonatomic,copy,nullable) void (^onSelectPeerIP)(NSString *ip);
@property(nonatomic,copy,nullable) void (^onRefreshPeers)(void);

- (void)setPeerConnected:(BOOL)connected;
- (void)setSendProgress:(double)progress bytesSent:(uint64_t)bytesSent totalBytes:(uint64_t)totalBytes;
- (void)setSendStatusText:(NSString *)text;
- (void)setSendingInProgress:(BOOL)sending;
- (void)setSelectedFileName:(NSString *)name;
- (void)updatePeerInfo:(NSString *)info;
/// 应用信令下发的在线列表（不读写本地，仅更新当前界面）
- (void)applyOnlinePeers:(NSArray<NSDictionary *> *)peers;
- (nullable NSString *)currentSelectedPeerIP;

@end

NS_ASSUME_NONNULL_END

