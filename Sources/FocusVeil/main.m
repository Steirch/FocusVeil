#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <QuartzCore/QuartzCore.h>
#import <ServiceManagement/ServiceManagement.h>

static NSString * const FVEnabledKey = @"enabled";
static NSString * const FVDimmingAmountKey = @"dimmingAmount";
static NSString * const FVWindowMarginKey = @"windowMargin";
static NSString * const FVTransitionDurationKey = @"transitionDuration";
static NSString * const FVHighlightAllWindowsKey = @"highlightAllWindows";
static NSString * const FVDimAllDisplaysKey = @"dimAllDisplays";
static NSString * const FVOverlayRedKey = @"overlayRed";
static NSString * const FVOverlayGreenKey = @"overlayGreen";
static NSString * const FVOverlayBlueKey = @"overlayBlue";

static void FVRegisterDefaults(void) {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        FVEnabledKey: @YES,
        FVDimmingAmountKey: @0.42,
        FVWindowMarginKey: @8.0,
        FVTransitionDurationKey: @0.16,
        FVHighlightAllWindowsKey: @NO,
        FVDimAllDisplaysKey: @YES,
        FVOverlayRedKey: @0.0,
        FVOverlayGreenKey: @0.0,
        FVOverlayBlueKey: @0.0
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

static CGFloat FVWindowMargin(void) {
    double value = [[NSUserDefaults standardUserDefaults] doubleForKey:FVWindowMarginKey];
    return MIN(MAX(value, 0.0), 24.0);
}

static void FVSetWindowMargin(CGFloat margin) {
    margin = MIN(MAX(margin, 0.0), 24.0);
    [[NSUserDefaults standardUserDefaults] setDouble:margin forKey:FVWindowMarginKey];
}

static NSTimeInterval FVTransitionDuration(void) {
    double value = [[NSUserDefaults standardUserDefaults]
        doubleForKey:FVTransitionDurationKey];
    return MIN(MAX(value, 0.0), 0.60);
}

static void FVSetTransitionDuration(NSTimeInterval duration) {
    duration = MIN(MAX(duration, 0.0), 0.60);
    [[NSUserDefaults standardUserDefaults]
        setDouble:duration
           forKey:FVTransitionDurationKey];
}

static BOOL FVHighlightAllWindows(void) {
    return [[NSUserDefaults standardUserDefaults]
        boolForKey:FVHighlightAllWindowsKey];
}

static void FVSetHighlightAllWindows(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults]
        setBool:enabled
         forKey:FVHighlightAllWindowsKey];
}

static BOOL FVDimAllDisplays(void) {
    return [[NSUserDefaults standardUserDefaults]
        boolForKey:FVDimAllDisplaysKey];
}

static void FVSetDimAllDisplays(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults]
        setBool:enabled
         forKey:FVDimAllDisplaysKey];
}

static NSColor *FVOverlayColor(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    return [NSColor colorWithSRGBRed:[defaults doubleForKey:FVOverlayRedKey]
                              green:[defaults doubleForKey:FVOverlayGreenKey]
                               blue:[defaults doubleForKey:FVOverlayBlueKey]
                              alpha:1.0];
}

static void FVSetOverlayColor(NSColor *color) {
    NSColor *rgbColor = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!rgbColor) {
        return;
    }

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setDouble:rgbColor.redComponent forKey:FVOverlayRedKey];
    [defaults setDouble:rgbColor.greenComponent forKey:FVOverlayGreenKey];
    [defaults setDouble:rgbColor.blueComponent forKey:FVOverlayBlueKey];
}

static CGRect FVAppKitRectFromQuartzRect(CGRect rect) {
    NSScreen *primaryScreen = NSScreen.screens.firstObject;
    CGFloat primaryScreenTop = primaryScreen ? NSMaxY(primaryScreen.frame) : 0;
    return CGRectMake(
        CGRectGetMinX(rect),
        primaryScreenTop - CGRectGetMaxY(rect),
        CGRectGetWidth(rect),
        CGRectGetHeight(rect)
    );
}

static BOOL FVFrameForAXWindow(AXUIElementRef windowElement, CGRect *result) {
    CFTypeRef minimizedReference = NULL;
    if (
        AXUIElementCopyAttributeValue(
            windowElement,
            kAXMinimizedAttribute,
            &minimizedReference
        ) == kAXErrorSuccess &&
        minimizedReference != NULL
    ) {
        BOOL minimized = CFGetTypeID(minimizedReference) == CFBooleanGetTypeID()
            && CFBooleanGetValue((CFBooleanRef)minimizedReference);
        CFRelease(minimizedReference);
        if (minimized) {
            return NO;
        }
    }

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

    BOOL found = FVFrameForAXWindow((AXUIElementRef)windowReference, result);
    CFRelease(windowReference);
    return found;
}

static BOOL FVArrayContainsRect(NSArray<NSValue *> *values, CGRect rect) {
    for (NSValue *value in values) {
        if (CGRectEqualToRect(value.rectValue, rect)) {
            return YES;
        }
    }
    return NO;
}

static NSArray<NSValue *> *FVAllAccessibilityWindowFrames(
    pid_t processIdentifier
) {
    NSMutableArray<NSValue *> *frames = [NSMutableArray array];
    CGRect focusedFrame = CGRectZero;
    if (FVAccessibilityWindowFrame(processIdentifier, &focusedFrame)) {
        [frames addObject:[NSValue valueWithRect:focusedFrame]];
    }

    AXUIElementRef applicationElement = AXUIElementCreateApplication(processIdentifier);
    CFTypeRef windowsReference = NULL;
    AXError error = AXUIElementCopyAttributeValue(
        applicationElement,
        kAXWindowsAttribute,
        &windowsReference
    );
    CFRelease(applicationElement);

    if (error != kAXErrorSuccess || windowsReference == NULL) {
        return frames;
    }

    CFArrayRef windows = (CFArrayRef)windowsReference;
    CFIndex count = CFArrayGetCount(windows);
    for (CFIndex index = 0; index < count; index++) {
        AXUIElementRef window = (AXUIElementRef)CFArrayGetValueAtIndex(windows, index);
        CGRect frame = CGRectZero;
        if (
            FVFrameForAXWindow(window, &frame) &&
            !FVArrayContainsRect(frames, frame)
        ) {
            [frames addObject:[NSValue valueWithRect:frame]];
        }
    }

    CFRelease(windowsReference);
    return frames;
}

static BOOL FVFallbackWindowFrame(pid_t processIdentifier, CGRect *result) {
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
    NSString *boundsKey = (__bridge NSString *)kCGWindowBounds;

    for (NSDictionary *window in windowList) {
        NSNumber *owner = window[ownerKey];
        NSNumber *layer = window[layerKey];
        NSDictionary *bounds = window[boundsKey];
        CGRect frame = CGRectZero;

        if (
            owner.intValue == processIdentifier &&
            layer.integerValue == 0 &&
            bounds != nil &&
            CGRectMakeWithDictionaryRepresentation(
                (__bridge CFDictionaryRef)bounds,
                &frame
            ) &&
            frame.size.width > 40 &&
            frame.size.height > 40
        ) {
            *result = frame;
            return YES;
        }
    }

    return NO;
}

static NSArray<NSValue *> *FVAllFallbackWindowFrames(pid_t processIdentifier) {
    CFArrayRef windowListReference = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
        kCGNullWindowID
    );
    if (windowListReference == NULL) {
        return @[];
    }

    NSArray<NSDictionary *> *windowList = CFBridgingRelease(windowListReference);
    NSMutableArray<NSValue *> *frames = [NSMutableArray array];
    NSString *ownerKey = (__bridge NSString *)kCGWindowOwnerPID;
    NSString *layerKey = (__bridge NSString *)kCGWindowLayer;
    NSString *boundsKey = (__bridge NSString *)kCGWindowBounds;

    for (NSDictionary *window in windowList) {
        NSNumber *owner = window[ownerKey];
        NSNumber *layer = window[layerKey];
        NSDictionary *bounds = window[boundsKey];
        CGRect frame = CGRectZero;
        if (
            owner.intValue == processIdentifier &&
            layer.integerValue == 0 &&
            bounds != nil &&
            CGRectMakeWithDictionaryRepresentation(
                (__bridge CFDictionaryRef)bounds,
                &frame
            ) &&
            frame.size.width > 40 &&
            frame.size.height > 40 &&
            !FVArrayContainsRect(frames, frame)
        ) {
            [frames addObject:[NSValue valueWithRect:frame]];
        }
    }

    return frames;
}

@interface FVDimmingView : NSView
@property(nonatomic) CGFloat dimmingAmount;
@property(nonatomic, strong) NSColor *overlayColor;
- (BOOL)setCutouts:(NSArray<NSValue *> *)cutouts;
@end

@implementation FVDimmingView {
    NSArray<NSValue *> *_cutouts;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _dimmingAmount = 0.42;
        _overlayColor = NSColor.blackColor;
        _cutouts = @[];
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

- (void)setOverlayColor:(NSColor *)overlayColor {
    _overlayColor = overlayColor ?: NSColor.blackColor;
    [self setNeedsDisplay:YES];
}

- (BOOL)setCutouts:(NSArray<NSValue *> *)cutouts {
    NSArray<NSValue *> *normalizedCutouts = cutouts ?: @[];
    if ([_cutouts isEqualToArray:normalizedCutouts]) {
        return NO;
    }

    _cutouts = [normalizedCutouts copy];
    [self setNeedsDisplay:YES];
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    [[self.overlayColor colorWithAlphaComponent:self.dimmingAmount] setFill];
    NSRectFillUsingOperation(self.bounds, NSCompositingOperationSourceOver);

    if (_cutouts.count > 0) {
        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext.currentContext.compositingOperation = NSCompositingOperationClear;
        for (NSValue *value in _cutouts) {
            NSBezierPath *path = [
                NSBezierPath bezierPathWithRoundedRect:value.rectValue
                                              xRadius:12
                                              yRadius:12
            ];
            [path fill];
        }
        [NSGraphicsContext restoreGraphicsState];
    }
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
        self.level = NSFloatingWindowLevel;
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
@property(nonatomic, readonly) CGRect screenFrame;
- (instancetype)initWithScreen:(NSScreen *)screen
                dimmingAmount:(CGFloat)amount
                  overlayColor:(NSColor *)color;
- (void)showWithGlobalCutouts:(NSArray<NSValue *> *)cutouts
                       margin:(CGFloat)margin
           transitionDuration:(NSTimeInterval)duration;
- (void)hide;
- (void)updateDimmingAmount:(CGFloat)amount;
- (void)updateOverlayColor:(NSColor *)color;
@end

@implementation FVOverlay {
    FVOverlayPanel *_panel;
    FVDimmingView *_dimmingView;
}

- (instancetype)initWithScreen:(NSScreen *)screen
                dimmingAmount:(CGFloat)amount
                  overlayColor:(NSColor *)color {
    self = [super init];
    if (self) {
        _panel = [[FVOverlayPanel alloc] initWithScreen:screen];
        _dimmingView = [[FVDimmingView alloc] initWithFrame:(CGRect){
            .origin = CGPointZero,
            .size = screen.frame.size
        }];
        _dimmingView.dimmingAmount = amount;
        _dimmingView.overlayColor = color;
        _panel.contentView = _dimmingView;
    }
    return self;
}

- (CGRect)screenFrame {
    return _panel.frame;
}

- (void)showWithGlobalCutouts:(NSArray<NSValue *> *)cutouts
                       margin:(CGFloat)margin
           transitionDuration:(NSTimeInterval)duration {
    NSMutableArray<NSValue *> *localCutouts = [NSMutableArray array];

    for (NSValue *value in cutouts) {
        CGRect expanded = CGRectInset(value.rectValue, -margin, -margin);
        CGRect localCutout = CGRectOffset(
            expanded,
            -CGRectGetMinX(_panel.frame),
            -CGRectGetMinY(_panel.frame)
        );
        localCutout = CGRectIntersection(localCutout, _dimmingView.bounds);
        if (!CGRectIsNull(localCutout) && !CGRectIsEmpty(localCutout)) {
            [localCutouts addObject:[NSValue valueWithRect:localCutout]];
        }
    }

    BOOL changed = [_dimmingView setCutouts:localCutouts];

    if (!_panel.visible) {
        _panel.alphaValue = 0;
        [_panel orderFrontRegardless];
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = duration;
            _panel.animator.alphaValue = 1;
        }];
    } else if (changed && duration > 0) {
        _panel.alphaValue = 0.68;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = duration;
            context.timingFunction = [CAMediaTimingFunction
                functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            _panel.animator.alphaValue = 1;
        }];
    }
}

- (void)hide {
    if (!_panel.visible) {
        return;
    }

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = FVTransitionDuration();
        _panel.animator.alphaValue = 0;
    } completionHandler:^{
        [self->_panel orderOut:nil];
        self->_panel.alphaValue = 1;
    }];
}

- (void)updateDimmingAmount:(CGFloat)amount {
    _dimmingView.dimmingAmount = amount;
}

- (void)updateOverlayColor:(NSColor *)color {
    _dimmingView.overlayColor = color;
}

@end

@interface FVFocusController : NSObject
@property(nonatomic, readonly) BOOL accessibilityTrusted;
@property(nonatomic, getter=isPaused) BOOL paused;
- (void)start;
- (void)stop;
- (void)setEnabled:(BOOL)enabled;
- (void)setDimmingAmount:(CGFloat)amount;
- (void)setOverlayColor:(NSColor *)color;
- (void)refreshNow;
- (BOOL)requestAccessibilityPermission;
@end

@implementation FVFocusController {
    NSMutableArray<FVOverlay *> *_overlays;
    NSTimer *_refreshTimer;
    NSArray<NSValue *> *_lastWindowFrames;
    pid_t _ownProcessIdentifier;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _overlays = [NSMutableArray array];
        _ownProcessIdentifier = NSProcessInfo.processInfo.processIdentifier;
        _lastWindowFrames = @[];
        _paused = NO;
    }
    return self;
}

- (BOOL)accessibilityTrusted {
    return AXIsProcessTrusted();
}

- (BOOL)requestAccessibilityPermission {
    NSDictionary *options = @{
        (__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES
    };
    return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
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

- (void)setOverlayColor:(NSColor *)color {
    FVSetOverlayColor(color);
    for (FVOverlay *overlay in _overlays) {
        [overlay updateOverlayColor:FVOverlayColor()];
    }
}

- (void)refreshNow {
    [self refresh:nil];
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
        NSArray<NSValue *> *quartzFrames = nil;

        if (FVHighlightAllWindows()) {
            quartzFrames = FVAllAccessibilityWindowFrames(
                frontmostApplication.processIdentifier
            );
            if (quartzFrames.count == 0) {
                quartzFrames = FVAllFallbackWindowFrames(
                    frontmostApplication.processIdentifier
                );
            }
        } else {
            CGRect quartzFrame = CGRectZero;
            BOOL found = FVAccessibilityWindowFrame(
                frontmostApplication.processIdentifier,
                &quartzFrame
            );
            if (!found) {
                found = FVFallbackWindowFrame(
                    frontmostApplication.processIdentifier,
                    &quartzFrame
                );
            }
            quartzFrames = found
                ? @[[NSValue valueWithRect:quartzFrame]]
                : @[];
        }

        NSMutableArray<NSValue *> *appKitFrames = [NSMutableArray array];
        for (NSValue *value in quartzFrames) {
            [appKitFrames addObject:[NSValue valueWithRect:
                FVAppKitRectFromQuartzRect(value.rectValue)
            ]];
        }
        _lastWindowFrames = appKitFrames;
    }

    if (_lastWindowFrames.count == 0) {
        for (FVOverlay *overlay in _overlays) {
            [overlay hide];
        }
        return;
    }

    CGRect focusedWindowFrame = _lastWindowFrames.firstObject.rectValue;
    for (FVOverlay *overlay in _overlays) {
        BOOL focusedWindowIntersects = CGRectIntersectsRect(
            focusedWindowFrame,
            overlay.screenFrame
        );
        if (!FVDimAllDisplays() && !focusedWindowIntersects) {
            [overlay hide];
            continue;
        }

        NSMutableArray<NSValue *> *cutouts = [NSMutableArray array];
        for (NSValue *value in _lastWindowFrames) {
            if (CGRectIntersectsRect(value.rectValue, overlay.screenFrame)) {
                [cutouts addObject:value];
            }
        }

        [overlay showWithGlobalCutouts:cutouts
                               margin:FVWindowMargin()
                   transitionDuration:FVTransitionDuration()];
    }
}

- (void)rebuildOverlays {
    for (FVOverlay *overlay in _overlays) {
        [overlay hide];
    }
    [_overlays removeAllObjects];

    for (NSScreen *screen in NSScreen.screens) {
        FVOverlay *overlay = [[FVOverlay alloc] initWithScreen:screen
                                              dimmingAmount:FVDimmingAmount()
                                                overlayColor:FVOverlayColor()];
        [_overlays addObject:overlay];
    }
}

@end

static NSTextField *FVLabel(
    NSString *text,
    NSRect frame,
    CGFloat fontSize,
    NSFontWeight weight
) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.frame = frame;
    label.font = [NSFont systemFontOfSize:fontSize weight:weight];
    return label;
}

static NSTextField *FVSecondaryLabel(NSString *text, NSRect frame) {
    NSTextField *label = FVLabel(text, frame, 12, NSFontWeightRegular);
    label.textColor = NSColor.secondaryLabelColor;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.maximumNumberOfLines = 0;
    return label;
}

static NSBox *FVSeparator(CGFloat y, CGFloat width) {
    NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(24, y, width, 1)];
    separator.boxType = NSBoxSeparator;
    return separator;
}

static NSSegmentedControl *FVSegmentedControl(
    NSArray<NSString *> *labels,
    NSRect frame,
    id target,
    SEL action
) {
    NSSegmentedControl *control = [[NSSegmentedControl alloc] initWithFrame:frame];
    control.segmentCount = labels.count;
    control.trackingMode = NSSegmentSwitchTrackingSelectOne;
    control.target = target;
    control.action = action;
    [labels enumerateObjectsUsingBlock:^(
        NSString *label,
        NSUInteger index,
        BOOL *stop
    ) {
        (void)stop;
        [control setLabel:label forSegment:index];
    }];
    return control;
}

@interface FVAppDelegate :
    NSObject <NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate>
@end

@implementation FVAppDelegate {
    FVFocusController *_focusController;
    NSStatusItem *_statusItem;
    NSMenuItem *_enabledItem;
    NSMenuItem *_permissionItem;
    NSMenuItem *_launchAtLoginItem;
    NSSlider *_menuIntensitySlider;
    NSTimer *_pauseTimer;
    BOOL _userPaused;
    BOOL _settingsVisible;

    NSWindow *_settingsWindow;
    NSButton *_settingsEnabledCheckbox;
    NSButton *_settingsLaunchCheckbox;
    NSTextField *_settingsStateLabel;
    NSTextField *_settingsPermissionLabel;
    NSButton *_resumeButton;

    NSSlider *_settingsDimmingSlider;
    NSTextField *_settingsDimmingValue;
    NSColorWell *_settingsColorWell;
    NSSlider *_settingsTransitionSlider;
    NSTextField *_settingsTransitionValue;
    NSSlider *_settingsMarginSlider;
    NSTextField *_settingsMarginValue;
    NSSegmentedControl *_settingsHighlightMode;
    NSSegmentedControl *_settingsDisplayMode;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _focusController = [[FVFocusController alloc] init];
        _userPaused = NO;
        _settingsVisible = NO;
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self configureStatusItem];
    [_focusController start];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self showSettings:nil];
    });
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [_pauseTimer invalidate];
    [_focusController stop];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender
                    hasVisibleWindows:(BOOL)flag {
    [self showSettings:nil];
    return YES;
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

    NSMenuItem *settingsItem = [[NSMenuItem alloc]
        initWithTitle:@"打开设置…"
               action:@selector(showSettings:)
        keyEquivalent:@","];
    settingsItem.target = self;
    [menu addItem:settingsItem];
    [menu addItem:NSMenuItem.separatorItem];

    _enabledItem = [[NSMenuItem alloc] initWithTitle:@"启用聚焦遮罩"
                                             action:@selector(toggleEnabled:)
                                      keyEquivalent:@""];
    _enabledItem.target = self;
    [menu addItem:_enabledItem];

    [menu addItem:[self intensityMenuItem]];
    [menu addItem:NSMenuItem.separatorItem];

    NSMenuItem *pauseItem = [[NSMenuItem alloc] initWithTitle:@"暂停五分钟"
                                                       action:@selector(pauseForFiveMinutes:)
                                                keyEquivalent:@""];
    pauseItem.target = self;
    [menu addItem:pauseItem];

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

    _menuIntensitySlider = [[NSSlider alloc]
        initWithFrame:NSMakeRect(14, 5, 220, 24)];
    _menuIntensitySlider.minValue = 0.08;
    _menuIntensitySlider.maxValue = 0.82;
    _menuIntensitySlider.doubleValue = FVDimmingAmount();
    _menuIntensitySlider.continuous = YES;
    _menuIntensitySlider.target = self;
    _menuIntensitySlider.action = @selector(intensityDidChange:);

    [container addSubview:label];
    [container addSubview:_menuIntensitySlider];
    menuItem.view = container;
    return menuItem;
}

- (void)createSettingsWindowIfNeeded {
    if (_settingsWindow) {
        return;
    }

    NSRect contentRect = NSMakeRect(0, 0, 660, 520);
    _settingsWindow = [[NSWindow alloc]
        initWithContentRect:contentRect
                  styleMask:NSWindowStyleMaskTitled
                    | NSWindowStyleMaskClosable
                    | NSWindowStyleMaskMiniaturizable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    _settingsWindow.title = @"FocusVeil 设置";
    _settingsWindow.delegate = self;
    _settingsWindow.releasedWhenClosed = NO;
    _settingsWindow.tabbingMode = NSWindowTabbingModeDisallowed;
    [_settingsWindow center];

    NSTabView *tabView = [[NSTabView alloc]
        initWithFrame:NSMakeRect(18, 14, 624, 488)];
    tabView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    NSTabViewItem *generalItem = [[NSTabViewItem alloc]
        initWithIdentifier:@"general"];
    generalItem.label = @"通用";
    generalItem.view = [self generalSettingsView];
    [tabView addTabViewItem:generalItem];

    NSTabViewItem *appearanceItem = [[NSTabViewItem alloc]
        initWithIdentifier:@"appearance"];
    appearanceItem.label = @"外观";
    appearanceItem.view = [self appearanceSettingsView];
    [tabView addTabViewItem:appearanceItem];

    NSTabViewItem *displayItem = [[NSTabViewItem alloc]
        initWithIdentifier:@"displays"];
    displayItem.label = @"显示器";
    displayItem.view = [self displaySettingsView];
    [tabView addTabViewItem:displayItem];

    NSTabViewItem *advancedItem = [[NSTabViewItem alloc]
        initWithIdentifier:@"advanced"];
    advancedItem.label = @"高级";
    advancedItem.view = [self advancedSettingsView];
    [tabView addTabViewItem:advancedItem];

    _settingsWindow.contentView = tabView;
}

- (NSView *)generalSettingsView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 604, 440)];

    [view addSubview:FVLabel(
        @"聚焦控制",
        NSMakeRect(24, 386, 400, 30),
        22,
        NSFontWeightSemibold
    )];
    [view addSubview:FVSecondaryLabel(
        @"FocusVeil 会自动跟随当前窗口，并让其他内容降低视觉干扰。",
        NSMakeRect(24, 360, 540, 20)
    )];

    _settingsEnabledCheckbox = [NSButton
        checkboxWithTitle:@"启用聚焦遮罩"
                 target:self
                 action:@selector(settingsEnabledDidChange:)];
    _settingsEnabledCheckbox.frame = NSMakeRect(24, 316, 260, 24);
    _settingsEnabledCheckbox.font = [NSFont systemFontOfSize:14
                                                     weight:NSFontWeightMedium];
    [view addSubview:_settingsEnabledCheckbox];

    _settingsStateLabel = FVSecondaryLabel(
        @"",
        NSMakeRect(44, 292, 510, 18)
    );
    [view addSubview:_settingsStateLabel];
    [view addSubview:FVSeparator(274, 556)];

    [view addSubview:FVLabel(
        @"辅助功能权限",
        NSMakeRect(24, 240, 220, 22),
        14,
        NSFontWeightMedium
    )];
    _settingsPermissionLabel = FVSecondaryLabel(
        @"",
        NSMakeRect(24, 202, 380, 30)
    );
    [view addSubview:_settingsPermissionLabel];

    NSButton *permissionButton = [NSButton
        buttonWithTitle:@"打开系统设置"
                 target:self
                 action:@selector(openAccessibilitySettings:)];
    permissionButton.frame = NSMakeRect(430, 204, 126, 30);
    permissionButton.bezelStyle = NSBezelStyleRounded;
    [view addSubview:permissionButton];

    _settingsLaunchCheckbox = [NSButton
        checkboxWithTitle:@"登录 macOS 时自动启动"
                 target:self
                 action:@selector(settingsLaunchAtLoginDidChange:)];
    _settingsLaunchCheckbox.frame = NSMakeRect(24, 166, 300, 24);
    [view addSubview:_settingsLaunchCheckbox];
    [view addSubview:FVSecondaryLabel(
        @"请先将应用移入“应用程序”文件夹，再启用此选项。",
        NSMakeRect(44, 144, 500, 18)
    )];
    [view addSubview:FVSeparator(126, 556)];

    [view addSubview:FVLabel(
        @"临时暂停",
        NSMakeRect(24, 91, 160, 22),
        14,
        NSFontWeightMedium
    )];
    NSArray<NSNumber *> *durations = @[@300, @900, @3600];
    NSArray<NSString *> *titles = @[@"五分钟", @"十五分钟", @"一小时"];
    for (NSUInteger index = 0; index < titles.count; index++) {
        NSButton *button = [NSButton
            buttonWithTitle:titles[index]
                     target:self
                     action:@selector(pauseForTaggedDuration:)];
        button.frame = NSMakeRect(24 + index * 94, 48, 86, 30);
        button.bezelStyle = NSBezelStyleRounded;
        button.tag = durations[index].integerValue;
        [view addSubview:button];
    }

    _resumeButton = [NSButton
        buttonWithTitle:@"立即恢复"
                 target:self
                 action:@selector(resumeNow:)];
    _resumeButton.frame = NSMakeRect(446, 48, 110, 30);
    _resumeButton.bezelStyle = NSBezelStyleRounded;
    [view addSubview:_resumeButton];

    return view;
}

- (NSView *)appearanceSettingsView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 604, 440)];

    [view addSubview:FVLabel(
        @"遮罩外观",
        NSMakeRect(24, 386, 400, 30),
        22,
        NSFontWeightSemibold
    )];
    [view addSubview:FVSecondaryLabel(
        @"调整背景的压暗程度、颜色和窗口切换时的过渡速度。",
        NSMakeRect(24, 360, 540, 20)
    )];

    [view addSubview:FVLabel(
        @"背景压暗强度",
        NSMakeRect(24, 318, 180, 20),
        13,
        NSFontWeightMedium
    )];
    _settingsDimmingSlider = [[NSSlider alloc]
        initWithFrame:NSMakeRect(24, 282, 470, 24)];
    _settingsDimmingSlider.minValue = 0.08;
    _settingsDimmingSlider.maxValue = 0.82;
    _settingsDimmingSlider.continuous = YES;
    _settingsDimmingSlider.target = self;
    _settingsDimmingSlider.action = @selector(intensityDidChange:);
    [view addSubview:_settingsDimmingSlider];
    _settingsDimmingValue = FVLabel(
        @"",
        NSMakeRect(510, 284, 60, 20),
        12,
        NSFontWeightMedium
    );
    _settingsDimmingValue.alignment = NSTextAlignmentRight;
    [view addSubview:_settingsDimmingValue];

    [view addSubview:FVLabel(
        @"遮罩颜色",
        NSMakeRect(24, 238, 180, 20),
        13,
        NSFontWeightMedium
    )];
    [view addSubview:FVSecondaryLabel(
        @"深色最适合降低干扰，也可以选择低饱和度的自定义颜色。",
        NSMakeRect(24, 212, 430, 20)
    )];
    _settingsColorWell = [[NSColorWell alloc]
        initWithFrame:NSMakeRect(504, 208, 60, 32)];
    _settingsColorWell.target = self;
    _settingsColorWell.action = @selector(overlayColorDidChange:);
    [view addSubview:_settingsColorWell];
    [view addSubview:FVSeparator(190, 556)];

    [view addSubview:FVLabel(
        @"过渡时间",
        NSMakeRect(24, 154, 180, 20),
        13,
        NSFontWeightMedium
    )];
    _settingsTransitionSlider = [[NSSlider alloc]
        initWithFrame:NSMakeRect(24, 118, 470, 24)];
    _settingsTransitionSlider.minValue = 0;
    _settingsTransitionSlider.maxValue = 0.60;
    _settingsTransitionSlider.continuous = YES;
    _settingsTransitionSlider.target = self;
    _settingsTransitionSlider.action = @selector(transitionDidChange:);
    [view addSubview:_settingsTransitionSlider];
    _settingsTransitionValue = FVLabel(
        @"",
        NSMakeRect(510, 120, 60, 20),
        12,
        NSFontWeightMedium
    );
    _settingsTransitionValue.alignment = NSTextAlignmentRight;
    [view addSubview:_settingsTransitionValue];

    [view addSubview:FVLabel(
        @"突出范围",
        NSMakeRect(24, 70, 180, 20),
        13,
        NSFontWeightMedium
    )];
    _settingsHighlightMode = FVSegmentedControl(
        @[@"当前窗口", @"当前应用的所有窗口"],
        NSMakeRect(270, 60, 294, 30),
        self,
        @selector(highlightModeDidChange:)
    );
    [view addSubview:_settingsHighlightMode];

    return view;
}

- (NSView *)displaySettingsView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 604, 440)];

    [view addSubview:FVLabel(
        @"多显示器行为",
        NSMakeRect(24, 386, 400, 30),
        22,
        NSFontWeightSemibold
    )];
    [view addSubview:FVSecondaryLabel(
        @"选择活动窗口位于某一显示器时，其他显示器如何响应。",
        NSMakeRect(24, 360, 540, 20)
    )];

    _settingsDisplayMode = FVSegmentedControl(
        @[@"压暗所有显示器", @"仅压暗活动显示器"],
        NSMakeRect(24, 300, 430, 32),
        self,
        @selector(displayModeDidChange:)
    );
    [view addSubview:_settingsDisplayMode];

    NSBox *explanationBox = [[NSBox alloc]
        initWithFrame:NSMakeRect(24, 142, 556, 126)];
    explanationBox.titlePosition = NSNoTitle;
    [view addSubview:explanationBox];

    [explanationBox.contentView addSubview:FVLabel(
        @"压暗所有显示器",
        NSMakeRect(18, 82, 220, 20),
        13,
        NSFontWeightMedium
    )];
    [explanationBox.contentView addSubview:FVSecondaryLabel(
        @"活动窗口之外的全部屏幕区域都会变暗，适合需要高度专注的工作。",
        NSMakeRect(18, 51, 510, 36)
    )];
    [explanationBox.contentView addSubview:FVLabel(
        @"仅压暗活动显示器",
        NSMakeRect(18, 22, 220, 20),
        13,
        NSFontWeightMedium
    )];
    [explanationBox.contentView addSubview:FVSecondaryLabel(
        @"其他显示器保持原状，便于持续查看参考资料或监控信息。",
        NSMakeRect(18, 1, 510, 22)
    )];

    [view addSubview:FVSecondaryLabel(
        @"连接或断开显示器后，FocusVeil 会自动重建遮罩。",
        NSMakeRect(24, 104, 540, 20)
    )];

    return view;
}

- (NSView *)advancedSettingsView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 604, 440)];

    [view addSubview:FVLabel(
        @"高级设置",
        NSMakeRect(24, 386, 400, 30),
        22,
        NSFontWeightSemibold
    )];
    [view addSubview:FVSecondaryLabel(
        @"控制活动窗口周围保留的范围，并管理本地设置。",
        NSMakeRect(24, 360, 540, 20)
    )];

    [view addSubview:FVLabel(
        @"窗口周围留白",
        NSMakeRect(24, 314, 180, 20),
        13,
        NSFontWeightMedium
    )];
    _settingsMarginSlider = [[NSSlider alloc]
        initWithFrame:NSMakeRect(24, 278, 470, 24)];
    _settingsMarginSlider.minValue = 0;
    _settingsMarginSlider.maxValue = 24;
    _settingsMarginSlider.continuous = YES;
    _settingsMarginSlider.target = self;
    _settingsMarginSlider.action = @selector(windowMarginDidChange:);
    [view addSubview:_settingsMarginSlider];
    _settingsMarginValue = FVLabel(
        @"",
        NSMakeRect(510, 280, 60, 20),
        12,
        NSFontWeightMedium
    );
    _settingsMarginValue.alignment = NSTextAlignmentRight;
    [view addSubview:_settingsMarginValue];
    [view addSubview:FVSecondaryLabel(
        @"适当增加留白可以保留窗口阴影，使活动窗口边界更加清晰。",
        NSMakeRect(24, 250, 540, 20)
    )];
    [view addSubview:FVSeparator(224, 556)];

    [view addSubview:FVLabel(
        @"隐私说明",
        NSMakeRect(24, 187, 180, 20),
        13,
        NSFontWeightMedium
    )];
    [view addSubview:FVSecondaryLabel(
        @"应用只通过系统辅助功能接口读取窗口的位置与尺寸，不读取窗口文字，不截取屏幕，也不发送任何数据。",
        NSMakeRect(24, 136, 540, 48)
    )];
    [view addSubview:FVSeparator(116, 556)];

    NSButton *resetButton = [NSButton
        buttonWithTitle:@"恢复默认设置"
                 target:self
                 action:@selector(resetSettings:)];
    resetButton.frame = NSMakeRect(24, 66, 132, 30);
    resetButton.bezelStyle = NSBezelStyleRounded;
    [view addSubview:resetButton];

    NSTextField *versionLabel = FVSecondaryLabel(
        @"FocusVeil 版本 0.2.0",
        NSMakeRect(400, 72, 164, 18)
    );
    versionLabel.alignment = NSTextAlignmentRight;
    [view addSubview:versionLabel];

    return view;
}

- (void)showSettings:(id)sender {
    [self createSettingsWindowIfNeeded];
    _settingsVisible = YES;
    [self updateControllerPauseState];
    [self updateSettingsControls];

    [NSApplication.sharedApplication activateIgnoringOtherApps:YES];
    [_settingsWindow makeKeyAndOrderFront:nil];
}

- (void)windowWillClose:(NSNotification *)notification {
    if (notification.object == _settingsWindow) {
        _settingsVisible = NO;
        [self updateControllerPauseState];
    }
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
    if (notification.object == _settingsWindow) {
        [self updateSettingsControls];
    }
}

- (void)menuWillOpen:(NSMenu *)menu {
    [self updateMenuState];
}

- (void)updateMenuState {
    BOOL active = FVIsEnabled() && !_userPaused;
    _enabledItem.state = active ? NSControlStateValueOn : NSControlStateValueOff;
    _menuIntensitySlider.doubleValue = FVDimmingAmount();

    BOOL trusted = _focusController.accessibilityTrusted;
    _permissionItem.title = trusted
        ? @"辅助功能权限已启用"
        : @"需要启用辅助功能权限";
    _permissionItem.state = trusted
        ? NSControlStateValueOn
        : NSControlStateValueOff;

    if (@available(macOS 13.0, *)) {
        _launchAtLoginItem.state =
            SMAppService.mainAppService.status == SMAppServiceStatusEnabled
            ? NSControlStateValueOn
            : NSControlStateValueOff;
    }

    [self updateSettingsControls];
}

- (void)updateSettingsControls {
    if (!_settingsWindow) {
        return;
    }

    BOOL enabled = FVIsEnabled();
    BOOL trusted = _focusController.accessibilityTrusted;
    _settingsEnabledCheckbox.state = enabled
        ? NSControlStateValueOn
        : NSControlStateValueOff;

    if (!enabled) {
        _settingsStateLabel.stringValue = @"聚焦遮罩已关闭。";
    } else if (_userPaused) {
        _settingsStateLabel.stringValue = @"聚焦遮罩当前处于临时暂停状态。";
    } else {
        _settingsStateLabel.stringValue =
            @"聚焦遮罩已启用；关闭设置窗口后继续显示。";
    }

    _settingsPermissionLabel.stringValue = trusted
        ? @"权限已启用，可以准确跟随同一应用中的窗口切换。"
        : @"尚未启用。没有此权限时，窗口识别可能不完整。";
    _settingsPermissionLabel.textColor = trusted
        ? NSColor.systemGreenColor
        : NSColor.systemOrangeColor;

    if (@available(macOS 13.0, *)) {
        _settingsLaunchCheckbox.state =
            SMAppService.mainAppService.status == SMAppServiceStatusEnabled
            ? NSControlStateValueOn
            : NSControlStateValueOff;
    }

    _resumeButton.enabled = _userPaused;
    _settingsDimmingSlider.doubleValue = FVDimmingAmount();
    _settingsDimmingValue.stringValue = [NSString
        stringWithFormat:@"%.0f%%",
        FVDimmingAmount() * 100
    ];
    _settingsColorWell.color = FVOverlayColor();
    _settingsTransitionSlider.doubleValue = FVTransitionDuration();
    _settingsTransitionValue.stringValue = [NSString
        stringWithFormat:@"%.0f 毫秒",
        FVTransitionDuration() * 1000
    ];
    _settingsMarginSlider.doubleValue = FVWindowMargin();
    _settingsMarginValue.stringValue = [NSString
        stringWithFormat:@"%.0f 像素",
        FVWindowMargin()
    ];
    _settingsHighlightMode.selectedSegment = FVHighlightAllWindows() ? 1 : 0;
    _settingsDisplayMode.selectedSegment = FVDimAllDisplays() ? 0 : 1;
}

- (void)updateControllerPauseState {
    _focusController.paused = _userPaused || _settingsVisible;
}

- (void)toggleEnabled:(id)sender {
    [_pauseTimer invalidate];
    _pauseTimer = nil;
    _userPaused = NO;
    [_focusController setEnabled:!FVIsEnabled()];
    [self updateControllerPauseState];
    [self updateMenuState];
}

- (void)settingsEnabledDidChange:(NSButton *)sender {
    [_pauseTimer invalidate];
    _pauseTimer = nil;
    _userPaused = NO;
    [_focusController setEnabled:sender.state == NSControlStateValueOn];
    [self updateControllerPauseState];
    [self updateMenuState];
}

- (void)intensityDidChange:(NSSlider *)sender {
    [_focusController setDimmingAmount:sender.doubleValue];
    [self updateMenuState];
}

- (void)overlayColorDidChange:(NSColorWell *)sender {
    [_focusController setOverlayColor:sender.color];
    [self updateSettingsControls];
}

- (void)transitionDidChange:(NSSlider *)sender {
    FVSetTransitionDuration(sender.doubleValue);
    [self updateSettingsControls];
}

- (void)windowMarginDidChange:(NSSlider *)sender {
    FVSetWindowMargin(sender.doubleValue);
    [_focusController refreshNow];
    [self updateSettingsControls];
}

- (void)highlightModeDidChange:(NSSegmentedControl *)sender {
    FVSetHighlightAllWindows(sender.selectedSegment == 1);
    [_focusController refreshNow];
    [self updateSettingsControls];
}

- (void)displayModeDidChange:(NSSegmentedControl *)sender {
    FVSetDimAllDisplays(sender.selectedSegment == 0);
    [_focusController refreshNow];
    [self updateSettingsControls];
}

- (void)pauseForFiveMinutes:(id)sender {
    [self pauseForDuration:300];
}

- (void)pauseForTaggedDuration:(NSButton *)sender {
    [self pauseForDuration:sender.tag];
}

- (void)pauseForDuration:(NSTimeInterval)duration {
    [_pauseTimer invalidate];
    _userPaused = YES;
    [self updateControllerPauseState];
    [self updateMenuState];

    __weak typeof(self) weakSelf = self;
    _pauseTimer = [NSTimer scheduledTimerWithTimeInterval:duration
                                                 repeats:NO
                                                   block:^(NSTimer *timer) {
        (void)timer;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf->_userPaused = NO;
        [strongSelf updateControllerPauseState];
        [strongSelf updateMenuState];
    }];
}

- (void)resumeNow:(id)sender {
    [_pauseTimer invalidate];
    _pauseTimer = nil;
    _userPaused = NO;
    [self updateControllerPauseState];
    [self updateMenuState];
}

- (void)openAccessibilitySettings:(id)sender {
    if (!_focusController.accessibilityTrusted) {
        [_focusController requestAccessibilityPermission];
    }

    NSURL *settingsURL = [NSURL URLWithString:
        @"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
    if (settingsURL) {
        [NSWorkspace.sharedWorkspace openURL:settingsURL];
    }
}

- (void)settingsLaunchAtLoginDidChange:(NSButton *)sender {
    BOOL requestedEnabled = sender.state == NSControlStateValueOn;
    BOOL currentlyEnabled =
        SMAppService.mainAppService.status == SMAppServiceStatusEnabled;
    if (requestedEnabled != currentlyEnabled) {
        [self toggleLaunchAtLogin:sender];
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
    BOOL settingsWasVisible = _settingsVisible;
    _settingsVisible = YES;
    [self updateControllerPauseState];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"FocusVeil";
    alert.informativeText =
        @"自动突出当前窗口，并将其他窗口压暗。\n\n版本 0.2.0";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"好"];
    [alert runModal];

    _settingsVisible = settingsWasVisible;
    [self updateControllerPauseState];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    BOOL settingsWasVisible = _settingsVisible;
    _settingsVisible = YES;
    [self updateControllerPauseState];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = message;
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"好"];
    [alert runModal];

    _settingsVisible = settingsWasVisible;
    [self updateControllerPauseState];
}

- (void)resetSettings:(id)sender {
    NSArray<NSString *> *keys = @[
        FVEnabledKey,
        FVDimmingAmountKey,
        FVWindowMarginKey,
        FVTransitionDurationKey,
        FVHighlightAllWindowsKey,
        FVDimAllDisplaysKey,
        FVOverlayRedKey,
        FVOverlayGreenKey,
        FVOverlayBlueKey
    ];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    for (NSString *key in keys) {
        [defaults removeObjectForKey:key];
    }

    [_pauseTimer invalidate];
    _pauseTimer = nil;
    _userPaused = NO;
    [_focusController setEnabled:FVIsEnabled()];
    [_focusController setDimmingAmount:FVDimmingAmount()];
    [_focusController setOverlayColor:FVOverlayColor()];
    [self updateControllerPauseState];
    [_focusController refreshNow];
    [self updateMenuState];
}

- (void)quitApplication:(id)sender {
    [NSApplication.sharedApplication terminate:nil];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        (void)argc;
        (void)argv;
        FVRegisterDefaults();

        NSApplication *application = NSApplication.sharedApplication;
        FVAppDelegate *delegate = [[FVAppDelegate alloc] init];
        [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
