//
//  HXAirDropStyleTransferViewController.m
//  test_webrtc_mac_framework
//
//  Container VC: LocalSend-like sidebar + child panes.
//
//  Created by Cursor AI on 2026/3/17.
//

#import "HXAirDropStyleTransferViewController.h"

#import "HXReceiveViewController.h"
#import "HXSendViewController.h"

typedef NS_ENUM(NSInteger, HXSidebarItem) {
    HXSidebarItemReceive = 0,
    HXSidebarItemSend = 1,
    HXSidebarItemSettings = 2,
};

#pragma mark - Sidebar row

@interface HXSidebarRow : NSControl
@property(nonatomic,strong) NSView *selectionPill;
@property(nonatomic,strong) NSImageView *iconView;
@property(nonatomic,strong) NSTextField *titleLabel;
@property(nonatomic,assign) HXSidebarItem item;
@property(nonatomic,assign) BOOL selected;
- (instancetype)initWithItem:(HXSidebarItem)item title:(NSString *)title symbol:(NSString *)symbol;
@end

@implementation HXSidebarRow

- (instancetype)initWithItem:(HXSidebarItem)item title:(NSString *)title symbol:(NSString *)symbol {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        _item = item;
        self.wantsLayer = YES;

        _selectionPill = [[NSView alloc] initWithFrame:NSZeroRect];
        _selectionPill.translatesAutoresizingMaskIntoConstraints = NO;
        _selectionPill.wantsLayer = YES;
        _selectionPill.layer.cornerRadius = 18;
        _selectionPill.layer.masksToBounds = YES;
        _selectionPill.layer.backgroundColor = [[NSColor colorWithCalibratedRed:0.76 green:0.88 blue:0.86 alpha:1.0] CGColor];
        _selectionPill.hidden = YES;
        [self addSubview:_selectionPill positioned:NSWindowBelow relativeTo:nil];

        _iconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:title];
        _iconView.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:16 weight:NSFontWeightSemibold];
        _iconView.contentTintColor = [NSColor labelColor];
        [self addSubview:_iconView];

        _titleLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.editable = NO;
        _titleLabel.bezeled = NO;
        _titleLabel.drawsBackground = NO;
        _titleLabel.selectable = NO;
        _titleLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
        _titleLabel.stringValue = title ?: @"";
        [self addSubview:_titleLabel];

        CGFloat pad = 10;
        [NSLayoutConstraint activateConstraints:@[
            [_selectionPill.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_selectionPill.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_selectionPill.topAnchor constraintEqualToAnchor:self.topAnchor constant:2],
            [_selectionPill.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-2],

            [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:pad],
            [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:20],
            [_iconView.heightAnchor constraintEqualToConstant:20],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:10],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-pad],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [self.heightAnchor constraintEqualToConstant:44],
        ]];
    }
    return self;
}

- (void)setSelected:(BOOL)selected {
    _selected = selected;
    self.selectionPill.hidden = !selected;
}

- (void)mouseDown:(NSEvent *)event {
    [self sendAction:self.action to:self.target];
}

@end

#pragma mark - Main container VC

@interface HXAirDropStyleTransferViewController ()

@property(nonatomic,strong) RTCClient *rtcClient;

@property(nonatomic,strong) NSSplitView *splitView;
@property(nonatomic,strong) NSView *sidebar;
@property(nonatomic,strong) NSView *content;

@property(nonatomic,strong) HXSidebarRow *rowReceive;
@property(nonatomic,strong) HXSidebarRow *rowSend;
@property(nonatomic,strong) HXSidebarRow *rowSettings;

@property(nonatomic,strong) HXSendViewController *sendVC;
@property(nonatomic,strong) HXReceiveViewController *receiveVC;
@property(nonatomic,strong) NSViewController *settingsVC;

@property(nonatomic,assign) HXSidebarItem selectedItem;
@property(nonatomic,copy,nullable) NSString *incomingName;
@property(nonatomic,assign) uint64_t incomingSize;

@property(nonatomic,assign) BOOL pendingAutoSend;
@property(nonatomic,copy,nullable) NSString *pendingPeerIP;
@property(nonatomic,assign) BOOL expectingPeerListRefreshAck;

@end

@implementation HXAirDropStyleTransferViewController

- (instancetype)initWithRTCClient:(RTCClient *)client {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _rtcClient = client;
        _rtcClient.delegate = self;
    }
    return self;
}

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 980, 620)];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self buildUI];
    [self setSelectedItem:HXSidebarItemSend];
    [self updateConnectionState];
}

- (NSTextField *)label:(NSString *)string size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor * _Nullable)color {
    NSTextField *t = [[NSTextField alloc] initWithFrame:NSZeroRect];
    t.translatesAutoresizingMaskIntoConstraints = NO;
    t.editable = NO;
    t.bezeled = NO;
    t.drawsBackground = NO;
    t.selectable = NO;
    t.stringValue = string ?: @"";
    t.font = [NSFont systemFontOfSize:size weight:weight];
    if (color != nil) { t.textColor = color; }
    return t;
}

- (void)buildUI {
    self.view.wantsLayer = YES;
    self.view.layer.backgroundColor = [[NSColor colorWithCalibratedRed:0.93 green:0.97 blue:0.96 alpha:1.0] CGColor];

    self.splitView = [[NSSplitView alloc] initWithFrame:NSZeroRect];
    self.splitView.translatesAutoresizingMaskIntoConstraints = NO;
    self.splitView.vertical = YES;
    self.splitView.dividerStyle = NSSplitViewDividerStyleThin;
    [self.view addSubview:self.splitView];

    [NSLayoutConstraint activateConstraints:@[
        [self.splitView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.splitView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.splitView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.splitView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.sidebar = [[NSView alloc] initWithFrame:NSZeroRect];
    self.sidebar.wantsLayer = YES;
    self.sidebar.layer.backgroundColor = [[NSColor colorWithCalibratedRed:0.89 green:0.95 blue:0.93 alpha:1.0] CGColor];
    [self.splitView addArrangedSubview:self.sidebar];

    self.content = [[NSView alloc] initWithFrame:NSZeroRect];
    self.content.wantsLayer = YES;
    self.content.layer.backgroundColor = [[NSColor colorWithCalibratedRed:0.93 green:0.97 blue:0.96 alpha:1.0] CGColor];
    [self.splitView addArrangedSubview:self.content];

    [self.sidebar.widthAnchor constraintEqualToConstant:280].active = YES;

    [self buildSidebar];
    [self buildChildren];
}

- (void)buildSidebar {
    NSView *side = self.sidebar;
    side.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *title = [self label:@"LocalSend" size:42 weight:NSFontWeightHeavy color:[NSColor labelColor]];
    [side addSubview:title];

    self.rowReceive = [[HXSidebarRow alloc] initWithItem:HXSidebarItemReceive title:@"接收" symbol:@"wifi"];
    self.rowReceive.target = self;
    self.rowReceive.action = @selector(onNav:);
    [side addSubview:self.rowReceive];

    self.rowSend = [[HXSidebarRow alloc] initWithItem:HXSidebarItemSend title:@"发送" symbol:@"paperplane.fill"];
    self.rowSend.target = self;
    self.rowSend.action = @selector(onNav:);
    [side addSubview:self.rowSend];

    self.rowSettings = [[HXSidebarRow alloc] initWithItem:HXSidebarItemSettings title:@"设置" symbol:@"gearshape.fill"];
    self.rowSettings.target = self;
    self.rowSettings.action = @selector(onNav:);
    [side addSubview:self.rowSettings];

    CGFloat left = 34;
    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:side.leadingAnchor constant:left],
        [title.topAnchor constraintEqualToAnchor:side.topAnchor constant:54],

        [self.rowReceive.leadingAnchor constraintEqualToAnchor:side.leadingAnchor constant:24],
        [self.rowReceive.trailingAnchor constraintEqualToAnchor:side.trailingAnchor constant:-24],
        [self.rowReceive.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:46],

        [self.rowSend.leadingAnchor constraintEqualToAnchor:self.rowReceive.leadingAnchor],
        [self.rowSend.trailingAnchor constraintEqualToAnchor:self.rowReceive.trailingAnchor],
        [self.rowSend.topAnchor constraintEqualToAnchor:self.rowReceive.bottomAnchor constant:10],

        [self.rowSettings.leadingAnchor constraintEqualToAnchor:self.rowReceive.leadingAnchor],
        [self.rowSettings.trailingAnchor constraintEqualToAnchor:self.rowReceive.trailingAnchor],
        [self.rowSettings.topAnchor constraintEqualToAnchor:self.rowSend.bottomAnchor constant:10],
    ]];
}

- (void)buildChildren {
    self.sendVC = [[HXSendViewController alloc] initWithNibName:nil bundle:nil];
    __weak typeof(self) weakSelf = self;
    self.sendVC.onChooseFile = ^{
        __strong typeof(weakSelf) self = weakSelf;
        [self onChooseFile:nil];
    };
    self.sendVC.onChooseFolder = ^{
        __strong typeof(weakSelf) self = weakSelf;
        [self onChooseFolder:nil];
    };
    self.sendVC.onSend = ^{
        __strong typeof(weakSelf) self = weakSelf;
        [self onSend:nil];
    };
    self.sendVC.onCancel = ^{
        __strong typeof(weakSelf) self = weakSelf;
        [self onCancel:nil];
    };
    self.sendVC.onTapDevice = ^{
        __strong typeof(weakSelf) self = weakSelf;
        [self onSend:nil];
    };
    self.sendVC.onRefreshPeers = ^{
        __strong typeof(weakSelf) self = weakSelf;
        self.expectingPeerListRefreshAck = YES;
        [self.rtcClient refreshOnlinePeers];
        [self.sendVC setSendStatusText:@"正在刷新在线设备…"];
    };

    // Select a peer from the Nearby list; if a file is selected, auto-send when the DataChannel opens.
    self.sendVC.onSelectPeerIP = ^(NSString *ip) {
        __strong typeof(weakSelf) self = weakSelf;

        if (ip == nil || ip.length == 0) { return; }
        // 已在向该设备发起连接时，避免列表刷新等导致的重复 pair_request（服务端会回 busy）。
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

    self.receiveVC = [[HXReceiveViewController alloc] initWithNibName:nil bundle:nil];
    self.receiveVC.onAccept = ^{
        __strong typeof(weakSelf) self = weakSelf;
        [self onAccept:nil];
    };
    self.receiveVC.onReject = ^{
        __strong typeof(weakSelf) self = weakSelf;
        [self onReject:nil];
    };

    self.settingsVC = [[NSViewController alloc] initWithNibName:nil bundle:nil];
    self.settingsVC.view = [[NSView alloc] initWithFrame:NSZeroRect];
    NSTextField *st = [self label:@"设置" size:18 weight:NSFontWeightSemibold color:[NSColor labelColor]];
    NSTextField *sh = [self label:@"此 Demo 只复刻 UI 样式（可后续补充真实设置项）。"
                           size:12
                         weight:NSFontWeightRegular
                          color:[NSColor secondaryLabelColor]];
    [self.settingsVC.view addSubview:st];
    [self.settingsVC.view addSubview:sh];
    [NSLayoutConstraint activateConstraints:@[
        [st.leadingAnchor constraintEqualToAnchor:self.settingsVC.view.leadingAnchor constant:34],
        [st.topAnchor constraintEqualToAnchor:self.settingsVC.view.topAnchor constant:42],
        [sh.leadingAnchor constraintEqualToAnchor:st.leadingAnchor],
        [sh.topAnchor constraintEqualToAnchor:st.bottomAnchor constant:12],
    ]];

    [self addChildViewController:self.sendVC];
    [self addChildViewController:self.receiveVC];
    [self addChildViewController:self.settingsVC];

    [self.content addSubview:self.sendVC.view];
    [self.content addSubview:self.receiveVC.view];
    [self.content addSubview:self.settingsVC.view];

    NSArray<NSView *> *views = @[self.sendVC.view, self.receiveVC.view, self.settingsVC.view];
    for (NSView *v in views) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [v.leadingAnchor constraintEqualToAnchor:self.content.leadingAnchor],
            [v.trailingAnchor constraintEqualToAnchor:self.content.trailingAnchor],
            [v.topAnchor constraintEqualToAnchor:self.content.topAnchor],
            [v.bottomAnchor constraintEqualToAnchor:self.content.bottomAnchor],
        ]];
    }
}

#pragma mark - navigation

- (void)onNav:(HXSidebarRow *)sender {
    [self setSelectedItem:sender.item];
}

- (void)setSelectedItem:(HXSidebarItem)selectedItem {
    _selectedItem = selectedItem;
    self.rowReceive.selected = (selectedItem == HXSidebarItemReceive);
    self.rowSend.selected = (selectedItem == HXSidebarItemSend);
    self.rowSettings.selected = (selectedItem == HXSidebarItemSettings);

    self.receiveVC.view.hidden = (selectedItem != HXSidebarItemReceive);
    self.sendVC.view.hidden = (selectedItem != HXSidebarItemSend);
    self.settingsVC.view.hidden = (selectedItem != HXSidebarItemSettings);
}

#pragma mark - actions (Send)

- (void)onChooseFile:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) { return; }
        self.sendVC.selectedFileURL = panel.URL;
        [self.sendVC setSelectedFileName:panel.URL.lastPathComponent];
        [self.sendVC setSendStatusText:@"已选择文件，点击设备发送"];
        [self updateConnectionState];
    }];
}

- (void)onChooseFolder:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) { return; }
        self.sendVC.selectedFileURL = panel.URL;
        [self.sendVC setSelectedFileName:panel.URL.lastPathComponent];
        [self.sendVC setSendStatusText:@"已选择文件夹（暂不支持发送整个文件夹）"];
        [self updateConnectionState];
    }];
}

- (void)onSend:(id)sender {
    NSURL *url = self.sendVC.selectedFileURL;
    if (url == nil) { return; }
    if ([url hasDirectoryPath]) {
        NSAlert *a = [[NSAlert alloc] init];
        a.messageText = @"暂不支持发送文件夹";
        a.informativeText = @"目前 Demo 仅支持发送单个文件。";
        [a beginSheetModalForWindow:self.view.window completionHandler:nil];
        return;
    }

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
    [self.sendVC setSendingInProgress:YES];
}

- (void)onCancel:(id)sender {
    [self.rtcClient cancelFileTransfer];
}

#pragma mark - actions (Receive)

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

#pragma mark - state updates

- (void)updateConnectionState {
    BOOL open = [self.rtcClient isDataChannelOpen];
    [self.sendVC setPeerConnected:open];
}

#pragma mark - RTCClientDelegate

- (void)rtcClient:(RTCClient *)client dataChannelStateDidChange:(RTCDataChannelState)state {
    [self updateConnectionState];
    if (state == RTCDataChannelStateOpen && self.pendingAutoSend) {
        self.pendingAutoSend = NO;
        self.pendingPeerIP = nil;
        [self onSend:nil];
    }
}

- (void)rtcClient:(RTCClient *)client didReceivePeerName:(NSString *)name ip:(NSString *)ip role:(NSString *)role {
    NSString *info = [NSString stringWithFormat:@"%@  %@", name, ip];
    [self.sendVC updatePeerInfo:info];
    [self.receiveVC updatePeerInfo:info];
}

- (void)rtcClient:(RTCClient *)client didUpdateOnlinePeers:(NSArray<NSDictionary *> *)peers {
    [self.sendVC applyOnlinePeers:peers];
    if (self.expectingPeerListRefreshAck) {
        self.expectingPeerListRefreshAck = NO;
        [self.sendVC setSendStatusText:@"在线设备已刷新"];
    }
}

- (void)rtcClient:(RTCClient *)client fileSendProgress:(double)progress bytesSent:(uint64_t)bytesSent totalBytes:(uint64_t)totalBytes {
    [self.sendVC setSendProgress:progress bytesSent:bytesSent totalBytes:totalBytes];
}

- (void)rtcClient:(RTCClient *)client fileReceiveOfferedWithName:(NSString *)name size:(uint64_t)size {
    self.incomingName = name;
    self.incomingSize = size;
    [self.receiveVC presentIncomingOfferWithName:name size:size];
    [self setSelectedItem:HXSidebarItemReceive];
}

- (void)rtcClient:(RTCClient *)client fileReceiveProgress:(double)progress bytesReceived:(uint64_t)bytesReceived totalBytes:(uint64_t)totalBytes {
    [self.receiveVC setReceiveProgress:progress bytesReceived:bytesReceived totalBytes:totalBytes];
}

- (void)rtcClient:(RTCClient *)client fileTransferDidFinishWithError:(NSError * _Nullable)error {
    [self.sendVC setSendingInProgress:NO];
    [self.sendVC setSendingInProgress:NO];
    if (error == nil) {
        [self.sendVC setSendStatusText:@"完成"];
        [self.receiveVC resetToIdleWithStatus:@"等待对方发送…"];
    } else if (error.code == 10) {
        [self.sendVC setSendStatusText:@"已取消"];
        [self.receiveVC resetToIdleWithStatus:@"等待对方发送…"];
    } else {
        [self.sendVC setSendStatusText:@"发生错误"];
        [self.receiveVC resetToIdleWithStatus:@"等待对方发送…"];
        NSAlert *a = [[NSAlert alloc] init];
        a.messageText = @"传输结束";
        a.informativeText = error.localizedDescription ?: @"Unknown error";
        [a beginSheetModalForWindow:self.view.window completionHandler:nil];
    }

    self.incomingName = nil;
    self.incomingSize = 0;
}

@end

