#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <ServiceManagement/ServiceManagement.h>
#import <math.h>

static NSString * const FVEnabledKey = @"enabled";
static NSString * const FVDimmingAmountKey = @"dimmingAmount";
static NSString * const FVGitHubURLString = @"https://github.com/Steirch/FocusVeil";

static void FVRegisterDefaults(void) {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        FVEnabledKey: @YES,
        FVDimmingAmountKey: @0.42
    }];
}

static BOOL FVIsEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:FVEnabledKey];
}

static void FVSetEnabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:FVEnabledKey];
}

static CGFloat FVDimmingAmount(void) {
    double value = [[NSUserDefaults standardUserDefaults] doubleForKey:FVDimmingAmountKey];
    return MIN(MAX(value, 0.08), 0.82);
}

static void FVSetDimmingAmount(CGFloat amount) {
    amount = MIN(MAX(amount, 0.08), 0.82);
    [[NSUserDefaults standardUserDefaults] setDouble:amount forKey:FVDimmingAmountKey];
}

static BOOL FVAccessibilityWindowFrame(pid_t processIdentifier, CGRect *result) {
    AXUIElementRef applicationElement = AXUIElementCreateApplication(processIdentifier);
    CFTypeRef windowReference = NULL;
    AXError windowError = AXUIElementCopyAttributeValue(
        applicationElement,
        kAXFocusedWindowAttribute,
        &windowReference
    );
    CFRelease(applicationElement);

    if (windowError != kAXErrorSuccess || windowReference == NULL) {
        return NO;
    }

    AXUIElementRef windowElement = (AXUIElementRef)windowReference;
    CFTypeRef positionReference = NULL;
    CFTypeRef sizeReference = NULL;

    AXError positionError = AXUIElementCopyAttributeValue(
        windowElement,
        kAXPositionAttribute,
        &positionReference
    );
    AXError sizeError = AXUIElementCopyAttributeValue(
        windowElement,
        kAXSizeAttribute,
        &sizeReference
    );
    CFRelease(windowReference);

    if (
        positionError != kAXErrorSuccess ||
        sizeError != kAXErrorSuccess ||
        positionReference == NULL ||
        sizeReference == NULL
    ) {
        if (positionReference) {
            CFRelease(positionReference);
        }
        if (sizeReference) {
            CFRelease(sizeReference);
        }
        return NO;
    }

    AXValueRef positionValue = (AXValueRef)positionReference;
    AXValueRef sizeValue = (AXValueRef)sizeReference;
    CGPoint position = CGPointZero;
    CGSize size = CGSizeZero;

    BOOL valid = AXValueGetType(positionValue) == kAXValueCGPointType
        && AXValueGetType(sizeValue) == kAXValueCGSizeType
        && AXValueGetValue(positionValue, kAXValueCGPointType, &position)
        && AXValueGetValue(sizeValue, kAXValueCGSizeType, &size);

    CFRelease(positionReference);
    CFRelease(sizeReference);

    if (!valid || size.width <= 40 || size.height <= 40) {
        return NO;
    }

    *result = CGRectMake(position.x, position.y, size.width, size.height);
    return YES;
}

static BOOL FVRectApproximatelyEqual(CGRect first, CGRect second) {
    CGFloat tolerance = 12.0;
    return fabs(CGRectGetMinX(first) - CGRectGetMinX(second)) <= tolerance
        && fabs(CGRectGetMinY(first) - CGRectGetMinY(second)) <= tolerance
        && fabs(CGRectGetWidth(first) - CGRectGetWidth(second)) <= tolerance
        && fabs(CGRectGetHeight(first) - CGRectGetHeight(second)) <= tolerance;
}

static BOOL FVWindowNumberForProcess(pid_t processIdentifier, CGWindowID *result) {
    CGRect focusedFrame = CGRectZero;
    BOOL hasFocusedFrame = FVAccessibilityWindowFrame(processIdentifier, &focusedFrame);

    CFArrayRef windowListReference = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
        kCGNullWindowID
    );
    if (windowListReference == NULL) {
        return NO;
    }

    NSArray<NSDictionary *> *windowList = CFBridgingRelease(windowListReference);
    NSString *ownerKey = (__bridge NSString *)kCGWindowOwnerPID;
    NSString *layerKey = (__bridge NSString *)kCGWindowLayer;
    NSString *numberKey = (__bridge NSString *)kCGWindowNumber;
    NSString *boundsKey = (__bridge NSString *)kCGWindowBounds;
    NSString *alphaKey = (__bridge NSString *)kCGWindowAlpha;
    CGWindowID firstWindowNumber = 0;

    for (NSDictionary *window in windowList) {
        NSNumber *owner = window[ownerKey];
        NSNumber *layer = window[layerKey];
        NSNumber *windowNumber = window[numberKey];
        NSNumber *alpha = window[alphaKey];
        NSDictionary *bounds = window[boundsKey];
        CGRect frame = CGRectZero;

        if (
            owner.intValue == processIdentifier &&
            layer.integerValue == 0 &&
            windowNumber != nil &&
            alpha.doubleValue > 0.01 &&
            bounds != nil &&
            CGRectMakeWithDictionaryRepresentation(
                (__bridge CFDictionaryRef)bounds,
                &frame
            ) &&
            frame.size.width > 40 &&
            frame.size.height > 40
        ) {
            if (firstWindowNumber == 0) {
                firstWindowNumber = windowNumber.unsignedIntValue;
            }
            if (hasFocusedFrame && FVRectApproximatelyEqual(frame, focusedFrame)) {
                *result = windowNumber.unsignedIntValue;
                return YES;
            }
        }
    }

    if (firstWindowNumber != 0) {
        *result = firstWindowNumber;
        return YES;
    }

    return NO;
}

@interface FVDimmingView : NSView
@property(nonatomic) CGFloat dimmingAmount;
@end

@implementation FVDimmingView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _dimmingAmount = 0.42;
    }
    return self;
}

- (BOOL)isOpaque {
    return NO;
}

- (void)setDimmingAmount:(CGFloat)dimmingAmount {
    _dimmingAmount = dimmingAmount;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor colorWithCalibratedWhite:0 alpha:self.dimmingAmount] setFill];
    NSRectFillUsingOperation(self.bounds, NSCompositingOperationSourceOver);
}

@end

@interface FVOverlayPanel : NSPanel
- (instancetype)initWithScreen:(NSScreen *)screen;
@end

@implementation FVOverlayPanel

- (instancetype)initWithScreen:(NSScreen *)screen {
    self = [super initWithContentRect:screen.frame
                           styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                             backing:NSBackingStoreBuffered
                               defer:NO
                              screen:screen];
    if (self) {
        [self setFrame:screen.frame display:NO];
        self.level = NSNormalWindowLevel;
        self.backgroundColor = NSColor.clearColor;
        self.opaque = NO;
        self.hasShadow = NO;
        self.ignoresMouseEvents = YES;
        self.hidesOnDeactivate = NO;
        self.releasedWhenClosed = NO;
        self.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces
            | NSWindowCollectionBehaviorFullScreenAuxiliary
            | NSWindowCollectionBehaviorStationary
            | NSWindowCollectionBehaviorIgnoresCycle;
    }
    return self;
}

- (BOOL)canBecomeKeyWindow {
    return NO;
}

- (BOOL)canBecomeMainWindow {
    return NO;
}

@end

@interface FVOverlay : NSObject
- (instancetype)initWithScreen:(NSScreen *)screen dimmingAmount:(CGFloat)amount;
- (void)showBelowWindowNumber:(CGWindowID)windowNumber;
- (void)hide;
- (void)updateDimmingAmount:(CGFloat)amount;
@end

@implementation FVOverlay {
    FVOverlayPanel *_panel;
    FVDimmingView *_dimmingView;
}

- (instancetype)initWithScreen:(NSScreen *)screen dimmingAmount:(CGFloat)amount {
    self = [super init];
    if (self) {
        _panel = [[FVOverlayPanel alloc] initWithScreen:screen];
        _dimmingView = [[FVDimmingView alloc] initWithFrame:(CGRect){
            .origin = CGPointZero,
            .size = screen.frame.size
        }];
        _dimmingView.dimmingAmount = amount;
        _panel.contentView = _dimmingView;
    }
    return self;
}

- (void)showBelowWindowNumber:(CGWindowID)windowNumber {
    _panel.alphaValue = 1;
    [_panel orderWindow:NSWindowBelow relativeTo:(NSInteger)windowNumber];
}

- (void)hide {
    if (!_panel.visible) {
        return;
    }

    _panel.alphaValue = 1;
    [_panel orderOut:nil];
}

- (void)updateDimmingAmount:(CGFloat)amount {
    _dimmingView.dimmingAmount = amount;
}

@end

@interface FVFocusController : NSObject
@property(nonatomic, readonly) BOOL accessibilityTrusted;
@property(nonatomic, getter=isPaused) BOOL paused;
- (void)start;
- (void)stop;
- (void)setEnabled:(BOOL)enabled;
- (void)setDimmingAmount:(CGFloat)amount;
@end

@implementation FVFocusController {
    NSMutableArray<FVOverlay *> *_overlays;
    NSTimer *_refreshTimer;
    CGWindowID _lastWindowNumber;
    BOOL _hasLastWindow;
    pid_t _ownProcessIdentifier;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _overlays = [NSMutableArray array];
        _ownProcessIdentifier = NSProcessInfo.processInfo.processIdentifier;
        _lastWindowNumber = 0;
        _hasLastWindow = NO;
        _paused = NO;
    }
    return self;
}

- (BOOL)accessibilityTrusted {
    return AXIsProcessTrusted();
}

- (void)start {
    [self rebuildOverlays];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(screenParametersDidChange:)
                                               name:NSApplicationDidChangeScreenParametersNotification
                                             object:nil];

    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self
                                                        selector:@selector(activeApplicationDidChange:)
                                                            name:NSWorkspaceDidActivateApplicationNotification
                                                          object:nil];

    _refreshTimer = [NSTimer timerWithTimeInterval:0.10
                                           target:self
                                         selector:@selector(refresh:)
                                         userInfo:nil
                                          repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:_refreshTimer forMode:NSRunLoopCommonModes];
    [self refresh:nil];
}

- (void)stop {
    [_refreshTimer invalidate];
    _refreshTimer = nil;
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    for (FVOverlay *overlay in _overlays) {
        [overlay hide];
    }
}

- (void)setEnabled:(BOOL)enabled {
    FVSetEnabled(enabled);
    [self refresh:nil];
}

- (void)setPaused:(BOOL)paused {
    _paused = paused;
    [self refresh:nil];
}

- (void)setDimmingAmount:(CGFloat)amount {
    FVSetDimmingAmount(amount);
    for (FVOverlay *overlay in _overlays) {
        [overlay updateDimmingAmount:FVDimmingAmount()];
    }
}

- (void)screenParametersDidChange:(NSNotification *)notification {
    [self rebuildOverlays];
    [self refresh:nil];
}

- (void)activeApplicationDidChange:(NSNotification *)notification {
    [self refresh:nil];
}

- (void)refresh:(NSTimer *)timer {
    if (!FVIsEnabled() || self.isPaused) {
        for (FVOverlay *overlay in _overlays) {
            [overlay hide];
        }
        return;
    }

    NSRunningApplication *frontmostApplication =
        NSWorkspace.sharedWorkspace.frontmostApplication;

    if (
        frontmostApplication &&
        frontmostApplication.processIdentifier != _ownProcessIdentifier
    ) {
        CGWindowID windowNumber = 0;
        if (FVWindowNumberForProcess(frontmostApplication.processIdentifier, &windowNumber)) {
            _lastWindowNumber = windowNumber;
            _hasLastWindow = YES;
        } else {
            _lastWindowNumber = 0;
            _hasLastWindow = NO;
        }
    }

    if (!_hasLastWindow) {
        for (FVOverlay *overlay in _overlays) {
            [overlay hide];
        }
        return;
    }

    for (FVOverlay *overlay in _overlays) {
        [overlay showBelowWindowNumber:_lastWindowNumber];
    }
}

- (void)rebuildOverlays {
    for (FVOverlay *overlay in _overlays) {
        [overlay hide];
    }
    [_overlays removeAllObjects];

    for (NSScreen *screen in NSScreen.screens) {
        FVOverlay *overlay = [[FVOverlay alloc] initWithScreen:screen
                                              dimmingAmount:FVDimmingAmount()];
        [_overlays addObject:overlay];
    }
}

@end

@interface FVAppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@end

@implementation FVAppDelegate {
    FVFocusController *_focusController;
    NSStatusItem *_statusItem;
    NSMenuItem *_enabledItem;
    NSMenuItem *_permissionItem;
    NSMenuItem *_launchAtLoginItem;
    NSSlider *_intensitySlider;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _focusController = [[FVFocusController alloc] init];
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self configureStatusItem];
    [_focusController start];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [_focusController stop];
}

- (void)configureStatusItem {
    _statusItem = [NSStatusBar.systemStatusBar
        statusItemWithLength:NSVariableStatusItemLength];
    _statusItem.button.image = [NSImage
        imageWithSystemSymbolName:@"circle.lefthalf.filled"
        accessibilityDescription:@"FocusVeil"];
    _statusItem.button.image.template = YES;

    NSMenu *menu = [[NSMenu alloc] init];
    menu.delegate = self;

    _enabledItem = [[NSMenuItem alloc] initWithTitle:@"启用背景压暗"
                                             action:@selector(toggleEnabled:)
                                      keyEquivalent:@""];
    _enabledItem.target = self;
    [menu addItem:_enabledItem];

    [menu addItem:[self intensityMenuItem]];
    [menu addItem:NSMenuItem.separatorItem];

    _permissionItem = [[NSMenuItem alloc] initWithTitle:@"辅助功能权限"
                                                  action:@selector(openAccessibilitySettings:)
                                           keyEquivalent:@""];
    _permissionItem.target = self;
    [menu addItem:_permissionItem];

    _launchAtLoginItem = [[NSMenuItem alloc] initWithTitle:@"登录时启动"
                                                    action:@selector(toggleLaunchAtLogin:)
                                             keyEquivalent:@""];
    _launchAtLoginItem.target = self;
    [menu addItem:_launchAtLoginItem];

    [menu addItem:NSMenuItem.separatorItem];

    NSMenuItem *aboutItem = [[NSMenuItem alloc] initWithTitle:@"关于 FocusVeil"
                                                       action:@selector(showAbout:)
                                                keyEquivalent:@""];
    aboutItem.target = self;
    [menu addItem:aboutItem];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"退出 FocusVeil"
                                                      action:@selector(quitApplication:)
                                               keyEquivalent:@"q"];
    quitItem.target = self;
    [menu addItem:quitItem];

    _statusItem.menu = menu;
    [self updateMenuState];
}

- (NSMenuItem *)intensityMenuItem {
    NSMenuItem *menuItem = [[NSMenuItem alloc] init];
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 248, 52)];

    NSTextField *label = [NSTextField labelWithString:@"背景压暗强度"];
    label.frame = NSMakeRect(16, 30, 216, 17);
    label.font = [NSFont menuFontOfSize:13];

    _intensitySlider = [[NSSlider alloc] initWithFrame:NSMakeRect(14, 5, 220, 24)];
    _intensitySlider.minValue = 0.08;
    _intensitySlider.maxValue = 0.82;
    _intensitySlider.doubleValue = FVDimmingAmount();
    _intensitySlider.continuous = YES;
    _intensitySlider.target = self;
    _intensitySlider.action = @selector(intensityDidChange:);

    [container addSubview:label];
    [container addSubview:_intensitySlider];
    menuItem.view = container;
    return menuItem;
}

- (void)menuWillOpen:(NSMenu *)menu {
    [self updateMenuState];
}

- (void)updateMenuState {
    BOOL active = FVIsEnabled() && !_focusController.isPaused;
    _enabledItem.state = active ? NSControlStateValueOn : NSControlStateValueOff;
    _intensitySlider.doubleValue = FVDimmingAmount();

    BOOL trusted = _focusController.accessibilityTrusted;
    _permissionItem.title = trusted
        ? @"辅助功能权限已启用"
        : @"打开辅助功能设置";
    _permissionItem.state = trusted
        ? NSControlStateValueOn
        : NSControlStateValueOff;

    if (@available(macOS 13.0, *)) {
        _launchAtLoginItem.state =
            SMAppService.mainAppService.status == SMAppServiceStatusEnabled
            ? NSControlStateValueOn
            : NSControlStateValueOff;
    }
}

- (void)toggleEnabled:(id)sender {
    _focusController.paused = NO;
    [_focusController setEnabled:!FVIsEnabled()];
    [self updateMenuState];
}

- (void)intensityDidChange:(NSSlider *)sender {
    [_focusController setDimmingAmount:sender.doubleValue];
}

- (void)openAccessibilitySettings:(id)sender {
    NSURL *settingsURL = [NSURL URLWithString:
        @"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
    if (settingsURL) {
        [NSWorkspace.sharedWorkspace openURL:settingsURL];
    }
}

- (void)toggleLaunchAtLogin:(id)sender API_AVAILABLE(macos(13.0)) {
    NSError *error = nil;
    BOOL succeeded = NO;

    if (SMAppService.mainAppService.status == SMAppServiceStatusEnabled) {
        succeeded = [SMAppService.mainAppService unregisterAndReturnError:&error];
    } else {
        succeeded = [SMAppService.mainAppService registerAndReturnError:&error];
    }

    if (!succeeded) {
        [self showAlertWithTitle:@"无法更改登录启动设置"
                         message:error.localizedDescription ?: @"系统未接受此项设置。"];
    }
    [self updateMenuState];
}

- (void)showAbout:(id)sender {
    BOOL wasPaused = _focusController.isPaused;
    _focusController.paused = YES;

    NSString *version = [NSBundle.mainBundle
        objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0.1.0";
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"FocusVeil";
    alert.informativeText = [NSString stringWithFormat:
        @"保持当前活动窗口原有亮度，并压暗其余窗口和桌面背景。\n\n版本：%@\nGitHub：%@",
        version,
        FVGitHubURLString
    ];
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"好"];
    [alert runModal];

    _focusController.paused = wasPaused;
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    BOOL wasPaused = _focusController.isPaused;
    _focusController.paused = YES;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = message;
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"好"];
    [alert runModal];

    _focusController.paused = wasPaused;
}

- (void)quitApplication:(id)sender {
    [NSApplication.sharedApplication terminate:nil];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        FVRegisterDefaults();

        NSApplication *application = NSApplication.sharedApplication;
        FVAppDelegate *delegate = [[FVAppDelegate alloc] init];
        [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
