#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <ServiceManagement/ServiceManagement.h>
#import <math.h>

static NSString * const FVEnabledKey = @"enabled";
static NSString * const FVDimmingAmountKey = @"dimmingAmount";
static NSString * const FVRankedBrightnessEnabledKey = @"rankedBrightnessEnabled";
static NSString * const FVHighlightWindowCountKey = @"highlightWindowCount";
static NSString * const FVRankedBrightnessCustomizedKey = @"rankedBrightnessCustomized";
static NSString * const FVGitHubURLString = @"https://github.com/Steirch/FocusVeil";
static const CGFloat FVDefaultDimmingAmount = 0.52;
static const NSInteger FVMinimumHighlightWindowCount = 1;
static const NSInteger FVMaximumHighlightWindowCount = 4;
static const CGFloat FVMinimumRankedBrightness = 0.0;
static const CGFloat FVMaximumRankedBrightness = 0.95;
static const CGFloat FVSingleRankedBrightnessDefault = 0.55;
static const CGFloat FVTopRankedBrightnessDefault = 0.62;
static const CGFloat FVBottomRankedBrightnessDefault = 0.06;
static const CGFloat FVRankedBrightnessDefaultCurve = 1.35;
static const CGFloat FVRankedBrightnessResponseCurve = 1.45;
static const CGFloat FVMinimumVisibleWindowAreaRatio = 0.08;

static void FVRegisterDefaults(void) {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        FVEnabledKey: @YES,
        FVDimmingAmountKey: @(FVDefaultDimmingAmount),
        FVRankedBrightnessEnabledKey: @NO,
        FVHighlightWindowCountKey: @2,
        FVRankedBrightnessCustomizedKey: @NO
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

static BOOL FVRankedBrightnessEnabled(void) {
    return [[NSUserDefaults standardUserDefaults]
        boolForKey:FVRankedBrightnessEnabledKey];
}

static void FVSetRankedBrightnessEnabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled
                                            forKey:FVRankedBrightnessEnabledKey];
}

static NSInteger FVHighlightWindowCount(void) {
    NSInteger count = [[NSUserDefaults standardUserDefaults]
        integerForKey:FVHighlightWindowCountKey];
    return MIN(MAX(count, FVMinimumHighlightWindowCount), FVMaximumHighlightWindowCount);
}

static void FVSetHighlightWindowCount(NSInteger count) {
    count = MIN(MAX(count, FVMinimumHighlightWindowCount), FVMaximumHighlightWindowCount);
    [[NSUserDefaults standardUserDefaults] setInteger:count
                                               forKey:FVHighlightWindowCountKey];
}

static NSString *FVRankedBrightnessKeyForLevel(NSInteger level) {
    return [NSString stringWithFormat:@"rankedBrightnessLevel%ld", (long)level];
}

static CGFloat FVClampRankedBrightness(CGFloat brightness) {
    return MIN(MAX(brightness, FVMinimumRankedBrightness), FVMaximumRankedBrightness);
}

static CGFloat FVDefaultRankedBrightnessForLevel(
    NSInteger level,
    NSInteger configuredCount
) {
    level = MIN(MAX(level, FVMinimumHighlightWindowCount), FVMaximumHighlightWindowCount);
    configuredCount = MIN(
        MAX(configuredCount, level),
        FVMaximumHighlightWindowCount
    );
    if (configuredCount <= FVMinimumHighlightWindowCount) {
        return FVSingleRankedBrightnessDefault;
    }

    CGFloat position = (CGFloat)(configuredCount - level)
        / (CGFloat)(configuredCount - FVMinimumHighlightWindowCount);
    CGFloat brightness = FVBottomRankedBrightnessDefault
        + (FVTopRankedBrightnessDefault - FVBottomRankedBrightnessDefault)
            * pow(position, FVRankedBrightnessDefaultCurve);
    return FVClampRankedBrightness(brightness);
}

static BOOL FVRankedBrightnessCustomized(void) {
    return [[NSUserDefaults standardUserDefaults]
        boolForKey:FVRankedBrightnessCustomizedKey];
}

static CGFloat FVStoredRankedBrightnessForLevel(
    NSInteger level,
    NSInteger configuredCount
) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = FVRankedBrightnessKeyForLevel(level);
    NSNumber *storedValue = [defaults objectForKey:key];
    if (storedValue == nil) {
        return FVDefaultRankedBrightnessForLevel(level, configuredCount);
    }

    return FVClampRankedBrightness(storedValue.doubleValue);
}

static CGFloat FVRankedBrightnessForLevel(NSInteger level, NSInteger configuredCount) {
    if (!FVRankedBrightnessCustomized()) {
        return FVDefaultRankedBrightnessForLevel(level, configuredCount);
    }

    return FVStoredRankedBrightnessForLevel(level, configuredCount);
}

static CGFloat FVEffectiveRankedBrightness(CGFloat brightness) {
    brightness = FVClampRankedBrightness(brightness);
    return pow(brightness, FVRankedBrightnessResponseCurve);
}

static void FVNormalizeRankedBrightnessValues(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    CGFloat previousBrightness = FVMaximumRankedBrightness;
    NSInteger configuredCount = FVHighlightWindowCount();

    for (
        NSInteger level = FVMinimumHighlightWindowCount;
        level <= FVMaximumHighlightWindowCount;
        level++
    ) {
        CGFloat brightness = FVStoredRankedBrightnessForLevel(level, configuredCount);
        brightness = MIN(brightness, previousBrightness);
        brightness = FVClampRankedBrightness(brightness);
        [defaults setDouble:brightness forKey:FVRankedBrightnessKeyForLevel(level)];
        previousBrightness = brightness;
    }
}

static void FVEnsureRankedBrightnessCustomization(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (FVRankedBrightnessCustomized()) {
        return;
    }

    NSInteger configuredCount = FVHighlightWindowCount();
    for (
        NSInteger level = FVMinimumHighlightWindowCount;
        level <= FVMaximumHighlightWindowCount;
        level++
    ) {
        CGFloat brightness = FVDefaultRankedBrightnessForLevel(
            level,
            configuredCount
        );
        [defaults setDouble:brightness forKey:FVRankedBrightnessKeyForLevel(level)];
    }

    [defaults setBool:YES forKey:FVRankedBrightnessCustomizedKey];
}

static void FVSetRankedBrightnessForLevel(NSInteger level, CGFloat brightness) {
    level = MIN(MAX(level, FVMinimumHighlightWindowCount), FVMaximumHighlightWindowCount);
    FVEnsureRankedBrightnessCustomization();
    [[NSUserDefaults standardUserDefaults] setDouble:FVClampRankedBrightness(brightness)
                                              forKey:FVRankedBrightnessKeyForLevel(level)];
    FVNormalizeRankedBrightnessValues();
}

static void FVResetRankedBrightnessLevels(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    for (
        NSInteger level = FVMinimumHighlightWindowCount;
        level <= FVMaximumHighlightWindowCount;
        level++
    ) {
        [defaults removeObjectForKey:FVRankedBrightnessKeyForLevel(level)];
    }
    [defaults setBool:NO forKey:FVRankedBrightnessCustomizedKey];
}

static CGFloat FVIncrementalDimmingAmount(CGFloat previousAmount, CGFloat targetAmount) {
    previousAmount = MIN(MAX(previousAmount, 0), 0.95);
    targetAmount = MIN(MAX(targetAmount, previousAmount), 0.95);
    if (targetAmount <= previousAmount) {
        return 0;
    }

    return (targetAmount - previousAmount) / (1 - previousAmount);
}

@interface FVWindowSnapshot : NSObject
@property(nonatomic, readonly) CGWindowID windowNumber;
@property(nonatomic, readonly) CGRect frame;
- (instancetype)initWithWindowNumber:(CGWindowID)windowNumber frame:(CGRect)frame;
@end

@implementation FVWindowSnapshot

- (instancetype)initWithWindowNumber:(CGWindowID)windowNumber frame:(CGRect)frame {
    self = [super init];
    if (self) {
        _windowNumber = windowNumber;
        _frame = frame;
    }
    return self;
}

@end

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

static CGFloat FVRectArea(CGRect rect) {
    if (CGRectIsNull(rect) || CGRectIsEmpty(rect)) {
        return 0;
    }

    return CGRectGetWidth(rect) * CGRectGetHeight(rect);
}

static BOOL FVWindowFrameIsSubstantiallyVisible(CGRect frame) {
    CGFloat frameArea = FVRectArea(frame);
    if (frameArea <= 0) {
        return NO;
    }

    CGDirectDisplayID displays[32];
    uint32_t displayCount = 0;
    CGError error = CGGetActiveDisplayList(32, displays, &displayCount);
    if (error != kCGErrorSuccess || displayCount == 0) {
        return YES;
    }

    CGFloat visibleArea = 0;
    for (uint32_t index = 0; index < displayCount; index++) {
        CGRect displayBounds = CGDisplayBounds(displays[index]);
        visibleArea += FVRectArea(CGRectIntersection(frame, displayBounds));
    }

    return visibleArea / frameArea >= FVMinimumVisibleWindowAreaRatio;
}

static NSNumber *FVDisplayIdentifierWithLargestIntersection(CGRect frame) {
    CGDirectDisplayID displays[32];
    uint32_t displayCount = 0;
    CGError error = CGGetActiveDisplayList(32, displays, &displayCount);
    if (error != kCGErrorSuccess || displayCount == 0) {
        return nil;
    }

    CGFloat largestArea = 0;
    CGDirectDisplayID selectedDisplay = 0;
    for (uint32_t index = 0; index < displayCount; index++) {
        CGRect displayBounds = CGDisplayBounds(displays[index]);
        CGFloat area = FVRectArea(CGRectIntersection(frame, displayBounds));
        if (area > largestArea) {
            largestArea = area;
            selectedDisplay = displays[index];
        }
    }

    if (selectedDisplay == 0 || largestArea <= 0) {
        return nil;
    }

    return @(selectedDisplay);
}

static BOOL FVWindowSnapshotForProcess(
    pid_t processIdentifier,
    FVWindowSnapshot **result
) {
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
    FVWindowSnapshot *firstWindowSnapshot = nil;

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
            FVWindowSnapshot *snapshot = [[FVWindowSnapshot alloc]
                initWithWindowNumber:windowNumber.unsignedIntValue
                                frame:frame];
            if (firstWindowSnapshot == nil) {
                firstWindowSnapshot = snapshot;
            }
            if (hasFocusedFrame && FVRectApproximatelyEqual(frame, focusedFrame)) {
                *result = snapshot;
                return YES;
            }
        }
    }

    if (firstWindowSnapshot != nil) {
        *result = firstWindowSnapshot;
        return YES;
    }

    return NO;
}

static NSArray<FVWindowSnapshot *> *FVVisibleNormalWindowSnapshotsExcludingProcess(
    pid_t processIdentifier
) {
    CFArrayRef windowListReference = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
        kCGNullWindowID
    );
    if (windowListReference == NULL) {
        return @[];
    }

    NSArray<NSDictionary *> *windowList = CFBridgingRelease(windowListReference);
    NSString *ownerKey = (__bridge NSString *)kCGWindowOwnerPID;
    NSString *layerKey = (__bridge NSString *)kCGWindowLayer;
    NSString *numberKey = (__bridge NSString *)kCGWindowNumber;
    NSString *boundsKey = (__bridge NSString *)kCGWindowBounds;
    NSString *alphaKey = (__bridge NSString *)kCGWindowAlpha;
    NSMutableArray<FVWindowSnapshot *> *windowSnapshots = [NSMutableArray array];

    for (NSDictionary *window in windowList) {
        NSNumber *owner = window[ownerKey];
        NSNumber *layer = window[layerKey];
        NSNumber *windowNumber = window[numberKey];
        NSNumber *alpha = window[alphaKey];
        NSDictionary *bounds = window[boundsKey];
        CGRect frame = CGRectZero;

        if (
            owner.intValue != processIdentifier &&
            layer.integerValue == 0 &&
            windowNumber != nil &&
            alpha.doubleValue > 0.01 &&
            bounds != nil &&
            CGRectMakeWithDictionaryRepresentation(
                (__bridge CFDictionaryRef)bounds,
                &frame
            ) &&
            frame.size.width > 40 &&
            frame.size.height > 40 &&
            FVWindowFrameIsSubstantiallyVisible(frame)
        ) {
            FVWindowSnapshot *snapshot = [[FVWindowSnapshot alloc]
                initWithWindowNumber:windowNumber.unsignedIntValue
                                frame:frame];
            [windowSnapshots addObject:snapshot];
        }
    }

    return windowSnapshots;
}

static NSDictionary<NSNumber *, FVWindowSnapshot *> *FVWindowSnapshotsByWindowNumber(
    NSArray<FVWindowSnapshot *> *windowSnapshots
) {
    NSMutableDictionary<NSNumber *, FVWindowSnapshot *> *snapshotsByNumber =
        [NSMutableDictionary dictionary];
    for (FVWindowSnapshot *snapshot in windowSnapshots) {
        snapshotsByNumber[@(snapshot.windowNumber)] = snapshot;
    }
    return snapshotsByNumber;
}

static BOOL FVIsFinderApplication(NSRunningApplication *application) {
    return [application.bundleIdentifier isEqualToString:@"com.apple.finder"];
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
            | NSWindowCollectionBehaviorTransient
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
- (void)setRankedBrightnessEnabled:(BOOL)enabled;
- (void)setHighlightWindowCount:(NSInteger)count;
- (void)setRankedBrightness:(CGFloat)brightness forLevel:(NSInteger)level;
- (void)resetRankedBrightnessLevels;
@end

@implementation FVFocusController {
    NSMutableArray<NSMutableArray<FVOverlay *> *> *_overlayLayers;
    NSMutableArray<NSNumber *> *_overlayDisplayIdentifiers;
    NSMutableDictionary<NSNumber *, NSMutableArray<NSNumber *> *>
        *_recentWindowNumbersByDisplayIdentifier;
    NSTimer *_refreshTimer;
    pid_t _ownProcessIdentifier;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _overlayLayers = [NSMutableArray array];
        _overlayDisplayIdentifiers = [NSMutableArray array];
        _recentWindowNumbersByDisplayIdentifier = [NSMutableDictionary dictionary];
        _ownProcessIdentifier = NSProcessInfo.processInfo.processIdentifier;
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
    [self hideAllOverlayLayers];
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
    [self refresh:nil];
}

- (void)setRankedBrightnessEnabled:(BOOL)enabled {
    FVSetRankedBrightnessEnabled(enabled);
    [self rebuildOverlays];
    [self refresh:nil];
}

- (void)setHighlightWindowCount:(NSInteger)count {
    FVSetHighlightWindowCount(count);
    [self rebuildOverlays];
    [self refresh:nil];
}

- (void)setRankedBrightness:(CGFloat)brightness forLevel:(NSInteger)level {
    FVSetRankedBrightnessForLevel(level, brightness);
    [self refresh:nil];
}

- (void)resetRankedBrightnessLevels {
    FVResetRankedBrightnessLevels();
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
        [self hideAllOverlayLayers];
        return;
    }

    NSRunningApplication *frontmostApplication =
        NSWorkspace.sharedWorkspace.frontmostApplication;
    BOOL hasExternalFrontmostApplication = frontmostApplication
        && frontmostApplication.processIdentifier != _ownProcessIdentifier;
    BOOL frontmostHasWindow = NO;
    BOOL frontmostIsFinderDesktop = NO;
    FVWindowSnapshot *frontmostWindowSnapshot = nil;

    if (hasExternalFrontmostApplication) {
        FVWindowSnapshot *windowSnapshot = nil;
        if (
            FVWindowSnapshotForProcess(
                frontmostApplication.processIdentifier,
                &windowSnapshot
            )
        ) {
            frontmostWindowSnapshot = windowSnapshot;
            [self recordActiveWindowSnapshot:windowSnapshot];
            frontmostHasWindow = YES;
        } else {
            frontmostIsFinderDesktop = FVIsFinderApplication(frontmostApplication);
        }
    }

    NSArray<FVWindowSnapshot *> *visibleWindowSnapshots =
        FVVisibleNormalWindowSnapshotsExcludingProcess(_ownProcessIdentifier);
    NSDictionary<NSNumber *, FVWindowSnapshot *> *visibleWindowSnapshotsByNumber =
        FVWindowSnapshotsByWindowNumber(visibleWindowSnapshots);

    if (
        hasExternalFrontmostApplication &&
        !frontmostHasWindow &&
        !frontmostIsFinderDesktop
    ) {
        [self hideAllOverlayLayers];
        return;
    }

    if (frontmostHasWindow) {
        NSNumber *frontmostWindowRecord = @(frontmostWindowSnapshot.windowNumber);
        if (visibleWindowSnapshotsByNumber[frontmostWindowRecord] == nil) {
            [self hideAllOverlayLayers];
            return;
        }
    }

    if (
        !frontmostHasWindow &&
        [self hasRecentWindowNumbersForActiveDisplays] &&
        ![self topRecentWindowNumbersAreVisible:visibleWindowSnapshotsByNumber]
    ) {
        [self hideAllOverlayLayers];
        return;
    }

    [self pruneRecentWindowNumbersWithVisibleWindowSnapshotsByNumber:
        visibleWindowSnapshotsByNumber];
    [self seedMissingDisplayHistoriesWithVisibleWindowSnapshots:
        visibleWindowSnapshots];

    if (![self hasRecentWindowNumbersForActiveDisplays]) {
        [self hideAllOverlayLayers];
        return;
    }

    [self applyOverlayLayers];
}

- (NSMutableArray<NSNumber *> *)recentWindowNumbersForDisplayIdentifier:
    (NSNumber *)displayIdentifier
                                                           createIfNeeded:
    (BOOL)createIfNeeded {
    if (displayIdentifier == nil) {
        return nil;
    }

    NSMutableArray<NSNumber *> *recentWindowNumbers =
        _recentWindowNumbersByDisplayIdentifier[displayIdentifier];
    if (recentWindowNumbers == nil && createIfNeeded) {
        recentWindowNumbers = [NSMutableArray array];
        _recentWindowNumbersByDisplayIdentifier[displayIdentifier] =
            recentWindowNumbers;
    }
    return recentWindowNumbers;
}

- (void)recordActiveWindowSnapshot:(FVWindowSnapshot *)windowSnapshot {
    NSNumber *displayIdentifier =
        FVDisplayIdentifierWithLargestIntersection(windowSnapshot.frame);
    if (displayIdentifier == nil) {
        return;
    }

    NSNumber *record = @(windowSnapshot.windowNumber);
    [self removeWindowNumberFromAllDisplayHistories:record];

    NSMutableArray<NSNumber *> *recentWindowNumbers =
        [self recentWindowNumbersForDisplayIdentifier:displayIdentifier
                                      createIfNeeded:YES];
    [recentWindowNumbers insertObject:record atIndex:0];
    [self trimRecentWindowNumbers:recentWindowNumbers];
}

- (void)removeWindowNumberFromAllDisplayHistories:(NSNumber *)windowNumber {
    for (NSMutableArray<NSNumber *> *recentWindowNumbers
         in _recentWindowNumbersByDisplayIdentifier.allValues) {
        [recentWindowNumbers removeObject:windowNumber];
    }
}

- (void)pruneRecentWindowNumbersWithVisibleWindowSnapshotsByNumber:
    (NSDictionary<NSNumber *, FVWindowSnapshot *> *)visibleWindowSnapshotsByNumber {
    NSSet<NSNumber *> *activeDisplayIdentifiers =
        [NSSet setWithArray:_overlayDisplayIdentifiers];
    for (NSNumber *displayIdentifier
         in _recentWindowNumbersByDisplayIdentifier.allKeys.copy) {
        NSMutableArray<NSNumber *> *recentWindowNumbers =
            _recentWindowNumbersByDisplayIdentifier[displayIdentifier];
        if (![activeDisplayIdentifiers containsObject:displayIdentifier]) {
            [_recentWindowNumbersByDisplayIdentifier
                removeObjectForKey:displayIdentifier];
            continue;
        }

        NSIndexSet *removedIndexes = [recentWindowNumbers
            indexesOfObjectsPassingTest:^BOOL(
                NSNumber *windowNumber,
                NSUInteger index,
                BOOL *stop
            ) {
                FVWindowSnapshot *snapshot =
                    visibleWindowSnapshotsByNumber[windowNumber];
                if (snapshot == nil) {
                    return YES;
                }

                NSNumber *currentDisplayIdentifier =
                    FVDisplayIdentifierWithLargestIntersection(snapshot.frame);
                return ![currentDisplayIdentifier isEqualToNumber:displayIdentifier];
            }];
        [recentWindowNumbers removeObjectsAtIndexes:removedIndexes];
        [self trimRecentWindowNumbers:recentWindowNumbers];
        if (recentWindowNumbers.count == 0) {
            [_recentWindowNumbersByDisplayIdentifier
                removeObjectForKey:displayIdentifier];
        }
    }
}

- (void)seedMissingDisplayHistoriesWithVisibleWindowSnapshots:
    (NSArray<FVWindowSnapshot *> *)visibleWindowSnapshots {
    NSSet<NSNumber *> *activeDisplayIdentifiers =
        [NSSet setWithArray:_overlayDisplayIdentifiers];
    for (FVWindowSnapshot *snapshot in visibleWindowSnapshots) {
        NSNumber *displayIdentifier =
            FVDisplayIdentifierWithLargestIntersection(snapshot.frame);
        if (
            displayIdentifier == nil ||
            ![activeDisplayIdentifiers containsObject:displayIdentifier]
        ) {
            continue;
        }

        NSMutableArray<NSNumber *> *recentWindowNumbers =
            [self recentWindowNumbersForDisplayIdentifier:displayIdentifier
                                          createIfNeeded:NO];
        if (recentWindowNumbers.count > 0) {
            continue;
        }

        recentWindowNumbers =
            [self recentWindowNumbersForDisplayIdentifier:displayIdentifier
                                          createIfNeeded:YES];
        [recentWindowNumbers addObject:@(snapshot.windowNumber)];
    }
}

- (BOOL)hasRecentWindowNumbersForActiveDisplays {
    for (NSNumber *displayIdentifier in _overlayDisplayIdentifiers) {
        NSArray<NSNumber *> *recentWindowNumbers =
            _recentWindowNumbersByDisplayIdentifier[displayIdentifier];
        if (recentWindowNumbers.count > 0) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)topRecentWindowNumbersAreVisible:
    (NSDictionary<NSNumber *, FVWindowSnapshot *> *)visibleWindowSnapshotsByNumber {
    for (NSNumber *displayIdentifier in _overlayDisplayIdentifiers) {
        NSArray<NSNumber *> *recentWindowNumbers =
            _recentWindowNumbersByDisplayIdentifier[displayIdentifier];
        if (recentWindowNumbers.count == 0) {
            continue;
        }

        NSNumber *topWindowNumber = recentWindowNumbers.firstObject;
        if (visibleWindowSnapshotsByNumber[topWindowNumber] == nil) {
            return NO;
        }
    }
    return YES;
}

- (void)trimRecentWindowNumbers:(NSMutableArray<NSNumber *> *)recentWindowNumbers {
    NSUInteger limit = (NSUInteger)FVMaximumHighlightWindowCount + 1;
    while (recentWindowNumbers.count > limit) {
        [recentWindowNumbers removeLastObject];
    }
}

- (CGFloat)targetDimmingAmountForLayerIndex:(NSUInteger)layerIndex
                         usedHighlightCount:(NSUInteger)usedHighlightCount
                   configuredHighlightCount:(NSInteger)configuredHighlightCount
                              deepestAmount:(CGFloat)deepestAmount {
    if (
        FVRankedBrightnessEnabled() &&
        usedHighlightCount > 0 &&
        layerIndex < usedHighlightCount
    ) {
        NSInteger level = (NSInteger)layerIndex + 1;
        CGFloat brightness = FVRankedBrightnessForLevel(
            level,
            configuredHighlightCount
        );
        return deepestAmount * (1 - FVEffectiveRankedBrightness(brightness));
    }

    return deepestAmount;
}

- (void)applyOverlayLayers {
    NSInteger configuredHighlightCount = FVRankedBrightnessEnabled()
        ? FVHighlightWindowCount()
        : 0;
    CGFloat deepestAmount = FVDimmingAmount();

    for (NSUInteger layerIndex = 0; layerIndex < _overlayLayers.count; layerIndex++) {
        NSArray<FVOverlay *> *overlays = _overlayLayers[layerIndex];
        for (NSUInteger overlayIndex = 0; overlayIndex < overlays.count; overlayIndex++) {
            FVOverlay *overlay = overlays[overlayIndex];
            if (overlayIndex >= _overlayDisplayIdentifiers.count) {
                [overlay hide];
                continue;
            }

            NSNumber *displayIdentifier = _overlayDisplayIdentifiers[overlayIndex];
            NSArray<NSNumber *> *recentWindowNumbers =
                _recentWindowNumbersByDisplayIdentifier[displayIdentifier];
            if (recentWindowNumbers.count == 0) {
                [overlay hide];
                continue;
            }

            NSUInteger availableHighlightCount = recentWindowNumbers.count > 0
                ? recentWindowNumbers.count - 1
                : 0;
            NSUInteger usedHighlightCount =
                MIN((NSUInteger)configuredHighlightCount, availableHighlightCount);
            NSUInteger boundaryCount = usedHighlightCount + 1;
            if (layerIndex >= boundaryCount) {
                [overlay hide];
                continue;
            }

            CGFloat targetAmount = [self targetDimmingAmountForLayerIndex:layerIndex
                                                       usedHighlightCount:usedHighlightCount
                                                 configuredHighlightCount:configuredHighlightCount
                                                            deepestAmount:deepestAmount];
            CGFloat previousTargetAmount = layerIndex == 0
                ? 0
                : [self targetDimmingAmountForLayerIndex:layerIndex - 1
                                      usedHighlightCount:usedHighlightCount
                                configuredHighlightCount:configuredHighlightCount
                                           deepestAmount:deepestAmount];
            CGFloat layerAmount = FVIncrementalDimmingAmount(
                previousTargetAmount,
                targetAmount
            );

            CGWindowID windowNumber =
                recentWindowNumbers[layerIndex].unsignedIntValue;
            [overlay updateDimmingAmount:layerAmount];
            [overlay showBelowWindowNumber:windowNumber];
        }
    }
}

- (void)pruneHistoriesForActiveDisplays {
    NSSet<NSNumber *> *activeDisplayIdentifiers =
        [NSSet setWithArray:_overlayDisplayIdentifiers];
    for (NSNumber *displayIdentifier
         in _recentWindowNumbersByDisplayIdentifier.allKeys.copy) {
        if (![activeDisplayIdentifiers containsObject:displayIdentifier]) {
            [_recentWindowNumbersByDisplayIdentifier
                removeObjectForKey:displayIdentifier];
        }
    }
}

- (void)rebuildOverlays {
    [self hideAllOverlayLayers];
    [_overlayLayers removeAllObjects];
    [_overlayDisplayIdentifiers removeAllObjects];

    NSMutableArray<NSScreen *> *screens = [NSMutableArray array];
    for (NSScreen *screen in NSScreen.screens) {
        NSNumber *displayIdentifier = screen.deviceDescription[@"NSScreenNumber"];
        if (displayIdentifier == nil) {
            continue;
        }

        [_overlayDisplayIdentifiers addObject:displayIdentifier];
        [screens addObject:screen];
    }
    [self pruneHistoriesForActiveDisplays];

    NSUInteger layerCount = FVRankedBrightnessEnabled()
        ? (NSUInteger)FVHighlightWindowCount() + 1
        : 1;

    for (NSUInteger layerIndex = 0; layerIndex < layerCount; layerIndex++) {
        NSMutableArray<FVOverlay *> *overlays = [NSMutableArray array];
        for (NSScreen *screen in screens) {
            FVOverlay *overlay = [[FVOverlay alloc] initWithScreen:screen
                                                    dimmingAmount:0];
            [overlays addObject:overlay];
        }
        [_overlayLayers addObject:overlays];
    }
}

- (void)hideAllOverlayLayers {
    for (NSArray<FVOverlay *> *overlays in _overlayLayers) {
        for (FVOverlay *overlay in overlays) {
            [overlay hide];
        }
    }
}

@end

@interface FVAppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@end

@implementation FVAppDelegate {
    FVFocusController *_focusController;
    NSStatusItem *_statusItem;
    NSMenuItem *_enabledItem;
    NSMenuItem *_rankedBrightnessItem;
    NSMenuItem *_highlightWindowCountItem;
    NSMenuItem *_rankedBrightnessControlsItem;
    NSMenuItem *_permissionItem;
    NSMenuItem *_launchAtLoginItem;
    NSSlider *_intensitySlider;
    NSMutableArray<NSSlider *> *_rankedBrightnessSliders;
    NSMutableArray<NSTextField *> *_rankedBrightnessLabels;
    NSMutableArray<NSTextField *> *_rankedBrightnessValueLabels;
    NSButton *_resetRankedBrightnessButton;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _focusController = [[FVFocusController alloc] init];
        _rankedBrightnessSliders = [NSMutableArray array];
        _rankedBrightnessLabels = [NSMutableArray array];
        _rankedBrightnessValueLabels = [NSMutableArray array];
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

    _rankedBrightnessItem = [[NSMenuItem alloc] initWithTitle:@"启用分级亮度"
                                                       action:@selector(toggleRankedBrightness:)
                                                keyEquivalent:@""];
    _rankedBrightnessItem.target = self;
    [menu addItem:_rankedBrightnessItem];

    _highlightWindowCountItem = [self highlightWindowCountMenuItem];
    [menu addItem:_highlightWindowCountItem];

    _rankedBrightnessControlsItem = [self rankedBrightnessControlsMenuItem];
    [menu addItem:_rankedBrightnessControlsItem];
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

- (NSMenuItem *)highlightWindowCountMenuItem {
    NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:@"历史高亮窗口"
                                                     action:nil
                                              keyEquivalent:@""];
    NSMenu *submenu = [[NSMenu alloc] initWithTitle:@"历史高亮窗口"];

    for (
        NSInteger count = FVMinimumHighlightWindowCount;
        count <= FVMaximumHighlightWindowCount;
        count++
    ) {
        NSString *title = [NSString stringWithFormat:@"%ld 个窗口", (long)count];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                      action:@selector(selectHighlightWindowCount:)
                                               keyEquivalent:@""];
        item.target = self;
        item.tag = count;
        [submenu addItem:item];
    }

    menuItem.submenu = submenu;
    return menuItem;
}

- (NSMenuItem *)rankedBrightnessControlsMenuItem {
    NSMenuItem *menuItem = [[NSMenuItem alloc] init];
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 286, 212)];

    NSTextField *titleLabel = [NSTextField labelWithString:@"分级亮度"];
    titleLabel.frame = NSMakeRect(16, 188, 120, 17);
    titleLabel.font = [NSFont menuFontOfSize:13];

    [container addSubview:titleLabel];

    for (
        NSInteger level = FVMinimumHighlightWindowCount;
        level <= FVMaximumHighlightWindowCount;
        level++
    ) {
        CGFloat y = 188 - (CGFloat)level * 36;

        NSTextField *label = [NSTextField labelWithString:
            [NSString stringWithFormat:@"第 %ld 级", (long)level]];
        label.frame = NSMakeRect(16, y + 7, 58, 17);
        label.font = [NSFont menuFontOfSize:12];

        NSSlider *slider = [[NSSlider alloc] initWithFrame:NSMakeRect(76, y, 150, 26)];
        slider.minValue = FVMinimumRankedBrightness;
        slider.maxValue = FVMaximumRankedBrightness;
        slider.continuous = YES;
        slider.target = self;
        slider.action = @selector(rankedBrightnessDidChange:);
        slider.tag = level;

        NSTextField *valueLabel = [NSTextField labelWithString:@""];
        valueLabel.frame = NSMakeRect(234, y + 7, 38, 17);
        valueLabel.font = [NSFont menuFontOfSize:12];
        valueLabel.alignment = NSTextAlignmentRight;

        [container addSubview:label];
        [container addSubview:slider];
        [container addSubview:valueLabel];
        [_rankedBrightnessLabels addObject:label];
        [_rankedBrightnessSliders addObject:slider];
        [_rankedBrightnessValueLabels addObject:valueLabel];
    }

    _resetRankedBrightnessButton = [NSButton buttonWithTitle:@"恢复默认"
                                                      target:self
                                                      action:@selector(resetRankedBrightness:)];
    _resetRankedBrightnessButton.frame = NSMakeRect(16, 10, 96, 26);
    _resetRankedBrightnessButton.bezelStyle = NSBezelStyleRounded;
    [container addSubview:_resetRankedBrightnessButton];

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
    _rankedBrightnessItem.state = FVRankedBrightnessEnabled()
        ? NSControlStateValueOn
        : NSControlStateValueOff;

    NSInteger highlightWindowCount = FVHighlightWindowCount();
    _highlightWindowCountItem.title = [NSString stringWithFormat:
        @"历史高亮窗口：%ld",
        (long)highlightWindowCount
    ];
    _highlightWindowCountItem.enabled = FVRankedBrightnessEnabled();
    for (NSMenuItem *item in _highlightWindowCountItem.submenu.itemArray) {
        item.state = item.tag == highlightWindowCount
            ? NSControlStateValueOn
            : NSControlStateValueOff;
    }
    [self updateRankedBrightnessControlsWithCount:highlightWindowCount];

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

- (void)updateRankedBrightnessControlsWithCount:(NSInteger)highlightWindowCount {
    BOOL controlsEnabled = FVRankedBrightnessEnabled();
    _rankedBrightnessControlsItem.enabled = controlsEnabled;
    _resetRankedBrightnessButton.enabled = controlsEnabled;

    for (NSUInteger index = 0; index < _rankedBrightnessSliders.count; index++) {
        NSInteger level = (NSInteger)index + 1;
        NSSlider *slider = _rankedBrightnessSliders[index];
        NSTextField *label = _rankedBrightnessLabels[index];
        NSTextField *valueLabel = _rankedBrightnessValueLabels[index];
        BOOL levelEnabled = controlsEnabled && level <= highlightWindowCount;
        CGFloat brightness = FVRankedBrightnessForLevel(level, highlightWindowCount);

        slider.doubleValue = brightness;
        slider.enabled = levelEnabled;
        valueLabel.stringValue = [NSString stringWithFormat:
            @"%.0f%%",
            brightness * 100
        ];
        label.textColor = levelEnabled
            ? NSColor.labelColor
            : NSColor.disabledControlTextColor;
        valueLabel.textColor = levelEnabled
            ? NSColor.labelColor
            : NSColor.disabledControlTextColor;
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

- (void)toggleRankedBrightness:(id)sender {
    [_focusController setRankedBrightnessEnabled:!FVRankedBrightnessEnabled()];
    [self updateMenuState];
}

- (void)selectHighlightWindowCount:(NSMenuItem *)sender {
    [_focusController setHighlightWindowCount:sender.tag];
    [self updateMenuState];
}

- (void)rankedBrightnessDidChange:(NSSlider *)sender {
    [_focusController setRankedBrightness:sender.doubleValue forLevel:sender.tag];
    [self updateMenuState];
}

- (void)resetRankedBrightness:(id)sender {
    [_focusController resetRankedBrightnessLevels];
    [self updateMenuState];
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
