//
//  RTCClient.m
//  webrtc_file_sender
//
//  Created by hanxiaoqing on 2026/3/12.
//

#import "RTCClient.h"

@interface RTCClient()

@property(nonatomic,strong) RTCPeerConnectionFactory *factory;
@property(nonatomic,strong) RTCPeerConnection *peerConnection;
@property(nonatomic,strong) RTCDataChannel *dataChannel;

@property(nonatomic,strong) NSURLSessionWebSocketTask *socket;

@property(nonatomic,strong,nullable) NSFileHandle *sendHandle;
@property(nonatomic,assign) uint64_t sendTotalBytes;
@property(nonatomic,assign) uint64_t sendBytesSent;

@property(nonatomic,strong,nullable) NSFileHandle *recvHandle;
@property(nonatomic,assign) uint64_t recvTotalBytes;
@property(nonatomic,assign) uint64_t recvBytesReceived;
@property(nonatomic,copy,nullable) NSString *incomingFileName;

@property(nonatomic,strong) dispatch_queue_t fileQueue;
@property(nonatomic,assign) BOOL transferCancelled;
@property(nonatomic,assign) NSUInteger chunkSize;
@property(nonatomic,assign) BOOL isOfferer;
@property(nonatomic,strong) NSMutableArray<RTCIceCandidate *> *pendingCandidates;
@property(nonatomic,assign) BOOL hasRemoteDescription;
@property(nonatomic,copy,nullable) NSString *peerIP;
@property(nonatomic,copy,nullable) NSString *peerName;
@property(nonatomic,copy,nullable) NSString *selfIP;

@end

@implementation RTCClient

- (instancetype)init {
    self = [super init];
    if (self) {
        _fileQueue = dispatch_queue_create("hx.webrtc.filetransfer", DISPATCH_QUEUE_SERIAL);
        // Smaller chunks reduce DataChannel backpressure spikes on desktop.
        _chunkSize = 16 * 1024;
        _pendingCandidates = [NSMutableArray array];
    }
    return self;
}

#pragma mark - start

- (void)start {
    // 不再持久化设备列表；清理旧版本写入的键，避免误以为仍在使用本地列表。
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"RecentPeers"];
    [self setupWebSocket];
}

#pragma mark - websocket

- (void)setupWebSocket {
    NSLog(@"[RTCClient] Connecting to ws://localhost:9000");
    NSURL *url = [NSURL URLWithString:@"ws://localhost:9000"];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:
                             [NSURLSessionConfiguration defaultSessionConfiguration]];
    self.socket = [session webSocketTaskWithURL:url];
    [self.socket resume];
    
    [self receiveSignal];
    [self setupPeerConnection];
}


#pragma mark - receive signal

- (void)receiveSignal {
    __weak typeof(self) weakSelf = self;
    
    [self.socket receiveMessageWithCompletionHandler:
     ^(NSURLSessionWebSocketMessage * _Nullable message,
       NSError * _Nullable error) {
        
        // 兼容 text frame (信令服务器发 text) 和 data frame
            NSData *msgData = nil;
            if (message.type == NSURLSessionWebSocketMessageTypeString) {
                msgData = [message.string dataUsingEncoding:NSUTF8StringEncoding];
            } else if (message.type == NSURLSessionWebSocketMessageTypeData) {
                msgData = message.data;
            }
            if (msgData == nil) { [weakSelf receiveSignal]; return; }
            {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:msgData options:0 error:nil];
            NSString *type = json[@"type"];
            
            // === 信令状态机入口：根据 type 分发 ===
            // role / peer_joined：确定我是 offerer 还是 answerer，以及何时触发 createOffer
            // offer / answer：SDP 协商（谁先 setRemoteDescription / 再 setLocalDescription）
            // candidate：ICE 候选添加（支持“候选早到”的情况，先排队再 flush）
            // peers：在线设备列表，只影响 UI，不参与 WebRTC 协商
            
            if ([type isEqual:@"role"]) {
                // 信令服务器告诉当前身份：offerer 还是 answerer。
                // - offerer：后续在 peer_joined 时会主动 createOffer 并创建 DataChannel；
                // - answerer：只等待对端发来的 offer，再生成 answer。
                NSString *role = json[@"role"];
                NSLog(@"[RTCClient] Assigned role: %@", role);
                weakSelf.isOfferer = [role isEqual:@"offerer"];
                if (json[@"selfIP"] && json[@"selfIP"] != [NSNull null]) weakSelf.selfIP = json[@"selfIP"];
                if (json[@"peerIP"] && json[@"peerIP"] != [NSNull null]) weakSelf.peerIP = json[@"peerIP"];
                [weakSelf receiveSignal]; return;
            }
            if ([type isEqual:@"peer_joined"]) {
                // 配对成功：
                // - offerer 收到后：正式进入 WebRTC 协商阶段（调用 createOffer）；
                // - answerer 收到后：只记录 peerIP，等待后续的 offer 消息。
                NSLog(@"[RTCClient] Peer joined, creating offer");
                if (json[@"peerIP"] && json[@"peerIP"] != [NSNull null]) weakSelf.peerIP = json[@"peerIP"];
                if (weakSelf.isOfferer) { [weakSelf createOffer]; }
                [weakSelf receiveSignal]; return;
            }
            if ([type isEqual:@"peer_left"]) {
                // 对端从信令服务器断开配对。
                // 这里通过 delegate 告诉 UI“DataChannel 视为已关闭”，
                // 真正的传输清理逻辑由 ICE 状态变化和文件传输逻辑负责。
                NSLog(@"[RTCClient] Peer left");
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([weakSelf.delegate respondsToSelector:@selector(rtcClient:dataChannelStateDidChange:)]) {
                        [weakSelf.delegate rtcClient:weakSelf dataChannelStateDidChange:RTCDataChannelStateClosed];
                    }
                });
                [weakSelf receiveSignal]; return;
            }
            if ([type isEqual:@"error"]) {
                NSLog(@"[RTCClient] Signaling error: %@", json[@"reason"] ?: json);
                [weakSelf receiveSignal]; return;
            }
            if ([type isEqual:@"peers"]) {
                // signaling-server 推送的“当前在线设备列表”，
                // 仅用于发送页 UI 展示，与 SDP/ICE 协商无直接关系。
                NSArray *raw = [json[@"peers"] isKindOfClass:[NSArray class]] ? json[@"peers"] : @[];
                NSMutableArray<NSDictionary *> *peers = [NSMutableArray array];
                for (id obj in raw) {
                    if (![obj isKindOfClass:[NSDictionary class]]) { continue; }
                    NSDictionary *p = (NSDictionary *)obj;
                    NSString *ip = [p[@"ip"] isKindOfClass:[NSString class]] ? p[@"ip"] : @"";
                    if (ip.length == 0) { continue; }
                    NSString *name = [p[@"name"] isKindOfClass:[NSString class]] ? p[@"name"] : @"";
                    if (name.length == 0) { name = ip; }
                    [peers addObject:@{ @"ip": ip, @"name": name, @"online": @YES }];
                }
                NSArray<NSDictionary *> *snapshot = [peers copy];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([weakSelf.delegate respondsToSelector:@selector(rtcClient:didUpdateOnlinePeers:)]) {
                        [weakSelf.delegate rtcClient:weakSelf didUpdateOnlinePeers:snapshot];
                    }
                });
                [weakSelf receiveSignal]; return;
            }
            
            if ([type isEqual:@"offer"]){
                 // 作为 answerer 收到对端的 SDP Offer：
                // 1) setRemoteDescription(offer)，让本地 PeerConnection 知道对端的媒体参数/能力；
                // 2) 把之前因为还没有 RemoteDescription 而暂存的 ICE candidates 全部 add 进去；
                // 3) 调用 answerForConstraints 生成 SDP Answer，并 setLocalDescription(answer)；
                // 4) 通过 WebSocket 把 answer 发回给对端（对端是 offerer）。
                NSLog(@"[RTCClient] Received offer, peerConnection=%@", weakSelf.peerConnection);
                if (weakSelf.peerConnection == nil) {
                    NSLog(@"[RTCClient] ERROR: peerConnection is nil when offer received!");
                    [weakSelf receiveSignal]; return;
                }
                RTCSessionDescription *offer = [[RTCSessionDescription alloc] initWithType:RTCSdpTypeOffer sdp:json[@"sdp"]];
                [weakSelf.peerConnection setRemoteDescription:offer completionHandler:^(NSError * _Nullable error) {
                    if (error) { NSLog(@"setRemoteDescription(offer) error: %@", error); return; }
                    // ✅ flush pending candidates after remote description is set
                    weakSelf.hasRemoteDescription = YES;
                    for (RTCIceCandidate *cand in weakSelf.pendingCandidates) {
                        [weakSelf.peerConnection addIceCandidate:cand];
                    }
                    [weakSelf.pendingCandidates removeAllObjects];
                    NSLog(@"[RTCClient] Flushed pending candidates after offer");
                    RTCMediaConstraints *constraints = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:nil optionalConstraints:nil];
                    [weakSelf.peerConnection answerForConstraints:constraints completionHandler:^(RTCSessionDescription * _Nullable sdp, NSError * _Nullable error) {
                        if (error || sdp == nil) { NSLog(@"answerForConstraints error: %@", error); return; }
                        [weakSelf.peerConnection setLocalDescription:sdp completionHandler:^(NSError * _Nullable error) {
                            if (error) { NSLog(@"setLocalDescription(answer) error: %@", error); return; }
                            [weakSelf sendSignalingJSONObject:@{ @"type": @"answer", @"sdp": sdp.sdp }];
                        }];
                    }];
                }];
            }
            
            if ([type isEqual:@"answer"]){
                // 作为 offerer 收到对端返回的 SDP Answer：
                // 1) setRemoteDescription(answer) 完成协商的另一半；
                // 2) flush pendingCandidates，把之前排队的 candidates 全部 add 进去；
                // 此后双方都拥有 Local+Remote SDP，只需继续通过 candidate 完成 ICE 连接。
                RTCSessionDescription *answer = [[RTCSessionDescription alloc] initWithType:RTCSdpTypeAnswer sdp:json[@"sdp"]];
                [weakSelf.peerConnection setRemoteDescription:answer completionHandler:^(NSError * _Nullable error) {
                    if (error) { NSLog(@"setRemoteDescription(answer) error: %@", error); return; }
                    weakSelf.hasRemoteDescription = YES;
                    for (RTCIceCandidate *cand in weakSelf.pendingCandidates) {
                        [weakSelf.peerConnection addIceCandidate:cand];
                    }
                    [weakSelf.pendingCandidates removeAllObjects];
                    NSLog(@"[RTCClient] Flushed pending candidates after answer");
                }];
            }
            
            if ([type isEqual:@"candidate"]){
                // 收到对端通过信令发来的 ICE candidate：
                // - 若 hasRemoteDescription == YES：可以立即 addIceCandidate；
                // - 否则先丢进 pendingCandidates，等 setRemoteDescription 完成后统一 flush，
                //  避免“candidate 比 SDP 提前到”导致添加失败。
                NSDictionary *cd = json[@"candidate"];
                RTCIceCandidate *candidate = [[RTCIceCandidate alloc] initWithSdp:cd[@"candidate"] sdpMLineIndex:[cd[@"sdpMLineIndex"] intValue] sdpMid:cd[@"sdpMid"]];
                if (weakSelf.hasRemoteDescription) {
                    [weakSelf.peerConnection addIceCandidate:candidate];
                } else {
                    [weakSelf.pendingCandidates addObject:candidate];
                    NSLog(@"[RTCClient] Queued ICE candidate (total: %lu)", (unsigned long)weakSelf.pendingCandidates.count);
                }
            }
            
        } // end json block
        [weakSelf receiveSignal];
    }];
    
}



#pragma mark - peerconnection

- (void)setupPeerConnection {
    self.factory = [[RTCPeerConnectionFactory alloc] init];
    
    RTCConfiguration *config = [[RTCConfiguration alloc] init];
    RTCIceServer *stun = [[RTCIceServer alloc] initWithURLStrings:@[@"stun:stun.l.google.com:19302"]];
    config.iceServers = @[stun];
    
    self.peerConnection = [self.factory peerConnectionWithConfiguration:config constraints:nil  delegate:self];
    
    // DataChannel 只由 Offerer 创建；Answerer 通过 didOpenDataChannel: 被动接收
    // createOffer 由信令服务器的 peer_joined 消息触发
}


#pragma mark - offer

- (void)createOffer {
    /*
     WebRTC 协商流程（Offerer 侧）：
     1) 创建 DataChannel（本 demo：文件传输走可靠且有序的数据通道）
     2) 生成本地 SDP Offer（offerForConstraints）
     3) setLocalDescription(offer)：把 SDP 应用到 PeerConnection，并触发本地 ICE gathering
     4) 将 SDP 通过 signaling 通道发给对端（这里的 signaling 由 WebSocket 服务器转发）

     注意：
     - 本方法只负责“创建 offer 并发送给对端”。ICE candidate 的实际发送在
       `peerConnection:didGenerateIceCandidate:` 回调里完成。
     - Answerer 不会在这里主动创建 DataChannel；它通过 `didOpenDataChannel:` 被动获取。
     */

    // 只有 offerer 负责创建 DataChannel
    RTCDataChannelConfiguration *dcConfig = [[RTCDataChannelConfiguration alloc] init];
    // 文件传输依赖可靠 + 有序：避免丢包/乱序导致接收端写文件出错
    dcConfig.isOrdered = YES;
    // maxRetransmits = -1 表示“不指定”，保留默认的可靠行为（由 WebRTC 内部策略决定）
    dcConfig.maxRetransmits = -1; // -1 means "unset" in WebRTC; keep default reliable behavior.
    // 通过 label="chat" 使两端用同一个通道标识匹配（answerer 会在 didOpenDataChannel 得到它）
    self.dataChannel = [self.peerConnection dataChannelForLabel:@"chat" configuration:dcConfig];
    // 注册 DataChannel delegate：用于监听 readyState 变化和接收来自对端的业务消息（hello/ft_*）
    self.dataChannel.delegate = self;
    NSLog(@"[RTCClient] DataChannel created by offerer, state: %ld", (long)self.dataChannel.readyState);

    
    __weak typeof(self) weakSelf = self;
    // 本 demo 不传音视频流，因此 constraints 对 SDP/ICE 生成只做默认约束即可
    RTCMediaConstraints *constraints = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:nil optionalConstraints:nil];

    // 生成本地 SDP Offer：对端要用它做 setRemoteDescription，然后生成 answer
    [self.peerConnection offerForConstraints:constraints
                           completionHandler:^(RTCSessionDescription * _Nullable sdp,
                                               NSError * _Nullable error) {
        // offer 生成失败则直接返回：上层没有在此处做 UI 告警（Demo 简化）
        if (error) return;

        // 将生成出的 SDP Offer 应用为本地描述。
        // 这一步会让 PeerConnection 开始：
        // - ICE gathering（本地候选收集）
        // - 后续在候选产生时回调 didGenerateIceCandidate，然后通过 signaling 发送出去
        [weakSelf.peerConnection setLocalDescription:sdp
                                   completionHandler:^(NSError * _Nullable error) {
            // setLocalDescription 失败通常意味着协商状态不可用；这里直接 return
            if (error) return;

            // 将 SDP 通过信令发送给对端（对端会 setRemoteDescription，然后走 answerForConstraints）
            NSString *typeString;
            switch (sdp.type) {
                case RTCSdpTypeOffer:
                    typeString = @"offer";
                    break;
                case RTCSdpTypeAnswer:
                    typeString = @"answer";
                    break;
                case RTCSdpTypePrAnswer:
                    typeString = @"pranswer";
                    break;
                default:
                    typeString = @"offer";
            }
            
            // signaling payload：{ type: "offer"|"answer"|..., sdp: "<SDP text>" }
            // 注意：这里发的是文本信令，不是 DataChannel 业务消息
            NSDictionary *msg = @{
                @"type": typeString,
                @"sdp": sdp.sdp
            };
            [weakSelf sendSignalingJSONObject:msg];
        }];
    }];
}




#pragma mark - PeerConnection delegate

- (void)peerConnectionShouldNegotiate:(RTCPeerConnection *)peerConnection {
    
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeSignalingState:(RTCSignalingState)stateChanged {
    
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeIceGatheringState:(RTCIceGatheringState)newState {
    
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeIceConnectionState:(RTCIceConnectionState)newState {
    NSLog(@"ICE connection state: %ld", (long)newState);
    // 连接断开或失败时，通知 UI DataChannel 已关闭
    if (newState == RTCIceConnectionStateDisconnected ||
        newState == RTCIceConnectionStateFailed ||
        newState == RTCIceConnectionStateClosed) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(rtcClient:dataChannelStateDidChange:)]) {
                [self.delegate rtcClient:self dataChannelStateDidChange:RTCDataChannelStateClosed];
            }
            // 如果有传输中的任务，以错误结束
            if (self.sendHandle != nil || self.recvHandle != nil) {
                [self cleanupTransferWithError:[NSError errorWithDomain:@"RTCClient"
                                                                   code:40
                                                               userInfo:@{NSLocalizedDescriptionKey: @"连接已断开"}]];
            }
        });
    }
}


- (void)peerConnection:(RTCPeerConnection *)peerConnection
didGenerateIceCandidate:(RTCIceCandidate *)candidate {
    
    NSDictionary *c =
    @{
        @"candidate":candidate.sdp,
        @"sdpMLineIndex":@(candidate.sdpMLineIndex),
        @"sdpMid":candidate.sdpMid
    };
    
    NSDictionary *msg =
    @{
        @"type":@"candidate",
        @"candidate":c
    };
    [self sendSignalingJSONObject:msg];
}

- (void)peerConnection:(nonnull RTCPeerConnection *)peerConnection didAddStream:(nonnull RTCMediaStream *)stream { 
    
}


- (void)peerConnection:(nonnull RTCPeerConnection *)peerConnection didOpenDataChannel:(nonnull RTCDataChannel *)dataChannel {
    // Answerer 端：对方创建的 DataChannel 通过此回调拿到
    NSLog(@"didOpenDataChannel: %@", dataChannel.label);
    if (self.dataChannel == nil || self.dataChannel.readyState != RTCDataChannelStateOpen) {
        self.dataChannel = dataChannel;
        self.dataChannel.delegate = self;
        // 通知 UI DataChannel 已就绪
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(rtcClient:dataChannelStateDidChange:)]) {
                [self.delegate rtcClient:self dataChannelStateDidChange:RTCDataChannelStateOpen];
            }
        });
    }
}


- (void)peerConnection:(nonnull RTCPeerConnection *)peerConnection didRemoveIceCandidates:(nonnull NSArray<RTCIceCandidate *> *)candidates { 
    
}


- (void)peerConnection:(nonnull RTCPeerConnection *)peerConnection didRemoveStream:(nonnull RTCMediaStream *)stream { 
    
}




#pragma mark - signaling pairing

/// 使用 **文本帧** 发 JSON，避免部分 `ws` 对二进制帧与 `JSON.parse` 组合不兼容。
- (void)sendSignalingJSONObject:(NSDictionary *)obj {
    if (self.socket == nil || obj == nil) { return; }
    if (![NSJSONSerialization isValidJSONObject:obj]) { return; }
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
    if (data == nil) { return; }
    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (str == nil) { return; }
    NSURLSessionWebSocketMessage *message = [[NSURLSessionWebSocketMessage alloc] initWithString:str];
    [self.socket sendMessage:message completionHandler:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"[RTCClient] WebSocket signaling send error: %@", error);
        }
    }];
}

- (void)connectToPeerIP:(NSString *)peerIP {
    if (peerIP == nil || peerIP.length == 0) { return; }
    if (self.socket == nil) { return; }

    NSDictionary *msg = @{
        @"type": @"pair_request",
        @"targetIP": peerIP
    };
    [self sendSignalingJSONObject:msg];
}

- (void)refreshOnlinePeers {
    if (self.socket == nil) { return; }
    [self sendSignalingJSONObject:@{@"type": @"list_peers"}];
}

#pragma mark - file transfer public API
- (BOOL)isDataChannelOpen {
    return self.dataChannel.readyState == RTCDataChannelStateOpen;
}

- (BOOL)sendFileAtURL:(NSURL *)fileURL error:(NSError **)error {
    if (![self isDataChannelOpen]) {
        if (error) {
            *error = [NSError errorWithDomain:@"RTCClient"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"DataChannel is not open"}];
        }
        return NO;
    }
    if (self.sendHandle != nil || self.recvHandle != nil) {
        if (error) {
            *error = [NSError errorWithDomain:@"RTCClient"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"A file transfer is already in progress"}];
        }
        return NO;
    }
    
    NSNumber *fileSizeNum = nil;
    [fileURL getResourceValue:&fileSizeNum forKey:NSURLFileSizeKey error:nil];
    uint64_t total = (uint64_t)fileSizeNum.unsignedLongLongValue;
    if (total == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"RTCClient"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"File is empty or size unavailable"}];
        }
        return NO;
    }
    
    NSError *openErr = nil;
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:fileURL error:&openErr];
    if (handle == nil) {
        if (error) { *error = openErr; }
        return NO;
    }
    
    self.transferCancelled = NO;
    self.sendHandle = handle;
    self.sendTotalBytes = total;
    self.sendBytesSent = 0;
    
    NSString *name = fileURL.lastPathComponent ?: @"file";
    NSDictionary *offer = @{
        @"t": @"ft_offer",
        @"name": name,
        @"size": @(total),
        @"chunk": @(self.chunkSize)
    };
    [self sendControlJSON:offer];
    return YES;
}

- (void)cancelFileTransfer {
    self.transferCancelled = YES;
    [self sendControlJSON:@{@"t": @"ft_cancel"}];
    [self cleanupTransferWithError:[NSError errorWithDomain:@"RTCClient"
                                                       code:10
                                                   userInfo:@{NSLocalizedDescriptionKey: @"Cancelled"}]];
}

- (void)acceptIncomingFileToURL:(NSURL *)destinationURL {
    if (self.incomingFileName == nil || self.recvTotalBytes == 0) { return; }
    if (self.recvHandle != nil) { return; }
    
    [[NSFileManager defaultManager] createFileAtPath:destinationURL.path contents:nil attributes:nil];
    NSError *err = nil;
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingToURL:destinationURL error:&err];
    if (handle == nil) {
        [self rejectIncomingFileWithReason:@"Unable to open destination"];
        [self cleanupTransferWithError:err ?: [NSError errorWithDomain:@"RTCClient"
                                                                  code:11
                                                              userInfo:@{NSLocalizedDescriptionKey: @"Unable to open destination"}]];
        return;
    }
    
    self.recvHandle = handle;
    self.recvBytesReceived = 0;
    [self sendControlJSON:@{@"t": @"ft_accept"}];
}

- (void)rejectIncomingFileWithReason:(NSString *)reason {
    [self sendControlJSON:@{@"t": @"ft_reject", @"reason": reason ?: @""}];
    [self cleanupTransferWithError:[NSError errorWithDomain:@"RTCClient"
                                                       code:12
                                                   userInfo:@{NSLocalizedDescriptionKey: reason ?: @"Rejected"}]];
}

#pragma mark - DataChannel delegate

- (void)dataChannelDidChangeState:(RTCDataChannel *)dataChannel {
    NSLog(@"[RTCClient] DataChannel state: %ld", (long)dataChannel.readyState);
    RTCDataChannelState state = dataChannel.readyState;
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(rtcClient:dataChannelStateDidChange:)]) {
            [self.delegate rtcClient:self dataChannelStateDidChange:state];
        }
    });
    if (state == RTCDataChannelStateOpen) {
        [self sendHello];
    }
}

- (void)dataChannel:(RTCDataChannel *)dataChannel didReceiveMessageWithBuffer:(RTCDataBuffer *)buffer {
    
    if (!buffer.isBinary) {
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:buffer.data options:0 error:nil];
        if (![json isKindOfClass:[NSDictionary class]]) { return; }
        NSString *t = json[@"t"];
        
        if ([t isEqual:@"hello"]) {
            NSString *name = [json[@"name"] isKindOfClass:[NSString class]] ? json[@"name"] : @"Unknown";
            NSString *ip   = [json[@"ip"]   isKindOfClass:[NSString class]] ? json[@"ip"]   : @"unknown";
            NSString *role = [json[@"role"] isKindOfClass:[NSString class]] ? json[@"role"] : @"";
            self.peerName = name;
            if (self.peerIP == nil) self.peerIP = ip;
            NSLog(@"[RTCClient] Received hello from peer: name=%@, ip=%@, role=%@", name, ip, role);
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([self.delegate respondsToSelector:@selector(rtcClient:didReceivePeerName:ip:role:)]) {
                    [self.delegate rtcClient:self didReceivePeerName:name ip:ip role:role];
                }
            });
            return;
        }
        
        if ([t isEqual:@"ft_offer"]) {
            if (self.sendHandle != nil || self.recvHandle != nil) {
                [self sendControlJSON:@{@"t": @"ft_reject", @"reason": @"busy"}];
                return;
            }
            self.incomingFileName = [json[@"name"] isKindOfClass:[NSString class]] ? json[@"name"] : @"file";
            self.recvTotalBytes = (uint64_t)[json[@"size"] unsignedLongLongValue];
            self.recvBytesReceived = 0;

            // UI 更新必须在主线程做；dataChannel 回调不保证在主线程。
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([self.delegate respondsToSelector:@selector(rtcClient:fileReceiveOfferedWithName:size:)]) {
                    [self.delegate rtcClient:self fileReceiveOfferedWithName:self.incomingFileName size:self.recvTotalBytes];
                }
            });
            return;
        }
        
        if ([t isEqual:@"ft_accept"]) {
            if (self.sendHandle == nil) { return; }
            [self startSendingLoop];
            return;
        }
        
        if ([t isEqual:@"ft_reject"] || [t isEqual:@"ft_cancel"]) {
            NSString *reason = [json[@"reason"] isKindOfClass:[NSString class]] ? json[@"reason"] : @"Cancelled/Rejected";
            [self cleanupTransferWithError:[NSError errorWithDomain:@"RTCClient"
                                                               code:13
                                                           userInfo:@{NSLocalizedDescriptionKey: reason}]];
            return;
        }
        
        if ([t isEqual:@"ft_done"]) {
            [self cleanupTransferWithError:nil];
            return;
        }
        
        NSString *msg = [[NSString alloc] initWithData:buffer.data encoding:NSUTF8StringEncoding];
        if (msg.length > 0) {
            NSLog(@"recv %@", msg);
        }
        return;
    }
    
    if (self.recvHandle == nil || self.recvTotalBytes == 0) {
        return;
    }
    
    NSError *writeErr = nil;
    @try {
        [self.recvHandle writeData:buffer.data];
    } @catch (NSException *exception) {
        writeErr = [NSError errorWithDomain:@"RTCClient"
                                       code:20
                                   userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Write failed"}];
    }
    if (writeErr != nil) {
        [self cleanupTransferWithError:writeErr];
        return;
    }
    
    self.recvBytesReceived += buffer.data.length;
    double p = self.recvTotalBytes > 0 ? (double)self.recvBytesReceived / (double)self.recvTotalBytes : 0;
    // UI 更新必须在主线程做；dataChannel 回调不保证在主线程。
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(rtcClient:fileReceiveProgress:bytesReceived:totalBytes:)]) {
            [self.delegate rtcClient:self fileReceiveProgress:p bytesReceived:self.recvBytesReceived totalBytes:self.recvTotalBytes];
        }
    });
    
    if (self.recvBytesReceived >= self.recvTotalBytes) {
        [self sendControlJSON:@{@"t": @"ft_done"}];
        [self cleanupTransferWithError:nil];
    }
    
}

#pragma mark - send

- (void)sendHello {
    NSString *baseUser = NSUserName() ?: @"Mac";
    NSString *pid = [NSString stringWithFormat:@"%d", [[NSProcessInfo processInfo] processIdentifier]];
    NSString *name = [NSString stringWithFormat:@"%@#%@", baseUser, [pid substringFromIndex:MAX(0, (int)pid.length - 3)]];
    NSString *ip = self.selfIP ?: @"unknown";
    NSString *role = self.isOfferer ? @"offerer" : @"answerer";
    NSDictionary *helloDict = @{@"t": @"hello", @"name": name, @"ip": ip, @"role": role};
    [self sendControlJSON:helloDict];
    NSLog(@"[RTCClient] Sent hello: name=%@, ip=%@", name, ip);
}

- (void)sendControlJSON:(NSDictionary *)json {
    if (![NSJSONSerialization isValidJSONObject:json]) { return; }
    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
    if (data == nil) { return; }
    RTCDataBuffer *buffer = [[RTCDataBuffer alloc] initWithData:data isBinary:NO];
    [self.dataChannel sendData:buffer];
}

- (void)startSendingLoop {
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.fileQueue, ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil || self.sendHandle == nil) { return; }
        const uint64_t kBufferedAmountHighWatermark = 512 * 1024; // 512 KB
        const uint64_t kBufferedAmountLowWatermark = 128 * 1024;  // 128 KB
        
        while (!self.transferCancelled && self.sendBytesSent < self.sendTotalBytes) {
            @autoreleasepool {
                // Backpressure guard: wait until queued bytes drop under low watermark.
                NSInteger backpressureWaitIters = 0;
                while (!self.transferCancelled &&
                       self.dataChannel.readyState == RTCDataChannelStateOpen &&
                       self.dataChannel.bufferedAmount > kBufferedAmountHighWatermark &&
                       backpressureWaitIters < 200) {
                    [NSThread sleepForTimeInterval:0.01];
                    backpressureWaitIters += 1;
                    if (self.dataChannel.bufferedAmount <= kBufferedAmountLowWatermark) {
                        break;
                    }
                }
                if (self.dataChannel.readyState != RTCDataChannelStateOpen) {
                    [self cleanupTransferWithError:[NSError errorWithDomain:@"RTCClient"
                                                                       code:32
                                                                   userInfo:@{NSLocalizedDescriptionKey: @"DataChannel closed during send"}]];
                    return;
                }

                NSError *readErr = nil;
                NSData *chunk = nil;
                if (@available(macOS 10.15, *)) {
                    chunk = [self.sendHandle readDataUpToLength:self.chunkSize error:&readErr];
                } else {
                    chunk = [self.sendHandle readDataOfLength:self.chunkSize];
                }
                if (readErr != nil || chunk.length == 0) { break; }
                
                RTCDataBuffer *buffer = [[RTCDataBuffer alloc] initWithData:chunk isBinary:YES];
                BOOL ok = NO;
                NSInteger retries = 0;
                while (!ok && retries < 120 && !self.transferCancelled) {
                    if (self.dataChannel.readyState != RTCDataChannelStateOpen) { break; }
                    ok = [self.dataChannel sendData:buffer];
                    if (ok) { break; }

                    // Temporary backpressure is common; retry briefly before failing.
                    retries += 1;
                    [NSThread sleepForTimeInterval:0.01];
                }
                if (!ok) {
                    [self cleanupTransferWithError:[NSError errorWithDomain:@"RTCClient"
                                                                       code:30
                                                                   userInfo:@{NSLocalizedDescriptionKey: @"DataChannel send failed (backpressure timeout)"}]];
                    return;
                }
                
                self.sendBytesSent += chunk.length;
                double p = self.sendTotalBytes > 0 ? (double)self.sendBytesSent / (double)self.sendTotalBytes : 0;
                if ([self.delegate respondsToSelector:@selector(rtcClient:fileSendProgress:bytesSent:totalBytes:)]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self.delegate rtcClient:self fileSendProgress:p bytesSent:self.sendBytesSent totalBytes:self.sendTotalBytes];
                    });
                }
            }
        }
        
        if (self.transferCancelled) { return; }
        
        if (self.sendBytesSent >= self.sendTotalBytes) {
            [self sendControlJSON:@{@"t": @"ft_done"}];
            [self cleanupTransferWithError:nil];
        } else {
            [self cleanupTransferWithError:[NSError errorWithDomain:@"RTCClient"
                                                               code:31
                                                           userInfo:@{NSLocalizedDescriptionKey: @"Send ended early"}]];
        }
    });
}




- (void)cleanupTransferWithError:(NSError * _Nullable)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.sendHandle != nil) {
            @try { [self.sendHandle closeFile]; } @catch (__unused NSException *e) {}
        }
        if (self.recvHandle != nil) {
            @try { [self.recvHandle closeFile]; } @catch (__unused NSException *e) {}
        }
        
        self.sendHandle = nil;
        self.sendTotalBytes = 0;
        self.sendBytesSent = 0;
        
        self.recvHandle = nil;
        self.recvTotalBytes = 0;
        self.recvBytesReceived = 0;
        self.incomingFileName = nil;
        
        if ([self.delegate respondsToSelector:@selector(rtcClient:fileTransferDidFinishWithError:)]) {
            [self.delegate rtcClient:self fileTransferDidFinishWithError:error];
        }
    });
}

@end
