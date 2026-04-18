# RTCClient 对外文件 API 调用链梳理（发送/接收）

## 概述

以 `RTCClient.h` 的对外方法为准，梳理“其他发送/接收模块”是如何实现文件发送与接收的调用过程。

整体调用链可以概括为：
`HXSendViewController/HXReceiveViewController (UI事件) -> HXAirDropStyleTransferViewController (容器编排) -> RTCClient (对外API) -> RTCClientDelegate (阶段回调) -> UI更新`

---

## 1. RTCClient 负责文件传输的对外方法

来自 `RTCClient.h`：

- `- (BOOL)isDataChannelOpen;`
- `- (BOOL)sendFileAtURL:(NSURL *)fileURL error:(NSError **)error;`
- `- (void)cancelFileTransfer;`
- `- (void)acceptIncomingFileToURL:(NSURL *)destinationURL;`
- `- (void)rejectIncomingFileWithReason:(NSString *)reason;`

这些方法分别对应发送/接收流程中的关键节点。

---

## 2. 发送端（A）文件发送：从 UI 到 RTCClient 的调用顺序

### 2.1 UI 事件如何触发“容器编排”

发送页 `HXSendViewController` 只负责把按钮点击/设备选择等事件抛给外部（容器 VC）。

关键关系是“UI -> block -> 容器方法 -> RTCClient”。你提到的几个名字对应如下：

1. `onSendTap`：由发送按钮点击触发，最终调用容器注入的 `self.onSend` block

```objc
// HXSendViewController.m（buildUI）
self.sendButton.target = self;
self.sendButton.action = @selector(onSendTap:);

// HXSendViewController.m
- (void)onSendTap:(id)sender { if (self.onSend) { self.onSend(); } }
```

2. `onCancelTap`：由取消按钮点击触发，最终调用容器注入的 `self.onCancel` block

```objc
// HXSendViewController.m（buildUI）
self.cancelButton.target = self;
self.cancelButton.action = @selector(onCancelTap:);

// HXSendViewController.m
- (void)onCancelTap:(id)sender { if (self.onCancel) { self.onCancel(); } }
```

3. `self.onSelectPeerIP(ip)`：由“附近设备列表”选中某行触发，并把选中的 `ip` 抛给容器

```objc
// HXSendViewController.m
- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = self.peersTableView.selectedRow;
    self.selectedPeerRow = row;
    if (self.suppressPeerSelectActions) {
        [self.peersTableView reloadData];
        return;
    }
    if (row >= 0 && row < (NSInteger)self.onlinePeers.count) {
        NSDictionary *peer = self.onlinePeers[(NSUInteger)row];
        NSString *ip = peer[@"ip"] ?: @"";
        if (self.onSelectPeerIP) {
            self.onSelectPeerIP(ip);
        }
    }
    [self.peersTableView reloadData];
}
```

4. 容器 `buildChildren` 做“block 注入”，把上面三个 block 绑定到容器真正的业务逻辑

```objc
// HXAirDropStyleTransferViewController.m（buildChildren）
self.sendVC.onSend = ^{
    [self onSend:nil];
};
self.sendVC.onCancel = ^{
    [self onCancel:nil];
};
self.sendVC.onSelectPeerIP = ^(NSString *ip) {
    if (ip == nil || ip.length == 0) { return; }
    if (self.pendingAutoSend && self.pendingPeerIP != nil && [self.pendingPeerIP isEqualToString:ip] &&
        ![self.rtcClient isDataChannelOpen]) {
        return;
    }
    if (self.sendVC.selectedFileURL == nil) {
        NSAlert *a = [[NSAlert alloc] init];
        a.messageText = @"请选择文件";
        [a beginSheetModalForWindow:self.view.window completionHandler:nil];
        return;
    }
    if ([self.sendVC.selectedFileURL hasDirectoryPath]) {
        NSAlert *a = [[NSAlert alloc] init];
        a.messageText = @"暂不支持发送文件夹";
        [a beginSheetModalForWindow:self.view.window completionHandler:nil];
        return;
    }
    if ([self.rtcClient isDataChannelOpen]) {
        NSAlert *a = [[NSAlert alloc] init];
        a.messageText = @"当前已有连接，请先发送完成后再切换设备";
        [a beginSheetModalForWindow:self.view.window completionHandler:nil];
        return;
    }
    self.pendingPeerIP = ip;
    self.pendingAutoSend = YES;
    [self.sendVC setSendStatusText:@"正在连接设备…"];
    [self.rtcClient connectToPeerIP:ip];
};
```

### 2.2 容器编排：容器 VC 的 `onSend` 决定调用哪个 RTCClient 对外 API

发送按钮点击后，容器 VC 的 `onSend` 是“唯一入口决策点”：

```objc
// HXAirDropStyleTransferViewController.m
- (void)onSend:(id)sender {
    NSURL *url = self.sendVC.selectedFileURL;
    if (url == nil) { return; }

    if (![self.rtcClient isDataChannelOpen]) {
        NSString *targetIP = self.pendingPeerIP ?: [self.sendVC currentSelectedPeerIP];
        if (targetIP.length == 0) {
            NSAlert *a = [[NSAlert alloc] init];
            a.messageText = @"请先选择设备";
            a.informativeText = @"在“附近的设备”列表中点击一个目标设备后再发送。";
            [a beginSheetModalForWindow:self.view.window completionHandler:nil];
            return;
        }
        self.pendingPeerIP = targetIP;
        self.pendingAutoSend = YES;
        [self.sendVC setSendStatusText:@"正在连接设备…"];
        [self.rtcClient connectToPeerIP:targetIP];
        return;
    }

    NSError *err = nil;
    BOOL ok = [self.rtcClient sendFileAtURL:url error:&err];
    if (!ok) {
        NSAlert *a = [[NSAlert alloc] init];
        a.messageText = @"发送失败";
        a.informativeText = err.localizedDescription ?: @"Unknown error";
        [a beginSheetModalForWindow:self.view.window completionHandler:nil];
        return;
    }

    [self.sendVC setSendStatusText:@"等待对方确认…"];
    [self.sendVC setSendingInProgress:YES];
}
```

这段逻辑把发送流程拆成两种路径：

- 如果 DataChannel 还没打开：调用 `rtcClient.connectToPeerIP` 发起配对，然后等待 DataChannel open 后自动触发真正的 `sendFileAtURL`
- 如果 DataChannel 已打开：直接调用 `rtcClient.sendFileAtURL`

### 2.3 DataChannel 打开后，容器如何自动触发 `sendFileAtURL`

容器通过 `RTCClientDelegate` 的 `dataChannelStateDidChange` 做自动发送：

```objc
// HXAirDropStyleTransferViewController.m
- (void)rtcClient:(RTCClient *)client dataChannelStateDidChange:(RTCDataChannelState)state {
    [self updateConnectionState];
    if (state == RTCDataChannelStateOpen && self.pendingAutoSend) {
        self.pendingAutoSend = NO;
        self.pendingPeerIP = nil;
        [self onSend:nil]; // 再次进入 onSend，这时 isDataChannelOpen == YES
    }
}
```

### 2.4 `RTCClient.sendFileAtURL` 内部做了什么（关键协议节点）

容器调用 `sendFileAtURL` 后，RTCClient 会发送业务控制消息 `ft_offer`，然后等待对端发 `ft_accept` 才开始真正的数据发送循环。

关键代码：

```objc
// RTCClient.m
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
```

此后阶段推进来自 RTCClient 的 DataChannel 收到消息：

- 收到 `ft_accept` -> 开始发送循环（内部调用 `startSendingLoop`）

### 2.5 发送过程中 UI 如何收到进度/完成

RTCClient 在发送数据过程中会通过 delegate 回调：

```objc
// RTCClientDelegate: fileSendProgress
[self.delegate rtcClient:self fileSendProgress:p bytesSent:self.sendBytesSent totalBytes:self.sendTotalBytes];
```

容器 VC 把它转成 UI 更新：

```objc
// HXAirDropStyleTransferViewController.m
- (void)rtcClient:(RTCClient *)client fileSendProgress:(double)progress
                                 bytesSent:(uint64_t)bytesSent
                                totalBytes:(uint64_t)totalBytes {
    [self.sendVC setSendProgress:progress bytesSent:bytesSent totalBytes:totalBytes];
}
```

最终发送结束（成功或失败）由：

```objc
- (void)rtcClient:(RTCClient *)client fileTransferDidFinishWithError:(NSError * _Nullable)error
```

容器里根据 error 更新状态并清理 `incomingName/incomingSize`：

```objc
if (error == nil) { [self.sendVC setSendStatusText:@"完成"]; }
else if (error.code == 10) { [self.sendVC setSendStatusText:@"已取消"]; }
else { [self.sendVC setSendStatusText:@"发生错误"]; }
```

### 2.6 用户点击“取消”时调用 `RTCClient.cancelFileTransfer`

容器将取消按钮直接映射到 RTCClient：

```objc
// HXAirDropStyleTransferViewController.m
- (void)onCancel:(id)sender {
    [self.rtcClient cancelFileTransfer];
}
```

RTCClient 接收到 `cancelFileTransfer` 后会发 `ft_cancel` 并清理发送状态：

```objc
// RTCClient.m
- (void)cancelFileTransfer {
    self.transferCancelled = YES;
    [self sendControlJSON:@{@"t": @"ft_cancel"}];
    [self cleanupTransferWithError:[NSError errorWithDomain:@"RTCClient"
                                                       code:10
                                                   userInfo:@{NSLocalizedDescriptionKey: @"Cancelled"}]];
}
```

---

## 3. 接收端（B）文件接收：从 RTCClient 回调到 UI 的调用顺序

### 3.1 RTCClient 收到 `ft_offer` 后触发 delegate（这是接收端的“起点”）

当对端 A 调用 `sendFileAtURL` 并发送 `ft_offer` 后，B 的 RTCClient 在 DataChannel 文本消息解析阶段会收到 `ft_offer`。

对应代码（RTCClient 内部）：

```objc
// RTCClient.m
if ([t isEqual:@"ft_offer"]) {
    if (self.sendHandle != nil || self.recvHandle != nil) {
        [self sendControlJSON:@{@"t": @"ft_reject", @"reason": @"busy"}];
        return;
    }
    self.incomingFileName = [json[@"name"] isKindOfClass:[NSString class]] ? json[@"name"] : @"file";
    self.recvTotalBytes = (uint64_t)[json[@"size"] unsignedLongLongValue];
    self.recvBytesReceived = 0;
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(rtcClient:fileReceiveOfferedWithName:size:)]) {
            [self.delegate rtcClient:self fileReceiveOfferedWithName:self.incomingFileName size:self.recvTotalBytes];
        }
    });
    return;
}
```

容器 VC 收到 `fileReceiveOfferedWithName:size:` 后开始准备接收 UI：

```objc
// HXAirDropStyleTransferViewController.m
- (void)rtcClient:(RTCClient *)client fileReceiveOfferedWithName:(NSString *)name size:(uint64_t)size {
    self.incomingName = name;
    self.incomingSize = size;
    [self.receiveVC presentIncomingOfferWithName:name size:size];
    [self setSelectedItem:HXSidebarItemReceive];
}
```

### 3.2 用户在接收页点击“另存为/拒绝” -> 容器调用 RTCClient 的对外 API

`HXReceiveViewController` 把按钮点击抛给容器：

```objc
// HXReceiveViewController.m
- (void)onAcceptTap:(id)sender { if (self.onAccept) { self.onAccept(); } }
- (void)onRejectTap:(id)sender { if (self.onReject) { self.onReject(); } }
```

容器 VC 的实现为：

```objc
// HXAirDropStyleTransferViewController.m
- (void)onAccept:(id)sender {
    if (self.incomingName == nil || self.incomingSize == 0) { return; }
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = self.incomingName ?: @"file";
    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) {
            [self.rtcClient rejectIncomingFileWithReason:@"User cancelled save dialog"];
            return;
        }
        [self.rtcClient acceptIncomingFileToURL:panel.URL];
        [self.receiveVC beginReceivingWithName:self.incomingName ?: @"file" size:self.incomingSize];
    }];
}

- (void)onReject:(id)sender {
    [self.rtcClient rejectIncomingFileWithReason:@"User rejected"];
}
```

### 3.3 `RTCClient.acceptIncomingFileToURL` 如何推进接收

RTCClient 在 `acceptIncomingFileToURL` 内会创建目标文件句柄并发送 `ft_accept`：

```objc
// RTCClient.m
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
```

此后 RTCClient 才会开始把二进制 DataChannel chunk 写入文件句柄。

当累计接收达到总大小，会发送 `ft_done` 并 cleanup：

```objc
if (self.recvBytesReceived >= self.recvTotalBytes) {
    [self sendControlJSON:@{@"t": @"ft_done"}];
    [self cleanupTransferWithError:nil];
}
```

### 3.4 接收过程中进度如何回传到 UI

RTCClient 在写入文件后计算进度并回调：

```objc
// RTCClient.m
[self.delegate rtcClient:self fileReceiveProgress:p
            bytesReceived:self.recvBytesReceived
               totalBytes:self.recvTotalBytes];
```

容器 VC 再转发给接收页：

```objc
// HXAirDropStyleTransferViewController.m
- (void)rtcClient:(RTCClient *)client fileReceiveProgress:(double)progress
       bytesReceived:(uint64_t)bytesReceived
          totalBytes:(uint64_t)totalBytes {
    [self.receiveVC setReceiveProgress:progress bytesReceived:bytesReceived totalBytes:totalBytes];
}
```

---

## 4. 总结

发送端的“真正发送入口”是 `RTCClient.sendFileAtURL`，接收端的“真正开始写文件入口”是 `RTCClient.acceptIncomingFileToURL`；  
二者的衔接由 RTCClient 在 DataChannel 上的 `ft_offer/ft_accept/ft_done` 控制消息驱动，并通过 `RTCClientDelegate` 把阶段与进度回传给容器，由容器更新 `HXSendViewController` / `HXReceiveViewController` 的 UI。

