//
//  RTCClient.h
//  test_webrtc_mac_framework
//
//  Created by hanxiaoqing on 2026/3/12.
//

#import <Foundation/Foundation.h>
#import <WebRTC/WebRTC.h>

NS_ASSUME_NONNULL_BEGIN

@class RTCClient;

@protocol RTCClientDelegate <NSObject>
@optional
/// DataChannel 连接状态变化
- (void)rtcClient:(RTCClient *)client dataChannelStateDidChange:(RTCDataChannelState)state;

/// 收到对端身份信息
- (void)rtcClient:(RTCClient *)client didReceivePeerName:(NSString *)name ip:(NSString *)ip role:(NSString *)role;

/// 在线设备列表（仅内存、实时；由信令 `peers` 推送，客户端不持久化）
- (void)rtcClient:(RTCClient *)client didUpdateOnlinePeers:(NSArray<NSDictionary *> *)peers;



/// 发送进度回调
- (void)rtcClient:(RTCClient *)client
 fileSendProgress:(double)progress
        bytesSent:(uint64_t)bytesSent
       totalBytes:(uint64_t)totalBytes;

/// 收到对方发送请求（offer）
- (void)rtcClient:(RTCClient *)client
fileReceiveOfferedWithName:(NSString *)name
             size:(uint64_t)size;

/// 接收进度回调
- (void)rtcClient:(RTCClient *)client
fileReceiveProgress:(double)progress
   bytesReceived:(uint64_t)bytesReceived
      totalBytes:(uint64_t)totalBytes;

/// 传输结束（error == nil 表示成功）
- (void)rtcClient:(RTCClient *)client
fileTransferDidFinishWithError:(nullable NSError *)error;
@end

@interface RTCClient : NSObject <RTCPeerConnectionDelegate, RTCDataChannelDelegate>

@property(nonatomic,weak,nullable) id<RTCClientDelegate> delegate;

/// 对端 IP 和别名（连接成功后可读）
@property(nonatomic,readonly,nullable) NSString *peerIP;
@property(nonatomic,readonly,nullable) NSString *peerName;

/// 启动 WebSocket 信令 + 建立 PeerConnection
- (void)start;

/// DataChannel 是否已打开
- (BOOL)isDataChannelOpen;

/// 发起文件发送（需 DataChannel 已 Open）
- (BOOL)sendFileAtURL:(NSURL *)fileURL error:(NSError **)error;

/// 取消当前传输
- (void)cancelFileTransfer;

/// 接受来文件并写入指定路径
- (void)acceptIncomingFileToURL:(NSURL *)destinationURL;

/// 拒绝来文件
- (void)rejectIncomingFileWithReason:(NSString *)reason;

/// 请求与指定 `peerIP` 配对建立 DataChannel（用于“点击设备发送”）
- (void)connectToPeerIP:(NSString *)peerIP;

/// 刷新在线设备列表（通过 signaling server）
- (void)refreshOnlinePeers;

@end

NS_ASSUME_NONNULL_END
