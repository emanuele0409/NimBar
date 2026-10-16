// SPDX-License-Identifier: GPL-3.0-only
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Runtime-checked bridge to macOS 27's private native menu-bar visibility API.
/// The assertion is released on failure and when the app exits.
@interface MenuBarNativeHider : NSObject

@property(nonatomic, readonly, getter=isAvailable) BOOL available;

- (void)applyHiddenBundleIdentifiers:(NSSet<NSString *> *)bundleIdentifiers
                          completion:(void (^)(NSError * _Nullable error))completion;
- (void)restoreAll;

/// Window Server's real menu-bar-item window bounds. Returns an empty array
/// when the private enumeration entry points are unavailable.
+ (NSArray<NSValue *> *)menuBarItemFrames;
+ (NSArray<NSDictionary<NSString *, id> *> *)menuBarWindows;
/// Captures only the requested menu window, with transparency and best resolution.
+ (nullable NSImage *)captureMenuBarWindow:(uint32_t)windowID;

@end

NS_ASSUME_NONNULL_END
