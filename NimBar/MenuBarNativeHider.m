// SPDX-License-Identifier: GPL-3.0-only
#import "MenuBarNativeHider.h"
#import <AppKit/AppKit.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <math.h>
#import <stdlib.h>

@interface MenuBarNativeHider ()
@property(nonatomic, strong, nullable) id activeAssertion;
@property(nonatomic, strong, nullable) id pendingAssertion;
@property(nonatomic, strong) NSSet<NSString *> *requestedHiddenBundles;
@property(nonatomic) NSUInteger generation;
@property(nonatomic, strong) NSMutableArray<id> *workspaceObservers;
@property(nonatomic) NSUInteger workspaceRefreshGeneration;
@property(nonatomic) BOOL needsWorkspaceRefresh;
@property(nonatomic, readwrite, getter=isAvailable) BOOL available;
@end

@implementation MenuBarNativeHider

+ (NSArray<NSDictionary<NSString *, id> *> *)menuBarWindows {
    // These Window Server entry points are private and version-sensitive.
    // Resolve them dynamically and fail closed to the Accessibility scanner.
    static void *skyLight = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL);
    });
    if (!skyLight) return @[];

    typedef int32_t (*MainConnectionFunction)(void);
    typedef int32_t (*WindowCountFunction)(int32_t, int32_t, int32_t *);
    typedef int32_t (*MenuBarWindowsFunction)(int32_t, int32_t, int32_t, CGWindowID *, int32_t *);
    typedef int32_t (*WindowLevelFunction)(int32_t, CGWindowID, CGWindowLevel *);
    typedef int32_t (*WindowBoundsFunction)(int32_t, CGWindowID, CGRect *);

    MainConnectionFunction mainConnection = (MainConnectionFunction)dlsym(skyLight, "CGSMainConnectionID");
    WindowCountFunction windowCount = (WindowCountFunction)dlsym(skyLight, "CGSGetWindowCount");
    MenuBarWindowsFunction menuBarWindows = (MenuBarWindowsFunction)dlsym(skyLight, "CGSGetProcessMenuBarWindowList");
    WindowLevelFunction windowLevel = (WindowLevelFunction)dlsym(skyLight, "CGSGetWindowLevel");
    WindowBoundsFunction windowBounds = (WindowBoundsFunction)dlsym(skyLight, "CGSGetScreenRectForWindow");
    if (!mainConnection || !windowCount || !menuBarWindows || !windowLevel || !windowBounds) {
        return @[];
    }

    int32_t connection = mainConnection();
    int32_t count = 0;
    int32_t countResult = windowCount(connection, 0, &count);
    if (countResult != 0 || count <= 0 || count > 10000) return @[];
    NSMutableArray<NSDictionary<NSString *, id> *> *windows = [NSMutableArray array];
    CGWindowID *windowIDs = calloc((size_t)count, sizeof(CGWindowID));
    if (!windowIDs) return @[];
    int32_t returnedCount = count;
    int32_t result = menuBarWindows(connection, 0, count, windowIDs, &returnedCount);
    if (result == 0 && returnedCount > 0 && returnedCount <= count) {
        for (int32_t index = 0; index < returnedCount; index++) {
            CGWindowLevel level = 0;
            CGRect bounds = CGRectZero;
            // macOS 27 composites items in the main menu window. Retain that
            // surface too; AX supplies the individual item owner and bounds.
            if (windowLevel(connection, windowIDs[index], &level) != 0) continue;
            if (windowBounds(connection, windowIDs[index], &bounds) != 0 || CGRectIsEmpty(bounds) || !isfinite(bounds.origin.x) || !isfinite(bounds.origin.y)) continue;
            [windows addObject:@{@"windowID": @(windowIDs[index]), @"frame": [NSValue valueWithRect:NSRectFromCGRect(bounds)], @"container": @(level == kCGMainMenuWindowLevel)}];
        }
    }
    free(windowIDs);
    return windows;
}

+ (NSArray<NSValue *> *)menuBarItemFrames {
    return [[self menuBarWindows] valueForKey:@"frame"];
}

+ (NSImage *)captureMenuBarWindow:(uint32_t)windowID {
    if (!windowID || !CGPreflightScreenCaptureAccess()) return nil;
    static void *framework;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        framework = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL);
    });
    typedef CGImageRef (*CaptureFunction)(CGRect, CFArrayRef, CGWindowImageOption);
    CaptureFunction capture = framework ? (CaptureFunction)dlsym(framework, "SLWindowListCreateImageFromArray") : NULL;
    if (!capture) return nil;
    // CG window arrays contain the raw integer bit patterns, not CFNumbers.
    const void *pointer = (const void *)(uintptr_t)windowID;
    CFArrayRef windows = CFArrayCreate(NULL, &pointer, 1, NULL);
    CGImageRef image = capture(CGRectNull, windows, kCGWindowImageBoundsIgnoreFraming | kCGWindowImageBestResolution);
    CFRelease(windows);
    if (!image) return nil;
    NSImage *result = [[NSImage alloc] initWithCGImage:image size:NSZeroSize];
    CGImageRelease(image);
    return result;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;

    if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27) {
        void *framework = dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_LAZY | RTLD_LOCAL);
        Class configurationClass = NSClassFromString(@"MBAssessmentModeConfiguration");
        Class assertionClass = NSClassFromString(@"MBAssessmentModeAssertion");
        SEL configure = NSSelectorFromString(@"initWithAllowedSystemItems:allowedBundleIdentifiers:");
        SEL activate = NSSelectorFromString(@"activateWithConfiguration:completionHandler:");
        SEL invalidate = NSSelectorFromString(@"invalidate");
        self.available = framework != NULL &&
            [configurationClass instancesRespondToSelector:configure] &&
            [assertionClass instancesRespondToSelector:activate] &&
            [assertionClass instancesRespondToSelector:invalidate];
    }

    self.requestedHiddenBundles = [NSSet set];
    self.workspaceObservers = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    NSNotificationCenter *workspaceCenter = NSWorkspace.sharedWorkspace.notificationCenter;
    for (NSNotificationName name in @[NSWorkspaceDidLaunchApplicationNotification, NSWorkspaceDidTerminateApplicationNotification]) {
        id observer = [workspaceCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *notification) {
            typeof(self) self = weakSelf;
            if (!self || !self.requestedHiddenBundles.count) return;
            self.workspaceRefreshGeneration += 1;
            NSUInteger refreshGeneration = self.workspaceRefreshGeneration;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (refreshGeneration != self.workspaceRefreshGeneration || !self.requestedHiddenBundles.count) return;
                if (self.pendingAssertion) {
                    self.needsWorkspaceRefresh = YES;
                    return;
                }
                [self applyHiddenBundleIdentifiers:self.requestedHiddenBundles completion:^(__unused NSError *error) {}];
            });
        }];
        [self.workspaceObservers addObject:observer];
    }
    return self;
}

- (void)applyHiddenBundleIdentifiers:(NSSet<NSString *> *)bundleIdentifiers
                          completion:(void (^)(NSError * _Nullable error))completion {
    NSAssert(NSThread.isMainThread, @"Menu-bar assertions must be managed on the main thread");
    if (!self.available) {
        completion([NSError errorWithDomain:@"NimBar.MenuBarNativeHider" code:1
                                   userInfo:@{NSLocalizedDescriptionKey: @"L'API nativa per nascondere le icone non è disponibile su questa versione di macOS."}]);
        return;
    }

    NSMutableSet<NSString *> *protectedHiddenBundles = [bundleIdentifiers mutableCopy];
    NSString *ownBundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
    if (ownBundleIdentifier.length) [protectedHiddenBundles removeObject:ownBundleIdentifier];
    self.requestedHiddenBundles = [protectedHiddenBundles copy];
    self.generation += 1;
    NSUInteger requestGeneration = self.generation;
    [self invalidateAssertion:self.pendingAssertion];
    self.pendingAssertion = nil;

    NSMutableSet<NSString *> *allowedBundles = [NSMutableSet set];
    // The assessment assertion must never block macOS' own launchers and
    // search surfaces. Some of them are on-demand services and aren't listed
    // as running applications when the assertion is first installed.
    [allowedBundles addObjectsFromArray:@[
        @"com.apple.dock",
        @"com.apple.launchpad",
        @"com.apple.Launchpad",
        @"com.apple.Spotlight",
        @"com.apple.finder"
    ]];
    for (NSRunningApplication *application in NSWorkspace.sharedWorkspace.runningApplications) {
        NSString *identifier = application.bundleIdentifier;
        if (identifier.length && ![self.requestedHiddenBundles containsObject:identifier]) {
            [allowedBundles addObject:identifier];
        }
    }
    // NimBar's own status item is the recovery path for hidden apps and settings.
    if (ownBundleIdentifier.length) [allowedBundles addObject:ownBundleIdentifier];

    @try {
        Class configurationClass = NSClassFromString(@"MBAssessmentModeConfiguration");
        Class assertionClass = NSClassFromString(@"MBAssessmentModeAssertion");
        SEL configure = NSSelectorFromString(@"initWithAllowedSystemItems:allowedBundleIdentifiers:");
        SEL activate = NSSelectorFromString(@"activateWithConfiguration:completionHandler:");
        SEL invalidate = NSSelectorFromString(@"invalidate");

        id configuration = ((id (*)(id, SEL, id, id))objc_msgSend)(
            [configurationClass alloc], configure,
            @[@0, @1, @2, @3, @4, @5, @6, @7, @8], allowedBundles.allObjects);
        id assertion = [[assertionClass alloc] init];
        if (!configuration || !assertion) {
            @throw [NSException exceptionWithName:@"NimBarNativeAPIUnavailable"
                                           reason:@"Impossibile creare la configurazione di visibilità."
                                         userInfo:nil];
        }
        self.pendingAssertion = assertion;

        __weak typeof(self) weakSelf = self;
        void (^handler)(NSError *) = ^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(self) self = weakSelf;
                if (!self || requestGeneration != self.generation || self.pendingAssertion != assertion) {
                    ((void (*)(id, SEL))objc_msgSend)(assertion, invalidate);
                    return;
                }
                self.pendingAssertion = nil;
                if (error) {
                    [self invalidateAssertion:assertion];
                    [self restoreAll];
                    completion(error);
                    return;
                }
                [self invalidateAssertion:self.activeAssertion];
                self.activeAssertion = assertion;
                completion(nil);
                if (self.needsWorkspaceRefresh) {
                    self.needsWorkspaceRefresh = NO;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self applyHiddenBundleIdentifiers:self.requestedHiddenBundles completion:^(__unused NSError *refreshError) {}];
                    });
                }
            });
        };

        ((void (*)(id, SEL, id, id))objc_msgSend)(assertion, activate, configuration, handler);

        // Never allow a stuck private callback to strand menu-bar items.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf;
            if (!self || requestGeneration != self.generation || self.pendingAssertion != assertion) return;
            self.generation += 1;
            self.pendingAssertion = nil;
            [self invalidateAssertion:assertion];
            [self restoreAll];
            completion([NSError errorWithDomain:@"NimBar.MenuBarNativeHider" code:2
                                       userInfo:@{NSLocalizedDescriptionKey: @"La richiesta macOS è scaduta; le icone sono state ripristinate."}]);
        });
    } @catch (NSException *exception) {
        [self restoreAll];
        completion([NSError errorWithDomain:@"NimBar.MenuBarNativeHider" code:3
                                   userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"L'API nativa ha rifiutato la richiesta."}]);
    }
}

- (void)restoreAll {
    NSAssert(NSThread.isMainThread, @"Menu-bar assertions must be managed on the main thread");
    self.generation += 1;
    [self invalidateAssertion:self.pendingAssertion];
    [self invalidateAssertion:self.activeAssertion];
    self.pendingAssertion = nil;
    self.activeAssertion = nil;
    self.requestedHiddenBundles = [NSSet set];
    self.needsWorkspaceRefresh = NO;
}

- (void)invalidateAssertion:(id)assertion {
    if (!assertion) return;
    SEL invalidate = NSSelectorFromString(@"invalidate");
    if ([assertion respondsToSelector:invalidate]) {
        ((void (*)(id, SEL))objc_msgSend)(assertion, invalidate);
    }
}

- (void)dealloc {
    for (id observer in _workspaceObservers) {
        [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:observer];
    }
    id pending = _pendingAssertion;
    id active = _activeAssertion;
    if (pending) ((void (*)(id, SEL))objc_msgSend)(pending, NSSelectorFromString(@"invalidate"));
    if (active) ((void (*)(id, SEL))objc_msgSend)(active, NSSelectorFromString(@"invalidate"));
}

@end
