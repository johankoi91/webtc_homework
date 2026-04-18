//
//  HXReceiveViewController.m
//  test_webrtc_mac_framework
//
//  Created by Cursor AI on 2026/3/17.
//

#import "HXReceiveViewController.h"

@interface HXReceiveViewController ()

@property(nonatomic,strong) NSTextField *incomingNameLabel;
@property(nonatomic,strong) NSTextField *receiveStatusLabel;
@property(nonatomic,strong) NSProgressIndicator *receiveProgress;
@property(nonatomic,strong) NSButton *saveAsButton;
@property(nonatomic,strong) NSButton *rejectButton;
@property(nonatomic,strong) NSTextField *selfIPLabel;
@property(nonatomic,strong) NSTextField *peerInfoLabel;
@property(nonatomic,strong) NSView *receivingOverlay;
@property(nonatomic,strong) NSTextField *overlayFileLabel;
@property(nonatomic,strong) NSProgressIndicator *overlayFileProgress;
@property(nonatomic,strong) NSTextField *overlayTotalTitle;
@property(nonatomic,strong) NSProgressIndicator *overlayTotalProgress;
@property(nonatomic,strong) NSButton *overlayCancelButton;
@property(nonatomic,copy) NSString *currentIncomingName;
@property(nonatomic,assign) uint64_t currentIncomingSize;
@property(nonatomic,strong) NSPanel *receivingPanel;
@property(nonatomic,strong,nullable) NSDate *receiveStartTime;

@end

@implementation HXReceiveViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSZeroRect];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self buildUI];
    [self resetToIdleWithStatus:@"等待对方发送…"];
}

- (void)viewDidAppear {
    [super viewDidAppear];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onHostWindowDidResize:)
                                                 name:NSWindowDidResizeNotification
                                               object:self.view.window];
}

- (void)viewWillDisappear {
    [super viewWillDisappear];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSWindowDidResizeNotification
                                                  object:self.view.window];
    [self hideReceivingPanel];
}

- (void)onHostWindowDidResize:(NSNotification *)notification {
    (void)notification;
    [self layoutReceivingPanel];
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

- (NSString *)formatBytes:(uint64_t)bytes {
    static NSArray<NSString *> *units;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        units = @[@"B", @"KB", @"MB", @"GB", @"TB"];
    });
    double value = (double)bytes;
    NSUInteger idx = 0;
    while (value >= 1024.0 && idx + 1 < units.count) {
        value /= 1024.0;
        idx++;
    }
    if (idx == 0) { return [NSString stringWithFormat:@"%llu %@", bytes, units[idx]]; }
    return [NSString stringWithFormat:@"%.2f %@", value, units[idx]];
}

- (void)buildUI {
    NSView *root = self.view;

    // Center logo (approx)
    NSImageView *ring = [[NSImageView alloc] initWithFrame:NSZeroRect];
    ring.translatesAutoresizingMaskIntoConstraints = NO;
    ring.image = [NSImage imageWithSystemSymbolName:@"circle.dashed" accessibilityDescription:nil];
    ring.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:110 weight:NSFontWeightRegular];
    ring.contentTintColor = [NSColor colorWithCalibratedRed:0.0 green:0.45 blue:0.42 alpha:1.0];
    [root addSubview:ring];

    NSView *dot = [[NSView alloc] initWithFrame:NSZeroRect];
    dot.translatesAutoresizingMaskIntoConstraints = NO;
    dot.wantsLayer = YES;
    dot.layer.cornerRadius = 34;
    dot.layer.masksToBounds = YES;
    dot.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.0 green:0.45 blue:0.42 alpha:1.0].CGColor;
    [root addSubview:dot];

    // 本机用户名
    NSString *selfName = NSUserName() ?: @"本机";
    NSTextField *name = [self label:selfName size:42 weight:NSFontWeightHeavy color:[NSColor labelColor]];
    name.alignment = NSTextAlignmentCenter;
    [root addSubview:name];

    // 本机局域网 IP
    NSString *selfIP = @"127.0.0.1";
    for (NSString *addr in [[NSHost currentHost] addresses]) {
        if ([addr hasPrefix:@"10."] || [addr hasPrefix:@"192.168."] ||
            ([addr hasPrefix:@"172."] && !([addr hasPrefix:@"172.0."]))) {
            selfIP = addr;
            break;
        }
    }
    self.selfIPLabel = [self label:selfIP size:14 weight:NSFontWeightSemibold color:[NSColor secondaryLabelColor]];
    self.selfIPLabel.alignment = NSTextAlignmentCenter;
    [root addSubview:self.selfIPLabel];

    self.peerInfoLabel = [self label:@"等待连接…" size:13 weight:NSFontWeightRegular color:[NSColor tertiaryLabelColor]];
    self.peerInfoLabel.alignment = NSTextAlignmentCenter;
    [root addSubview:self.peerInfoLabel];

    self.incomingNameLabel = [self label:@"无接收任务" size:13 weight:NSFontWeightSemibold color:[NSColor labelColor]];
    [root addSubview:self.incomingNameLabel];
    self.receiveStatusLabel = [self label:@"等待对方发送…" size:12 weight:NSFontWeightRegular color:[NSColor secondaryLabelColor]];
    [root addSubview:self.receiveStatusLabel];

    self.receiveProgress = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    self.receiveProgress.translatesAutoresizingMaskIntoConstraints = NO;
    self.receiveProgress.indeterminate = NO;
    self.receiveProgress.minValue = 0;
    self.receiveProgress.maxValue = 1;
    self.receiveProgress.doubleValue = 0;
    self.receiveProgress.controlSize = NSControlSizeSmall;
    self.receiveProgress.style = NSProgressIndicatorStyleBar;
    [root addSubview:self.receiveProgress];

    self.saveAsButton = [NSButton buttonWithTitle:@"另存为…" target:self action:@selector(onAcceptTap:)];
    self.saveAsButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.saveAsButton.bezelStyle = NSBezelStyleTexturedRounded;
    self.saveAsButton.wantsLayer = YES;
    self.saveAsButton.layer.cornerRadius = 10;
    self.saveAsButton.layer.masksToBounds = YES;
    self.saveAsButton.layer.backgroundColor = [[NSColor colorWithCalibratedRed:0.0 green:0.45 blue:0.42 alpha:1.0] CGColor];
    self.saveAsButton.contentTintColor = [NSColor whiteColor];
    self.saveAsButton.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    self.saveAsButton.enabled = NO;
    [root addSubview:self.saveAsButton];

    self.rejectButton = [NSButton buttonWithTitle:@"拒绝" target:self action:@selector(onRejectTap:)];
    self.rejectButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.rejectButton.bezelStyle = NSBezelStyleTexturedRounded;
    self.rejectButton.wantsLayer = YES;
    self.rejectButton.layer.cornerRadius = 10;
    self.rejectButton.layer.masksToBounds = YES;
    self.rejectButton.layer.backgroundColor = [[NSColor colorWithCalibratedRed:0.0 green:0.45 blue:0.42 alpha:1.0] CGColor];
    self.rejectButton.contentTintColor = [NSColor whiteColor];
    self.rejectButton.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    self.rejectButton.enabled = NO;
    [root addSubview:self.rejectButton];

    [NSLayoutConstraint activateConstraints:@[
        [ring.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],
        [ring.centerYAnchor constraintEqualToAnchor:root.centerYAnchor constant:-100],
        [dot.centerXAnchor constraintEqualToAnchor:ring.centerXAnchor],
        [dot.centerYAnchor constraintEqualToAnchor:ring.centerYAnchor],
        [dot.widthAnchor constraintEqualToConstant:68],
        [dot.heightAnchor constraintEqualToConstant:68],

        [name.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],
        [name.topAnchor constraintEqualToAnchor:ring.bottomAnchor constant:18],
        [self.selfIPLabel.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],
        [self.selfIPLabel.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:8],
        [self.peerInfoLabel.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],
        [self.peerInfoLabel.topAnchor constraintEqualToAnchor:self.selfIPLabel.bottomAnchor constant:6],

        [self.incomingNameLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:34],
        [self.incomingNameLabel.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-34],
        [self.incomingNameLabel.bottomAnchor constraintEqualToAnchor:self.receiveProgress.topAnchor constant:-28],

        [self.receiveStatusLabel.leadingAnchor constraintEqualToAnchor:self.incomingNameLabel.leadingAnchor],
        [self.receiveStatusLabel.topAnchor constraintEqualToAnchor:self.incomingNameLabel.bottomAnchor constant:6],

        [self.receiveProgress.leadingAnchor constraintEqualToAnchor:self.incomingNameLabel.leadingAnchor],
        [self.receiveProgress.trailingAnchor constraintEqualToAnchor:self.incomingNameLabel.trailingAnchor],
        [self.receiveProgress.bottomAnchor constraintEqualToAnchor:self.saveAsButton.topAnchor constant:-18],

        [self.saveAsButton.leadingAnchor constraintEqualToAnchor:self.incomingNameLabel.leadingAnchor],
        [self.saveAsButton.widthAnchor constraintEqualToConstant:92],
        [self.saveAsButton.heightAnchor constraintEqualToConstant:34],
        [self.saveAsButton.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-34],
        [self.rejectButton.leadingAnchor constraintEqualToAnchor:self.saveAsButton.trailingAnchor constant:12],
        [self.rejectButton.widthAnchor constraintEqualToAnchor:self.saveAsButton.widthAnchor],
        [self.rejectButton.heightAnchor constraintEqualToAnchor:self.saveAsButton.heightAnchor],
        [self.rejectButton.centerYAnchor constraintEqualToAnchor:self.saveAsButton.centerYAnchor],
    ]];

    // Receiving overlay window (attached on top) - hidden by default.
    NSView *overlay = [[NSView alloc] initWithFrame:NSZeroRect];
    overlay.translatesAutoresizingMaskIntoConstraints = NO;
    overlay.wantsLayer = YES;
    overlay.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;
    overlay.layer.cornerRadius = 12;
    overlay.layer.masksToBounds = YES;
    overlay.layer.borderWidth = 1;
    overlay.layer.borderColor = [NSColor separatorColor].CGColor;
    overlay.hidden = YES;
    self.receivingOverlay = overlay;

    NSTextField *title = [self label:@"正在接收文件" size:16 weight:NSFontWeightBold color:[NSColor labelColor]];
    [overlay addSubview:title];

    NSImageView *fileIcon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    fileIcon.translatesAutoresizingMaskIntoConstraints = NO;
    fileIcon.image = [NSImage imageWithSystemSymbolName:@"film" accessibilityDescription:nil];
    fileIcon.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:26 weight:NSFontWeightSemibold];
    fileIcon.contentTintColor = [NSColor colorWithCalibratedRed:0.0 green:0.45 blue:0.42 alpha:1.0];
    fileIcon.wantsLayer = YES;
    fileIcon.layer.cornerRadius = 10;
    fileIcon.layer.masksToBounds = YES;
    fileIcon.layer.backgroundColor = [[NSColor colorWithCalibratedRed:0.8 green:0.92 blue:0.9 alpha:1.0] CGColor];
    [overlay addSubview:fileIcon];

    self.overlayFileLabel = [self label:@"file (0 MB)" size:13 weight:NSFontWeightRegular color:[NSColor labelColor]];
    [overlay addSubview:self.overlayFileLabel];

    self.overlayFileProgress = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    self.overlayFileProgress.translatesAutoresizingMaskIntoConstraints = NO;
    self.overlayFileProgress.indeterminate = NO;
    self.overlayFileProgress.minValue = 0;
    self.overlayFileProgress.maxValue = 1;
    self.overlayFileProgress.doubleValue = 0;
    self.overlayFileProgress.style = NSProgressIndicatorStyleBar;
    [overlay addSubview:self.overlayFileProgress];

    NSView *bottomCard = [[NSView alloc] initWithFrame:NSZeroRect];
    bottomCard.translatesAutoresizingMaskIntoConstraints = NO;
    bottomCard.wantsLayer = YES;
    bottomCard.layer.cornerRadius = 12;
    bottomCard.layer.masksToBounds = YES;
    bottomCard.layer.backgroundColor = [[NSColor colorWithCalibratedWhite:0.95 alpha:1.0] CGColor];
    bottomCard.layer.borderWidth = 1;
    bottomCard.layer.borderColor = [NSColor separatorColor].CGColor;
    [overlay addSubview:bottomCard];

    self.overlayTotalTitle = [self label:@"总进度 (0:00)" size:14 weight:NSFontWeightSemibold color:[NSColor labelColor]];
    [bottomCard addSubview:self.overlayTotalTitle];

    self.overlayTotalProgress = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    self.overlayTotalProgress.translatesAutoresizingMaskIntoConstraints = NO;
    self.overlayTotalProgress.indeterminate = NO;
    self.overlayTotalProgress.minValue = 0;
    self.overlayTotalProgress.maxValue = 1;
    self.overlayTotalProgress.doubleValue = 0;
    self.overlayTotalProgress.style = NSProgressIndicatorStyleBar;
    [bottomCard addSubview:self.overlayTotalProgress];

    self.overlayCancelButton = [NSButton buttonWithTitle:@"取消" target:self action:@selector(onRejectTap:)];
    self.overlayCancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.overlayCancelButton.bordered = NO;
    self.overlayCancelButton.contentTintColor = [NSColor labelColor];
    [bottomCard addSubview:self.overlayCancelButton];

    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor constant:16],
        [title.topAnchor constraintEqualToAnchor:overlay.topAnchor constant:14],

        [fileIcon.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [fileIcon.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:16],
        [fileIcon.widthAnchor constraintEqualToConstant:48],
        [fileIcon.heightAnchor constraintEqualToConstant:48],

        [self.overlayFileLabel.leadingAnchor constraintEqualToAnchor:fileIcon.trailingAnchor constant:14],
        [self.overlayFileLabel.centerYAnchor constraintEqualToAnchor:fileIcon.centerYAnchor],
        [self.overlayFileLabel.trailingAnchor constraintLessThanOrEqualToAnchor:overlay.trailingAnchor constant:-16],

        [self.overlayFileProgress.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [self.overlayFileProgress.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor constant:-16],
        [self.overlayFileProgress.topAnchor constraintEqualToAnchor:fileIcon.bottomAnchor constant:8],

        [bottomCard.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor constant:8],
        [bottomCard.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor constant:-8],
        [bottomCard.bottomAnchor constraintEqualToAnchor:overlay.bottomAnchor constant:-8],
        [bottomCard.heightAnchor constraintEqualToConstant:98],

        [self.overlayTotalTitle.leadingAnchor constraintEqualToAnchor:bottomCard.leadingAnchor constant:16],
        [self.overlayTotalTitle.topAnchor constraintEqualToAnchor:bottomCard.topAnchor constant:12],
        [self.overlayTotalProgress.leadingAnchor constraintEqualToAnchor:self.overlayTotalTitle.leadingAnchor],
        [self.overlayTotalProgress.trailingAnchor constraintEqualToAnchor:bottomCard.trailingAnchor constant:-16],
        [self.overlayTotalProgress.topAnchor constraintEqualToAnchor:self.overlayTotalTitle.bottomAnchor constant:10],

        [self.overlayCancelButton.trailingAnchor constraintEqualToAnchor:bottomCard.trailingAnchor constant:-16],
        [self.overlayCancelButton.bottomAnchor constraintEqualToAnchor:bottomCard.bottomAnchor constant:-12],
    ]];

    self.receivingPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 980, 620)
                                                      styleMask:NSWindowStyleMaskNonactivatingPanel
                                                        backing:NSBackingStoreBuffered
                                                          defer:NO];
    self.receivingPanel.floatingPanel = YES;
    self.receivingPanel.hidesOnDeactivate = NO;
    self.receivingPanel.level = NSFloatingWindowLevel;
    self.receivingPanel.releasedWhenClosed = NO;
    self.receivingPanel.titleVisibility = NSWindowTitleHidden;
    self.receivingPanel.titlebarAppearsTransparent = YES;
    self.receivingPanel.opaque = NO;
    self.receivingPanel.backgroundColor = [NSColor clearColor];
    self.receivingPanel.contentView = overlay;
}

- (void)layoutReceivingPanel {
    if (self.receivingPanel == nil) { return; }
    NSWindow *host = self.view.window;
    if (host == nil) { return; }

    NSRect hostFrame = host.frame;
    CGFloat panelWidth = MAX(700, hostFrame.size.width - 16);
    CGFloat panelHeight = MAX(420, hostFrame.size.height - 16);
    CGFloat panelX = hostFrame.origin.x + (hostFrame.size.width - panelWidth) / 2.0;
    CGFloat panelY = hostFrame.origin.y + (hostFrame.size.height - panelHeight) / 2.0;
    [self.receivingPanel setFrame:NSMakeRect(panelX, panelY, panelWidth, panelHeight) display:YES];
}

- (void)showReceivingPanel {
    if (self.receivingPanel == nil) { return; }
    NSWindow *host = self.view.window;
    if (host == nil) { return; }
    self.receivingOverlay.hidden = NO;
    [self layoutReceivingPanel];
    if (self.receivingPanel.parentWindow != host) {
        [host addChildWindow:self.receivingPanel ordered:NSWindowAbove];
    }
    [self.receivingPanel orderFront:nil];
}

- (void)hideReceivingPanel {
    if (self.receivingPanel == nil) { return; }
    self.receivingOverlay.hidden = YES;
    NSWindow *host = self.view.window;
    if (host != nil && self.receivingPanel.parentWindow == host) {
        [host removeChildWindow:self.receivingPanel];
    }
    [self.receivingPanel orderOut:nil];
}

- (void)onAcceptTap:(id)sender { if (self.onAccept) { self.onAccept(); } }
- (void)onRejectTap:(id)sender { if (self.onReject) { self.onReject(); } }

- (void)presentIncomingOfferWithName:(NSString *)name size:(uint64_t)size {
    self.currentIncomingName = name ?: @"file";
    self.currentIncomingSize = size;
    self.incomingNameLabel.stringValue = name ?: @"file";
    self.receiveStatusLabel.stringValue = [NSString stringWithFormat:@"对方发来 %@，点击“另存为…”接收", [self formatBytes:size]];
    self.saveAsButton.enabled = YES;
    self.rejectButton.enabled = YES;
    [self hideReceivingPanel];
}

- (void)beginReceivingWithName:(NSString *)name size:(uint64_t)size {
    self.currentIncomingName = name ?: @"file";
    self.currentIncomingSize = size;
    self.receiveStartTime = [NSDate date];
    [self showReceivingPanel];
    self.overlayFileLabel.stringValue = [NSString stringWithFormat:@"%@ (%@)",
                                         self.currentIncomingName,
                                         [self formatBytes:self.currentIncomingSize]];
    self.overlayFileProgress.doubleValue = 0;
    self.overlayTotalProgress.doubleValue = 0;
    self.overlayTotalTitle.stringValue = @"总进度 (0:00)";
    self.saveAsButton.enabled = NO;
    self.rejectButton.enabled = NO;
}

- (void)setReceiveProgress:(double)progress bytesReceived:(uint64_t)bytesReceived totalBytes:(uint64_t)totalBytes {
    self.receiveProgress.doubleValue = progress;
    self.receiveStatusLabel.stringValue = [NSString stringWithFormat:@"接收 %@ / %@ (%.0f%%)",
                                           [self formatBytes:bytesReceived],
                                           [self formatBytes:totalBytes],
                                           progress * 100.0];
    [self showReceivingPanel];
    self.overlayFileProgress.doubleValue = progress;
    self.overlayTotalProgress.doubleValue = progress;
    NSTimeInterval elapsed = 0;
    if (self.receiveStartTime != nil) {
        elapsed = [[NSDate date] timeIntervalSinceDate:self.receiveStartTime];
    }
    NSInteger elapsedSec = MAX(0, (NSInteger)round(elapsed));
    NSInteger mm = elapsedSec / 60;
    NSInteger ss = elapsedSec % 60;
    self.overlayTotalTitle.stringValue = [NSString stringWithFormat:@"总进度 (%ld:%02ld)", (long)mm, (long)ss];
    if (self.currentIncomingName.length > 0) {
        self.overlayFileLabel.stringValue = [NSString stringWithFormat:@"%@ (%@)",
                                             self.currentIncomingName,
                                             [self formatBytes:totalBytes]];
    }
}

- (void)updatePeerInfo:(NSString *)info {
    self.peerInfoLabel.stringValue = info.length > 0 ? [NSString stringWithFormat:@"\u5bf9\u7aef: %@", info] : @"\u7b49\u5f85\u8fde\u63a5\u2026";
}

- (void)resetToIdleWithStatus:(NSString *)status {
    self.incomingNameLabel.stringValue = @"无接收任务";
    self.receiveStatusLabel.stringValue = status ?: @"等待对方发送…";
    self.receiveProgress.doubleValue = 0;
    self.saveAsButton.enabled = NO;
    self.rejectButton.enabled = NO;
    [self hideReceivingPanel];
    self.currentIncomingName = @"";
    self.currentIncomingSize = 0;
    self.receiveStartTime = nil;
}

@end

