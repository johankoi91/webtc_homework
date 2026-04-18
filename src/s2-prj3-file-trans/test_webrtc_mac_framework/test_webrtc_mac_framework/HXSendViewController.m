//
//  HXSendViewController.m
//  test_webrtc_mac_framework
//
//  Created by Cursor AI on 2026/3/17.
//

#import "HXSendViewController.h"

@interface HXDropZoneView : NSView
@property(nonatomic,copy) void (^onFileURL)(NSURL *url);
@end

@implementation HXDropZoneView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = 14;
        self.layer.masksToBounds = YES;
        self.layer.borderWidth = 1;
        self.layer.borderColor = [NSColor separatorColor].CGColor;
        self.layer.backgroundColor = [[NSColor colorWithCalibratedWhite:1 alpha:0.55] CGColor];
        [self registerForDraggedTypes:@[NSPasteboardTypeFileURL, @"public.file-url"]];
    }
    return self;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    self.layer.borderColor = [NSColor controlAccentColor].CGColor;
    return NSDragOperationCopy;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
    self.layer.borderColor = [NSColor separatorColor].CGColor;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    self.layer.borderColor = [NSColor separatorColor].CGColor;
    NSPasteboard *pb = sender.draggingPasteboard;

    NSString *s = [pb stringForType:NSPasteboardTypeFileURL];
    if (s.length == 0) {
        s = [pb stringForType:@"public.file-url"];
    }
    if (s.length == 0) { return NO; }

    NSURL *url = [NSURL URLWithString:s];
    if (url == nil) { return NO; }
    if (self.onFileURL) { self.onFileURL(url); }
    return YES;
}

@end

@interface HXChoiceCardButton : NSButton
@property(nonatomic,strong) NSImageView *cardIconView;
@property(nonatomic,strong) NSTextField *cardTitleLabel;
@end

@implementation HXChoiceCardButton

- (instancetype)initWithTitle:(NSString *)title symbol:(NSString *)symbol target:(id)target action:(SEL)action {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.bordered = NO;
        self.title = @"";
        self.target = target;
        self.action = action;

        self.wantsLayer = YES;
        self.layer.cornerRadius = 12;
        self.layer.masksToBounds = YES;
        self.layer.backgroundColor = [[NSColor colorWithCalibratedWhite:1 alpha:0.55] CGColor];
        self.layer.borderWidth = 1;
        self.layer.borderColor = [NSColor separatorColor].CGColor;

        _cardIconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _cardIconView.translatesAutoresizingMaskIntoConstraints = NO;
        _cardIconView.imageScaling = NSImageScaleProportionallyDown;
        _cardIconView.contentTintColor = [NSColor colorWithCalibratedRed:0.0 green:0.45 blue:0.42 alpha:1.0];
        NSImage *img = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:title];
        if (img != nil) {
            NSImageSymbolConfiguration *cfg =
                [NSImageSymbolConfiguration configurationWithPointSize:34 weight:NSFontWeightSemibold];
            _cardIconView.image = [img imageWithSymbolConfiguration:cfg] ?: img;
        }
        [self addSubview:_cardIconView];

        _cardTitleLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
        _cardTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _cardTitleLabel.editable = NO;
        _cardTitleLabel.bezeled = NO;
        _cardTitleLabel.drawsBackground = NO;
        _cardTitleLabel.selectable = NO;
        _cardTitleLabel.stringValue = title ?: @"";
        _cardTitleLabel.alignment = NSTextAlignmentCenter;
        _cardTitleLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
        _cardTitleLabel.textColor = [NSColor colorWithCalibratedRed:0.0 green:0.45 blue:0.42 alpha:1.0];
        [self addSubview:_cardTitleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_cardIconView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_cardIconView.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
            // Keep icon size fixed so label position is consistent across different symbols.
            [_cardIconView.widthAnchor constraintEqualToConstant:44],
            [_cardIconView.heightAnchor constraintEqualToConstant:44],

            [_cardTitleLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_cardTitleLabel.topAnchor constraintEqualToAnchor:_cardIconView.bottomAnchor constant:8],
            [_cardTitleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
            [_cardTitleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
            [_cardTitleLabel.heightAnchor constraintEqualToConstant:18],
        ]];
    }
    return self;
}

@end

@interface HXSendViewController ()

@property(nonatomic,strong) HXDropZoneView *dropZone;
@property(nonatomic,strong) NSTextField *selectedFileLabel;
@property(nonatomic,strong) NSTextField *sendStatusLabel;
@property(nonatomic,strong) NSProgressIndicator *sendProgress;
@property(nonatomic,strong) NSButton *chooseFileButton;
@property(nonatomic,strong) NSButton *chooseFolderButton;
@property(nonatomic,strong) NSButton *sendButton;
@property(nonatomic,strong) NSTableView *peersTableView;
@property(nonatomic,strong) NSScrollView *peersScrollView;
@property(nonatomic,copy) NSArray<NSDictionary *> *onlinePeers;
@property(nonatomic,strong) NSButton *cancelButton;

@property(nonatomic,strong) NSTextField *deviceStateLabel;
@property(nonatomic,strong) NSTextField *troubleshootTitle;
@property(nonatomic,strong) NSTextField *troubleshootHint;
@property(nonatomic,strong) NSView *selectedSummaryCard;
@property(nonatomic,strong) NSTextField *selectedCountLabel;
@property(nonatomic,strong) NSTextField *selectedSizeLabel;
@property(nonatomic,strong) NSButton *selectedCloseButton;
@property(nonatomic,strong) NSButton *selectedEditButton;
@property(nonatomic,strong) NSImageView *selectedPreviewIcon;
@property(nonatomic,strong) NSArray<NSView *> *chooseCardButtons;
@property(nonatomic,strong) NSLayoutConstraint *nearTitleTopFromCardsConstraint;
@property(nonatomic,strong) NSLayoutConstraint *nearTitleTopFromSelectedConstraint;

@property(nonatomic,assign) BOOL peerConnectedFlag;
@property(nonatomic,assign) BOOL isSending;
@property(nonatomic,assign) NSInteger selectedPeerRow;
/// 程序化刷新列表/恢复选中时，避免重复触发 `onSelectPeerIP`（否则会多次 pair_request）。
@property(nonatomic,assign) BOOL suppressPeerSelectActions;

@end

@implementation HXSendViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSZeroRect];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    fprintf(stderr, "[HXSendViewController] viewDidLoad start\n");
    [self buildUI];
    fprintf(stderr, "[HXSendViewController] buildUI done\n");
    self.onlinePeers = @[];
    [self applyOnlinePeers:@[]];
    fprintf(stderr, "[HXSendViewController] applyOnlinePeers (empty) done\n");
    self.selectedPeerRow = -1;
    [self updateSelectedSummaryMode];
    [self refreshEnabledState];
    fprintf(stderr, "[HXSendViewController] viewDidLoad end\n");
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
    fprintf(stderr, "[HXSendViewController] buildUI start\n");
    NSView *root = self.view;
    CGFloat pad = 34;
    NSColor *brandColor = [NSColor colorWithCalibratedRed:0.0 green:0.45 blue:0.42 alpha:1.0];

    // 选择区域标题
    NSTextField *chooseTitle = [[NSTextField alloc] initWithFrame:NSZeroRect];
    chooseTitle.translatesAutoresizingMaskIntoConstraints = NO;
    chooseTitle.editable = NO;
    chooseTitle.bezeled = NO;
    chooseTitle.drawsBackground = NO;
    chooseTitle.stringValue = @"选择";
    chooseTitle.font = [NSFont systemFontOfSize:18 weight:NSFontWeightBold];
    chooseTitle.textColor = brandColor;
    [root addSubview:chooseTitle];

    // 选择卡片（文件、文件夹）
    NSArray *selectItems = @[@{@"title": @"文件", @"symbol": @"doc.fill"},
                             @{@"title": @"文件夹", @"symbol": @"folder.fill"}];
    NSMutableArray<NSButton *> *selectButtons = [NSMutableArray array];

    // 使用卡片按钮样式（更贴近截图）
    for (NSInteger idx = 0; idx < (NSInteger)selectItems.count; idx++) {
        NSDictionary *item = selectItems[(NSUInteger)idx];
        NSString *title = item[@"title"];
        NSString *symbol = item[@"symbol"];

        SEL action = NULL;
        id target = nil;
        BOOL enabled = (idx == 0 || idx == 1);
        if (idx == 0) {
            target = self;
            action = @selector(onChooseFileTap:);
        } else if (idx == 1) {
            target = self;
            action = @selector(onChooseFolderTap:);
        }

        HXChoiceCardButton *btn = [[HXChoiceCardButton alloc] initWithTitle:title symbol:symbol target:target action:action];
        btn.enabled = enabled;
        [root addSubview:btn];
        [selectButtons addObject:btn];
    }

    self.chooseFileButton = selectButtons[0];
    self.chooseFolderButton = selectButtons[1];
    self.chooseCardButtons = [selectButtons copy];

    // 选择完成后的摘要卡片（默认隐藏）
    NSView *summaryCard = [[NSView alloc] initWithFrame:NSZeroRect];
    summaryCard.translatesAutoresizingMaskIntoConstraints = NO;
    summaryCard.wantsLayer = YES;
    summaryCard.layer.cornerRadius = 12;
    summaryCard.layer.masksToBounds = YES;
    summaryCard.layer.backgroundColor = [[NSColor colorWithCalibratedWhite:1 alpha:0.45] CGColor];
    summaryCard.layer.borderWidth = 1;
    summaryCard.layer.borderColor = [NSColor separatorColor].CGColor;
    summaryCard.hidden = YES;
    [root addSubview:summaryCard];
    self.selectedSummaryCard = summaryCard;

    self.selectedCloseButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    self.selectedCloseButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.selectedCloseButton.title = @"";
    self.selectedCloseButton.image = [NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"clear"];
    self.selectedCloseButton.imagePosition = NSImageOnly;
    self.selectedCloseButton.bordered = NO;
    self.selectedCloseButton.contentTintColor = [NSColor secondaryLabelColor];
    self.selectedCloseButton.target = self;
    self.selectedCloseButton.action = @selector(onClearSelectedFileTap:);
    [summaryCard addSubview:self.selectedCloseButton];

    NSTextField *selectedTitle = [self label:@"选择" size:34 weight:NSFontWeightBold color:[NSColor labelColor]];
    [summaryCard addSubview:selectedTitle];

    self.selectedCountLabel = [self label:@"文件: 1" size:12 weight:NSFontWeightRegular color:[NSColor labelColor]];
    [summaryCard addSubview:self.selectedCountLabel];
    self.selectedSizeLabel = [self label:@"大小: --" size:12 weight:NSFontWeightRegular color:[NSColor labelColor]];
    [summaryCard addSubview:self.selectedSizeLabel];

    self.selectedPreviewIcon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    self.selectedPreviewIcon.translatesAutoresizingMaskIntoConstraints = NO;
    self.selectedPreviewIcon.image = [NSImage imageWithSystemSymbolName:@"doc.fill" accessibilityDescription:nil];
    self.selectedPreviewIcon.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:24 weight:NSFontWeightSemibold];
    self.selectedPreviewIcon.contentTintColor = [NSColor whiteColor];
    self.selectedPreviewIcon.wantsLayer = YES;
    self.selectedPreviewIcon.layer.backgroundColor = [brandColor CGColor];
    self.selectedPreviewIcon.layer.cornerRadius = 10;
    self.selectedPreviewIcon.layer.masksToBounds = YES;
    [summaryCard addSubview:self.selectedPreviewIcon];

    self.selectedEditButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    self.selectedEditButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.selectedEditButton.title = @"编辑";
    self.selectedEditButton.bordered = NO;
    self.selectedEditButton.contentTintColor = [NSColor labelColor];
    self.selectedEditButton.target = self;
    self.selectedEditButton.action = @selector(onEditSelectedFileTap:);
    [summaryCard addSubview:self.selectedEditButton];

    [NSLayoutConstraint activateConstraints:@[
        [selectedTitle.leadingAnchor constraintEqualToAnchor:summaryCard.leadingAnchor constant:16],
        [selectedTitle.topAnchor constraintEqualToAnchor:summaryCard.topAnchor constant:14],

        [self.selectedCloseButton.trailingAnchor constraintEqualToAnchor:summaryCard.trailingAnchor constant:-12],
        [self.selectedCloseButton.topAnchor constraintEqualToAnchor:summaryCard.topAnchor constant:12],
        [self.selectedCloseButton.widthAnchor constraintEqualToConstant:22],
        [self.selectedCloseButton.heightAnchor constraintEqualToConstant:22],

        [self.selectedCountLabel.leadingAnchor constraintEqualToAnchor:selectedTitle.leadingAnchor],
        [self.selectedCountLabel.topAnchor constraintEqualToAnchor:selectedTitle.bottomAnchor constant:8],
        [self.selectedSizeLabel.leadingAnchor constraintEqualToAnchor:self.selectedCountLabel.leadingAnchor],
        [self.selectedSizeLabel.topAnchor constraintEqualToAnchor:self.selectedCountLabel.bottomAnchor constant:4],

        [self.selectedPreviewIcon.leadingAnchor constraintEqualToAnchor:selectedTitle.leadingAnchor],
        [self.selectedPreviewIcon.topAnchor constraintEqualToAnchor:self.selectedSizeLabel.bottomAnchor constant:14],
        [self.selectedPreviewIcon.widthAnchor constraintEqualToConstant:52],
        [self.selectedPreviewIcon.heightAnchor constraintEqualToConstant:52],

        [self.selectedEditButton.trailingAnchor constraintEqualToAnchor:summaryCard.trailingAnchor constant:-16],
        [self.selectedEditButton.bottomAnchor constraintEqualToAnchor:summaryCard.bottomAnchor constant:-20],
    ]];

    // 附近的设备区域
    NSTextField *nearTitle = [[NSTextField alloc] initWithFrame:NSZeroRect];
    nearTitle.translatesAutoresizingMaskIntoConstraints = NO;
    nearTitle.editable = NO;
    nearTitle.bezeled = NO;
    nearTitle.drawsBackground = NO;
    nearTitle.stringValue = @"附近的设备";
    nearTitle.font = [NSFont systemFontOfSize:18 weight:NSFontWeightBold];
    nearTitle.textColor = brandColor;
    [root addSubview:nearTitle];

    // 设备操作按钮（刷新、搜索、收藏、设置）
    NSArray *actionSymbols = @[@"arrow.clockwise", @"magnifyingglass", @"heart", @"gearshape"];
    NSMutableArray<NSButton *> *actionButtons = [NSMutableArray array];
    for (NSString *symbol in actionSymbols) {
      NSButton *btn = [[NSButton alloc] initWithFrame:NSZeroRect];
      btn.translatesAutoresizingMaskIntoConstraints = NO;
      btn.title = @"";
      NSImage *img = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
      if (img != nil) {
          NSImageSymbolConfiguration *cfg =
              [NSImageSymbolConfiguration configurationWithPointSize:16 weight:NSFontWeightRegular];
          img = [img imageWithSymbolConfiguration:cfg] ?: img;
      }
      btn.image = img;
      btn.imagePosition = NSImageOnly;
      btn.imageScaling = NSImageScaleProportionallyDown;
      btn.bezelStyle = NSBezelStyleRegularSquare;
      btn.bordered = NO;
      btn.contentTintColor = [NSColor secondaryLabelColor];
      [root addSubview:btn];
      [actionButtons addObject:btn];
    }
    if (actionButtons.count > 0) {
        actionButtons[0].target = self;
        actionButtons[0].action = @selector(onRefreshPeersTap:);
    }

    // 附近设备列表（信令实时推送，仅内存）
    self.peersScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.peersScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.peersScrollView.drawsBackground = NO;
    self.peersScrollView.hasVerticalScroller = YES;

    self.peersTableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.peersTableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.peersTableView.headerView = nil;
    self.peersTableView.dataSource = self;
    self.peersTableView.delegate = self;

    NSTableColumn *peerCol = [[NSTableColumn alloc] initWithIdentifier:@"peer"];
    peerCol.width = 220;
    [self.peersTableView addTableColumn:peerCol];
    self.peersTableView.allowsMultipleSelection = NO;
    self.peersTableView.allowsEmptySelection = YES;
    self.peersTableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
    self.peersTableView.rowHeight = 80;
    self.peersTableView.intercellSpacing = NSMakeSize(0, 8);

    self.peersScrollView.documentView = self.peersTableView;
    [root addSubview:self.peersScrollView];

    // 故障排除
    NSTextField *troubleTitle = [[NSTextField alloc] initWithFrame:NSZeroRect];
    troubleTitle.translatesAutoresizingMaskIntoConstraints = NO;
    troubleTitle.editable = NO;
    troubleTitle.bezeled = NO;
    troubleTitle.drawsBackground = NO;
    troubleTitle.stringValue = @"故障排除";
    troubleTitle.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    troubleTitle.textColor = brandColor;
    troubleTitle.alignment = NSTextAlignmentCenter;
    [root addSubview:troubleTitle];

    NSTextField *troubleHint = [[NSTextField alloc] initWithFrame:NSZeroRect];
    troubleHint.translatesAutoresizingMaskIntoConstraints = NO;
    troubleHint.editable = NO;
    troubleHint.bezeled = NO;
    troubleHint.drawsBackground = NO;
    troubleHint.stringValue = @"请确保目标连接的是同一个 Wi‑Fi 网络。";
    troubleHint.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
    troubleHint.textColor = [NSColor secondaryLabelColor];
    troubleHint.alignment = NSTextAlignmentCenter;
    [root addSubview:troubleHint];

    // 文件选择
    self.selectedFileLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.selectedFileLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.selectedFileLabel.editable = NO;
    self.selectedFileLabel.bezeled = NO;
    self.selectedFileLabel.drawsBackground = NO;
    self.selectedFileLabel.stringValue = @"未选择文件";
    self.selectedFileLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
    self.selectedFileLabel.textColor = [NSColor secondaryLabelColor];
    self.selectedFileLabel.maximumNumberOfLines = 1;
    self.selectedFileLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.selectedFileLabel.usesSingleLineMode = YES;
    [root addSubview:self.selectedFileLabel];

    self.sendStatusLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.sendStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.sendStatusLabel.editable = NO;
    self.sendStatusLabel.bezeled = NO;
    self.sendStatusLabel.drawsBackground = NO;
    self.sendStatusLabel.stringValue = @"";
    self.sendStatusLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
    self.sendStatusLabel.textColor = [NSColor secondaryLabelColor];
    self.sendStatusLabel.maximumNumberOfLines = 1;
    self.sendStatusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.sendStatusLabel.usesSingleLineMode = YES;
    self.sendStatusLabel.hidden = YES;
    [root addSubview:self.sendStatusLabel];

    // 进度条
    self.sendProgress = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    self.sendProgress.translatesAutoresizingMaskIntoConstraints = NO;
    self.sendProgress.indeterminate = NO;
    self.sendProgress.minValue = 0;
    self.sendProgress.maxValue = 1;
    self.sendProgress.doubleValue = 0;
    self.sendProgress.controlSize = NSControlSizeSmall;
    self.sendProgress.style = NSProgressIndicatorStyleBar;
    self.sendProgress.hidden = YES;
    [root addSubview:self.sendProgress];

    // 按钮
    self.sendButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    self.sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.sendButton.title = @"发送";
    self.sendButton.bezelStyle = NSBezelStyleTexturedRounded;
    self.sendButton.wantsLayer = YES;
    self.sendButton.layer.cornerRadius = 10;
    self.sendButton.layer.backgroundColor = [brandColor CGColor];
    self.sendButton.contentTintColor = [NSColor whiteColor];
    self.sendButton.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    self.sendButton.target = self;
    self.sendButton.action = @selector(onSendTap:);
    [root addSubview:self.sendButton];

    self.cancelButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    self.cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.cancelButton.title = @"取消";
    self.cancelButton.bezelStyle = NSBezelStyleTexturedRounded;
    self.cancelButton.wantsLayer = YES;
    self.cancelButton.layer.cornerRadius = 10;
    self.cancelButton.layer.masksToBounds = YES;
    self.cancelButton.layer.backgroundColor = [brandColor CGColor];
    self.cancelButton.contentTintColor = [NSColor whiteColor];
    self.cancelButton.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    self.cancelButton.target = self;
    self.cancelButton.action = @selector(onCancelTap:);
    self.cancelButton.enabled = NO;
    [root addSubview:self.cancelButton];

    // 约束
    [NSLayoutConstraint activateConstraints:@[
        [chooseTitle.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:pad],
        [chooseTitle.topAnchor constraintEqualToAnchor:root.topAnchor constant:42],
        
        [selectButtons[0].leadingAnchor constraintEqualToAnchor:chooseTitle.leadingAnchor],
        [selectButtons[0].topAnchor constraintEqualToAnchor:chooseTitle.bottomAnchor constant:14],
        [selectButtons[0].widthAnchor constraintEqualToConstant:80],
        [selectButtons[0].heightAnchor constraintEqualToConstant:100],
        
        [selectButtons[1].leadingAnchor constraintEqualToAnchor:selectButtons[0].trailingAnchor constant:12],
        [selectButtons[1].topAnchor constraintEqualToAnchor:selectButtons[0].topAnchor],
        [selectButtons[1].widthAnchor constraintEqualToConstant:80],
        [selectButtons[1].heightAnchor constraintEqualToConstant:100],
        
        [summaryCard.leadingAnchor constraintEqualToAnchor:chooseTitle.leadingAnchor],
        [summaryCard.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-pad],
        [summaryCard.topAnchor constraintEqualToAnchor:chooseTitle.bottomAnchor constant:8],
        [summaryCard.heightAnchor constraintEqualToConstant:210],
        
        // 选择卡片下方的操作图标（截图中的一排）
        [actionButtons[0].centerYAnchor constraintEqualToAnchor:nearTitle.centerYAnchor],
        [actionButtons[0].trailingAnchor constraintEqualToAnchor:actionButtons[1].leadingAnchor constant:-12],
        [actionButtons[0].widthAnchor constraintEqualToConstant:22],
        [actionButtons[0].heightAnchor constraintEqualToConstant:22],

        [actionButtons[1].centerYAnchor constraintEqualToAnchor:nearTitle.centerYAnchor],
        [actionButtons[1].trailingAnchor constraintEqualToAnchor:actionButtons[2].leadingAnchor constant:-12],
        [actionButtons[1].widthAnchor constraintEqualToConstant:22],
        [actionButtons[1].heightAnchor constraintEqualToConstant:22],

        [actionButtons[2].centerYAnchor constraintEqualToAnchor:nearTitle.centerYAnchor],
        [actionButtons[2].trailingAnchor constraintEqualToAnchor:actionButtons[3].leadingAnchor constant:-12],
        [actionButtons[2].widthAnchor constraintEqualToConstant:22],
        [actionButtons[2].heightAnchor constraintEqualToConstant:22],

        [actionButtons[3].centerYAnchor constraintEqualToAnchor:nearTitle.centerYAnchor],
        [actionButtons[3].trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-pad],
        [actionButtons[3].widthAnchor constraintEqualToConstant:22],
        [actionButtons[3].heightAnchor constraintEqualToConstant:22],

        [nearTitle.leadingAnchor constraintEqualToAnchor:chooseTitle.leadingAnchor],
        
        [self.peersScrollView.leadingAnchor constraintEqualToAnchor:nearTitle.leadingAnchor],
        [self.peersScrollView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-pad],
        [self.peersScrollView.topAnchor constraintEqualToAnchor:nearTitle.bottomAnchor constant:12],
        [self.peersScrollView.heightAnchor constraintEqualToConstant:192],
        
        [troubleTitle.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],
        [troubleTitle.topAnchor constraintEqualToAnchor:self.peersScrollView.bottomAnchor constant:24],
        
        [troubleHint.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],
        [troubleHint.topAnchor constraintEqualToAnchor:troubleTitle.bottomAnchor constant:10],
        
        [self.selectedFileLabel.leadingAnchor constraintEqualToAnchor:nearTitle.leadingAnchor],
        [self.selectedFileLabel.topAnchor constraintEqualToAnchor:troubleHint.bottomAnchor constant:36],
        
        [self.sendStatusLabel.leadingAnchor constraintEqualToAnchor:self.selectedFileLabel.leadingAnchor],
        [self.sendStatusLabel.topAnchor constraintEqualToAnchor:self.selectedFileLabel.bottomAnchor constant:10],
        
        [self.sendProgress.leadingAnchor constraintEqualToAnchor:self.selectedFileLabel.leadingAnchor],
        [self.sendProgress.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-pad],
        [self.sendProgress.topAnchor constraintEqualToAnchor:self.sendStatusLabel.bottomAnchor constant:10],
        
        [self.sendButton.leadingAnchor constraintEqualToAnchor:self.selectedFileLabel.leadingAnchor],
        [self.sendButton.heightAnchor constraintEqualToConstant:34],
        [self.sendButton.widthAnchor constraintEqualToConstant:92],
        [self.sendButton.topAnchor constraintEqualToAnchor:self.sendProgress.bottomAnchor constant:16],
        [self.sendButton.bottomAnchor constraintLessThanOrEqualToAnchor:root.bottomAnchor constant:-34],
        
        [self.cancelButton.leadingAnchor constraintEqualToAnchor:self.sendButton.trailingAnchor constant:12],
        [self.cancelButton.heightAnchor constraintEqualToAnchor:self.sendButton.heightAnchor],
        [self.cancelButton.widthAnchor constraintEqualToAnchor:self.sendButton.widthAnchor],
        [self.cancelButton.centerYAnchor constraintEqualToAnchor:self.sendButton.centerYAnchor],
    ]];

    self.nearTitleTopFromCardsConstraint =
        [nearTitle.topAnchor constraintEqualToAnchor:selectButtons[0].bottomAnchor constant:28];
    self.nearTitleTopFromSelectedConstraint =
        [nearTitle.topAnchor constraintEqualToAnchor:summaryCard.bottomAnchor constant:18];
    self.nearTitleTopFromCardsConstraint.active = YES;
    
    fprintf(stderr, "[HXSendViewController] buildUI done\n");
}

- (void)onChooseFileTap:(id)sender { if (self.onChooseFile) { self.onChooseFile(); } }
- (void)onChooseFolderTap:(id)sender { if (self.onChooseFolder) { self.onChooseFolder(); } }
- (void)onSendTap:(id)sender { if (self.onSend) { self.onSend(); } }
- (void)onCancelTap:(id)sender { if (self.onCancel) { self.onCancel(); } }
- (void)onTapDeviceCard:(id)sender { if (self.onTapDevice) { self.onTapDevice(); } }
- (void)onRefreshPeersTap:(id)sender { if (self.onRefreshPeers) { self.onRefreshPeers(); } }
- (void)onEditSelectedFileTap:(id)sender { if (self.onChooseFile) { self.onChooseFile(); } }
- (void)onClearSelectedFileTap:(id)sender {
    self.selectedFileURL = nil;
    [self setSelectedFileName:nil];
    [self setSendStatusText:@""];
}

- (void)updateSelectedSummaryMode {
    BOOL hasFile = (self.selectedFileURL != nil && ![self.selectedFileURL hasDirectoryPath]);
    self.selectedSummaryCard.hidden = !hasFile;
    for (NSView *v in self.chooseCardButtons) {
        v.hidden = hasFile;
    }
    self.nearTitleTopFromCardsConstraint.active = !hasFile;
    self.nearTitleTopFromSelectedConstraint.active = hasFile;

    // The selected-summary card replaces the old bottom transfer strip in this mode.
    self.selectedFileLabel.hidden = hasFile;
    // Keep progress/status visible while sending, even in selected-summary mode.
    BOOL shouldShowProgress = self.isSending;
    self.sendStatusLabel.hidden = !shouldShowProgress;
    self.sendProgress.hidden = !shouldShowProgress;
    // Keep action buttons visible after file selection.
    self.sendButton.hidden = NO;
    self.cancelButton.hidden = NO;

    if (!hasFile) { return; }
    self.selectedCountLabel.stringValue = @"文件: 1";
    NSNumber *fileSizeNum = nil;
    [self.selectedFileURL getResourceValue:&fileSizeNum forKey:NSURLFileSizeKey error:nil];
    uint64_t fileSize = (uint64_t)fileSizeNum.unsignedLongLongValue;
    self.selectedSizeLabel.stringValue = [NSString stringWithFormat:@"大小: %@", [self formatBytes:fileSize]];
}

- (void)setPeerConnected:(BOOL)connected {
    self.peerConnectedFlag = connected;
    if (!connected) {
        self.deviceStateLabel.stringValue = @"未连接";
    }
    [self refreshEnabledState];
}

- (void)setSendStatusText:(NSString *)text {
    self.sendStatusLabel.stringValue = text ?: @"";
    BOOL hasFile = (self.selectedFileURL != nil && ![self.selectedFileURL hasDirectoryPath]);
    self.sendStatusLabel.hidden = (!self.isSending && hasFile) || (text.length == 0);
}

- (void)setSelectedFileName:(NSString *)name {
    self.selectedFileLabel.stringValue = name ?: @"未选择文件";
    if (name.length == 0) {
        self.sendStatusLabel.hidden = YES;
        self.sendProgress.hidden = YES;
    }
    [self updateSelectedSummaryMode];
    [self refreshEnabledState];
}


- (void)applyOnlinePeers:(NSArray<NSDictionary *> *)peers {
    NSString *prevIP = [self currentSelectedPeerIP];

    NSMutableArray<NSDictionary *> *norm = [NSMutableArray array];
    for (id obj in peers ?: @[]) {
        if (![obj isKindOfClass:[NSDictionary class]]) { continue; }
        NSDictionary *p = (NSDictionary *)obj;
        NSString *ip = [p[@"ip"] isKindOfClass:[NSString class]] ? p[@"ip"] : @"";
        if (ip.length == 0) { continue; }
        NSString *name = [p[@"name"] isKindOfClass:[NSString class]] ? p[@"name"] : @"";
        if (name.length == 0) { name = ip; }
        [norm addObject:@{ @"ip": ip, @"name": name, @"online": @YES }];
    }

    self.onlinePeers = [norm copy];

    NSInteger newRow = -1;
    if (prevIP.length > 0) {
        for (NSInteger i = 0; i < (NSInteger)self.onlinePeers.count; i++) {
            NSString *ip = [self.onlinePeers[(NSUInteger)i][@"ip"] isKindOfClass:[NSString class]]
                ? self.onlinePeers[(NSUInteger)i][@"ip"] : @"";
            if ([ip isEqualToString:prevIP]) {
                newRow = i;
                break;
            }
        }
    }

    // 必须先 reloadData 再选中：`reloadData` 会重建行，若在之前 select，选中状态常被清掉，
    // 导致 `selectedPeerRow` / `currentSelectedPeerIP` 丢失，发送端无法配对。
    self.suppressPeerSelectActions = YES;
    [self.peersTableView reloadData];
    self.selectedPeerRow = newRow;
    if (newRow >= 0) {
        [self.peersTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)newRow] byExtendingSelection:NO];
    } else {
        [self.peersTableView deselectAll:nil];
    }
    [self.peersTableView reloadData];
    self.suppressPeerSelectActions = NO;
}

- (nullable NSString *)currentSelectedPeerIP {
    NSInteger row = self.selectedPeerRow;
    if (row < 0 || row >= (NSInteger)self.onlinePeers.count) { return nil; }
    NSDictionary *peer = self.onlinePeers[(NSUInteger)row];
    NSString *ip = [peer[@"ip"] isKindOfClass:[NSString class]] ? peer[@"ip"] : nil;
    return ip.length > 0 ? ip : nil;
}

- (void)updatePeerInfo:(NSString *)info {
    // info 来自容器：`name + "  " + ip`。截图发送页只显示 name。
    if (info.length == 0) { return; }
    NSArray<NSString *> *parts = [info componentsSeparatedByString:@"  "];
    NSString *namePart = parts.count > 0 ? parts[0] : info;
    namePart = [namePart stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (namePart.length > 0) {
        self.deviceStateLabel.stringValue = namePart;
    }
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


- (void)setSendProgress:(double)progress bytesSent:(uint64_t)bytesSent totalBytes:(uint64_t)totalBytes {
    self.sendProgress.hidden = NO;
    self.sendProgress.doubleValue = progress;
    self.sendStatusLabel.stringValue =
        [NSString stringWithFormat:@"发送 %@ / %@ (%.0f%%)",
         [self formatBytes:bytesSent], [self formatBytes:totalBytes], progress * 100.0];
    self.sendStatusLabel.hidden = NO;
}

- (void)refreshEnabledState {
    BOOL hasFile = (self.selectedFileURL != nil && ![self.selectedFileURL hasDirectoryPath]);
    // Allow tapping send after file selection; connection readiness is handled in container onSend.
    self.sendButton.enabled = (hasFile && !self.isSending);
    self.cancelButton.enabled = self.isSending;
    
    self.troubleshootTitle.hidden = self.peerConnectedFlag;
    self.troubleshootHint.hidden = self.peerConnectedFlag;
}

- (void)setSendingInProgress:(BOOL)sending {
    self.isSending = sending;
    [self refreshEnabledState];
    if (!sending) {
        self.sendProgress.doubleValue = 0;
        self.sendProgress.hidden = YES;
        self.sendStatusLabel.hidden = YES;
    } else {
        self.sendProgress.hidden = NO;
        self.sendStatusLabel.hidden = NO;
    }
}


#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)self.onlinePeers.count;
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSDictionary *peer = self.onlinePeers[(NSUInteger)row];
    NSString *name = [peer[@"name"] isKindOfClass:[NSString class]] ? peer[@"name"] : @"Unknown";
    NSString *ip = [peer[@"ip"] isKindOfClass:[NSString class]] ? peer[@"ip"] : @"unknown";
    NSString *subtitle = [NSString stringWithFormat:@"在线 · %@", ip];
    
    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"peer" owner:self];
    if (cell == nil) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = @"peer";

        NSView *card = [[NSView alloc] initWithFrame:NSZeroRect];
        card.translatesAutoresizingMaskIntoConstraints = NO;
        card.wantsLayer = YES;
        card.layer.cornerRadius = 12;
        card.layer.masksToBounds = YES;
        card.layer.backgroundColor = [[NSColor colorWithCalibratedWhite:1 alpha:0.6] CGColor];
        card.layer.borderWidth = 1;
        card.layer.borderColor = [NSColor separatorColor].CGColor;
        [cell addSubview:card];

        NSImageView *icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        icon.image = [NSImage imageWithSystemSymbolName:@"iphone" accessibilityDescription:nil];
        icon.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:34 weight:NSFontWeightRegular];
        icon.contentTintColor = [NSColor secondaryLabelColor];
        [card addSubview:icon];

        NSTextField *nameLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
        nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        nameLabel.editable = NO;
        nameLabel.bezeled = NO;
        nameLabel.drawsBackground = NO;
        nameLabel.font = [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];
        nameLabel.textColor = [NSColor labelColor];
        [card addSubview:nameLabel];
        nameLabel.tag = 100;

        NSTextField *ipLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
        ipLabel.translatesAutoresizingMaskIntoConstraints = NO;
        ipLabel.editable = NO;
        ipLabel.bezeled = NO;
        ipLabel.drawsBackground = NO;
        ipLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
        ipLabel.textColor = [NSColor secondaryLabelColor];
        [card addSubview:ipLabel];
        ipLabel.tag = 101;

        NSButton *heart = [[NSButton alloc] initWithFrame:NSZeroRect];
        heart.translatesAutoresizingMaskIntoConstraints = NO;
        heart.title = @"";
        heart.image = [NSImage imageWithSystemSymbolName:@"heart" accessibilityDescription:nil];
        heart.imagePosition = NSImageOnly;
        heart.bordered = NO;
        heart.contentTintColor = [NSColor secondaryLabelColor];
        heart.enabled = NO;
        [card addSubview:heart];

        [NSLayoutConstraint activateConstraints:@[
            [card.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor],
            [card.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor],
            [card.topAnchor constraintEqualToAnchor:cell.topAnchor],
            [card.bottomAnchor constraintEqualToAnchor:cell.bottomAnchor],

            [icon.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
            [icon.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],

            [nameLabel.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12],
            [nameLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:12],
            [ipLabel.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor],
            [ipLabel.topAnchor constraintEqualToAnchor:nameLabel.bottomAnchor constant:4],

            [heart.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
            [heart.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
            [heart.widthAnchor constraintEqualToConstant:20],
            [heart.heightAnchor constraintEqualToConstant:20],
        ]];
    }
    
    NSView *card = cell.subviews.count > 0 ? cell.subviews.firstObject : nil;
    NSTextField *nameLabel = [card viewWithTag:100];
    NSTextField *ipLabel = [card viewWithTag:101];
    nameLabel.stringValue = name;
    ipLabel.stringValue = subtitle;

    BOOL selected = (row == self.selectedPeerRow);
    if (selected) {
        card.layer.backgroundColor = [[NSColor colorWithCalibratedRed:0.76 green:0.88 blue:0.86 alpha:1.0] CGColor];
        card.layer.borderColor = [[NSColor colorWithCalibratedRed:0.0 green:0.45 blue:0.42 alpha:0.35] CGColor];
        nameLabel.textColor = [NSColor colorWithCalibratedRed:0.0 green:0.35 blue:0.32 alpha:1.0];
    } else {
        card.layer.backgroundColor = [[NSColor colorWithCalibratedWhite:1 alpha:0.6] CGColor];
        card.layer.borderColor = [NSColor separatorColor].CGColor;
        nameLabel.textColor = [NSColor labelColor];
    }
    
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = self.peersTableView.selectedRow;
    self.selectedPeerRow = row;
    if (self.suppressPeerSelectActions) {
        [self.peersTableView reloadData];
        return;
    }
    if (row >= 0 && row < (NSInteger)self.onlinePeers.count) {
        NSDictionary *peer = self.onlinePeers[(NSUInteger)row];
        NSString *name = peer[@"name"] ?: @"Unknown";
        NSString *ip = peer[@"ip"] ?: @"";

        self.deviceStateLabel.stringValue = name;
        if (self.onSelectPeerIP) {
            self.onSelectPeerIP(ip);
        }
    }
    [self.peersTableView reloadData];
}


@end
