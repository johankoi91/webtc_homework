//
//  AppDelegate.m
//  webrtc_file_sender
//
//  Created by Peter Liu on 2026/3/2.
//

#import "AppDelegate.h"
#import "RTCClient.h"
#import "HXAirDropStyleTransferViewController.h"

@interface AppDelegate ()

@property (strong) IBOutlet NSWindow *window;

@property(nonatomic,strong) RTCClient *rtcClient;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    self.rtcClient = [[RTCClient alloc] init];
    [self.rtcClient start];

    HXAirDropStyleTransferViewController *vc =
        [[HXAirDropStyleTransferViewController alloc] initWithRTCClient:self.rtcClient];
    self.window.contentViewController = vc;

    // Window polish: closer to LocalSend
    self.window.title = @"LocalSend";
    self.window.titleVisibility = NSWindowTitleHidden;
    self.window.titlebarAppearsTransparent = YES;
    self.window.minSize = NSMakeSize(760, 520);

    // 设置合理的初始尺寸并居中（XIB 默认 480x360 太小）
    [self.window setContentSize:NSMakeSize(980, 620)];
    [self.window center];

    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

@end
