// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import AppKit
import ServiceManagement
import QuartzCore
@testable import NimBar

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testDefaultsAreSafeAndDisabled() {
        let store = SettingsStore(defaults: makeDefaults())
        XCTAssertFalse(store.autoHideEnabled)
        XCTAssertEqual(store.autoHideDelay, .five)
    }

    func testSwipeIsOptInAndDirectionsRemainComplementaryAfterRelaunch() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.menuBarSwipeEnabled)
        XCTAssertEqual(store.showSwipeDirection, .left)
        XCTAssertEqual(store.hideSwipeDirection, .right)
        store.menuBarSwipeEnabled = true
        store.setHideSwipeDirection(.left)
        let restored = SettingsStore(defaults: defaults)
        XCTAssertTrue(restored.menuBarSwipeEnabled)
        XCTAssertEqual(restored.showSwipeDirection, .right)
        XCTAssertEqual(restored.hideSwipeDirection, .left)
        restored.showSwipeDirection = .left
        XCTAssertEqual(restored.hideSwipeDirection, .right)
    }

    func testSwipeAccumulatesOnceAndIgnoresMomentumUntilANewGesture() throws {
        var recognizer = MenuBarSwipeRecognizer()
        let origin = CGPoint(x: 100, y: 900)
        XCTAssertNil(recognizer.consume(.init(x: 7, began: true, timestamp: 1, location: origin),
                                        displayID: 1, isOverMenuBar: true))
        let intent = try XCTUnwrap(recognizer.consume(.init(x: 12, phased: true, timestamp: 1.1),
                                                     displayID: 1, isOverMenuBar: true))
        XCTAssertEqual(intent, MenuBarSwipeIntent(direction: .left, origin: origin, displayID: 1))
        // Even a pause inside a phased stroke must not rearm it.
        XCTAssertNil(recognizer.consume(.init(x: 30, phased: true, timestamp: 2), displayID: 1, isOverMenuBar: true))
        XCTAssertNil(recognizer.consume(.init(x: -30, momentum: true, timestamp: 2.1), displayID: 1, isOverMenuBar: true))
        XCTAssertEqual(recognizer.consume(.init(x: -20, began: true, timestamp: 3), displayID: 1,
                                          isOverMenuBar: true)?.direction, .right)
    }

    func testSwipeNormalizesNaturalScrollingAndRejectsVerticalAndCrossDisplayStrokes() {
        var recognizer = MenuBarSwipeRecognizer()
        XCTAssertEqual(recognizer.consume(.init(x: -20, inverted: true, began: true, timestamp: 1),
                                          displayID: 1, isOverMenuBar: true)?.direction, .left)
        recognizer.reset()
        XCTAssertNil(recognizer.consume(.init(x: 2, y: 20, began: true, timestamp: 2), displayID: 1, isOverMenuBar: true))
        XCTAssertNil(recognizer.consume(.init(x: 50, phased: true, timestamp: 2.1), displayID: 1, isOverMenuBar: true))
        recognizer.reset()
        XCTAssertNil(recognizer.consume(.init(x: 8, began: true, timestamp: 3), displayID: 1, isOverMenuBar: true))
        XCTAssertNil(recognizer.consume(.init(x: 20, phased: true, timestamp: 3.1), displayID: 2, isOverMenuBar: true))
        XCTAssertNil(recognizer.consume(.init(x: 20, phased: true, timestamp: 3.2), displayID: 1, isOverMenuBar: true))
    }

    func testSwipeCannotBeginOutsideBarAndWheelRearmsOnlyAfterIdle() {
        var recognizer = MenuBarSwipeRecognizer()
        XCTAssertNil(recognizer.consume(.init(x: 20, began: true, timestamp: 1), displayID: 1, isOverMenuBar: false))
        XCTAssertNil(recognizer.consume(.init(x: 20, phased: true, timestamp: 1.1), displayID: 1, isOverMenuBar: true))
        recognizer.reset()
        XCTAssertNotNil(recognizer.consume(.init(x: 1, precise: false, timestamp: 2), displayID: 1, isOverMenuBar: true))
        XCTAssertNil(recognizer.consume(.init(x: 1, precise: false, timestamp: 2.1), displayID: 1, isOverMenuBar: true))
        XCTAssertNotNil(recognizer.consume(.init(x: 1, precise: false, timestamp: 2.5), displayID: 1, isOverMenuBar: true))
    }

    func testAlphaRevisionAndChannelPrecedenceUseSeparateVersionAndBuildNumbers() {
        let url = URL(string: "https://example.invalid/NimBar.dmg")!
        let alpha = AppUpdateRelease(version: "0.3.0.1", build: 47, assetURL: url, isPrerelease: true, isAlpha: true)
        let nextAlpha = AppUpdateRelease(version: "0.3.0.2", build: 48, assetURL: url, isPrerelease: true, isAlpha: true)
        let beta = AppUpdateRelease(version: "0.3.0", build: 1, assetURL: url, isPrerelease: true)
        let stable = AppUpdateRelease(version: "0.3.0", build: 1, assetURL: url)
        XCTAssertTrue(nextAlpha.isNewer(than: alpha))
        XCTAssertFalse(alpha.isNewer(than: nextAlpha))
        XCTAssertTrue(beta.isNewer(than: nextAlpha))
        XCTAssertTrue(stable.isNewer(than: beta))
        XCTAssertFalse(nextAlpha.isNewer(than: stable))
    }

    func testReleaseDiscoveryKeepsAlphaOutOfBetaAndStableChannels() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReleaseFixtureURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let stable = try await GitHubReleaseService(session: session, allowsPrereleases: false,
                                                    allowsAlphaReleases: false).latestRelease()
        XCTAssertEqual(stable?.version, "0.2.1")
        let beta = try await GitHubReleaseService(session: session, allowsPrereleases: true,
                                                  allowsAlphaReleases: false).latestRelease()
        XCTAssertEqual(beta?.version, "0.3.0")
        XCTAssertFalse(beta?.isAlpha ?? true)
        let alpha = try await GitHubReleaseService(session: session, allowsPrereleases: true,
                                                   allowsAlphaReleases: true).latestRelease()
        XCTAssertEqual(alpha?.version, "0.4.0.2")
        XCTAssertEqual(alpha?.build, 48)
        XCTAssertTrue(alpha?.isAlpha ?? false)
    }

    func testPackagedMetadataDeclaresItsChannelAndVersionFormat() throws {
        let channel = try XCTUnwrap(Bundle.main.infoDictionary?["NIMBARReleaseChannel"] as? String)
        XCTAssertTrue(["alpha", "beta", "stable"].contains(channel))
        let version = try XCTUnwrap(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
        XCTAssertEqual(version.split(separator: ".").count, channel == "alpha" ? 4 : 3)
        XCTAssertEqual(AppVersion.channel, channel)
        XCTAssertTrue(AppVersion.displayName.contains(version))
    }
    func testLoginRegistrationUsesSystemStatusAndAvoidsDuplicateRequests() {
        let service = FakeLoginItemService()
        let controller = LoginItemController(service: service)
        XCTAssertFalse(controller.isRegistered)
        controller.setEnabled(true)
        XCTAssertTrue(controller.isRegistered)
        XCTAssertEqual(service.registrations, 1)
        controller.setEnabled(true)
        XCTAssertEqual(service.registrations, 1)
        controller.setEnabled(false)
        XCTAssertFalse(controller.isRegistered)
        XCTAssertEqual(service.unregistrations, 1)
    }

    func testLoginApprovalAndExternalChangesAreReflectedWithoutReregistering() {
        let service = FakeLoginItemService()
        service.registrationResult = .requiresApproval
        let controller = LoginItemController(service: service)
        controller.setEnabled(true)
        XCTAssertTrue(controller.isRegistered)
        XCTAssertTrue(controller.needsApproval)
        controller.setEnabled(true)
        XCTAssertEqual(service.registrations, 1)
        service.status = .enabled
        controller.refresh()
        XCTAssertFalse(controller.needsApproval)
        service.status = .notRegistered
        controller.refresh()
        XCTAssertFalse(controller.isRegistered)
        XCTAssertEqual(service.registrations, 1)
    }

    func testFailedLoginRegistrationDoesNotLeaveTheToggleEnabled() {
        let service = FakeLoginItemService()
        service.failure = NSError(domain: "LoginItemTest", code: 1)
        let controller = LoginItemController(service: service)
        controller.setEnabled(true)
        XCTAssertFalse(controller.isRegistered)
        XCTAssertNotNil(controller.errorDescription)
        service.failure = nil
        controller.setEnabled(true)
        XCTAssertTrue(controller.isRegistered)
        XCTAssertNil(controller.errorDescription)
        service.failure = NSError(domain: "LoginItemTest", code: 2)
        controller.setEnabled(false)
        XCTAssertTrue(controller.isRegistered)
        XCTAssertNotNil(controller.errorDescription)
    }

    func testLoginControllerReadsExistingRegistrationWithoutChangingIt() {
        let service = FakeLoginItemService()
        service.status = .enabled
        let controller = LoginItemController(service: service)
        XCTAssertTrue(controller.isRegistered)
        XCTAssertEqual(service.registrations, 0)
        XCTAssertEqual(service.unregistrations, 0)
    }

    func testPermanentIconHidingPreservesExistingPreferenceAndCanBeDisabled() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "hideMenuLiteIconWhenCollapsed.v2")
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.hideNimBarIcon)
        store.hideNimBarIcon = false
        XCTAssertFalse(SettingsStore(defaults: defaults).hideNimBarIcon)
    }

    func testValuesPersist() {
        let defaults = makeDefaults()
        let first = SettingsStore(defaults: defaults)
        first.autoHideEnabled = true
        first.autoHideDelay = .thirty
        let second = SettingsStore(defaults: defaults)
        XCTAssertTrue(second.autoHideEnabled)
        XCTAssertEqual(second.autoHideDelay, .thirty)
    }
    func testInvalidDelayFallsBackToFiveSeconds() {
        let defaults = makeDefaults()
        defaults.set(17, forKey: "autoHideDelay")
        XCTAssertEqual(SettingsStore(defaults: defaults).autoHideDelay, .five)
    }
    func testHiddenItemsReturnWhenExpandedButAlwaysHiddenRemainHidden() {
        let hidden: Set<String> = ["app.hidden"]
        let alwaysHidden: Set<String> = ["app.always"]

        XCTAssertEqual(MenuBarLayoutController.bundlesToHide(hidden: hidden, alwaysHidden: alwaysHidden, isCollapsed: true),
                       ["app.hidden", "app.always"])
        XCTAssertEqual(MenuBarLayoutController.bundlesToHide(hidden: hidden, alwaysHidden: alwaysHidden, isCollapsed: false),
                       ["app.always"])
    }

    func testVisibleAndAlwaysHiddenStatesRemainDistinct() {
        XCTAssertEqual(MenuBarLayoutController.bundlesToHide(hidden: [], alwaysHidden: ["app.always"], isCollapsed: false),
                       ["app.always"])
        XCTAssertTrue(MenuBarLayoutController.bundlesToHide(hidden: [], alwaysHidden: [], isCollapsed: true).isEmpty)
    }

    func testNativeDragResolvesSameOwnerAfterItsGeometricIDChanges() throws {
        let source = candidate("app.one", x: 130)
        let moved = candidate("app.one", x: 60)
        let divider = CGRect(x: 100, y: 0, width: 9, height: 24)
        let drag = try XCTUnwrap(LiveDividerDragSession(start: CGPoint(x: 140, y: 12), divider: divider,
            candidates: [source], alwaysHidden: [], ownPID: 999))
        let drops = drag.drops(at: CGPoint(x: 70, y: 12), divider: divider, candidates: [moved])
        XCTAssertNotEqual(source.id, moved.id)
        XCTAssertEqual(drops.count, 1)
        XCTAssertEqual(drops.first?.candidate.id, moved.id)
        XCTAssertEqual(drops.first?.zone, .hidden)
    }

    func testNativeDragUsesCurrentDividerAndCanMakeHiddenItemVisible() throws {
        let source = candidate("app.one", x: 60)
        let divider = CGRect(x: 100, y: 0, width: 9, height: 24)
        let drag = try XCTUnwrap(LiveDividerDragSession(start: CGPoint(x: 70, y: 12), divider: divider,
            candidates: [source], alwaysHidden: [], ownPID: 999))
        let currentDivider = CGRect(x: 80, y: 0, width: 9, height: 24)
        let drops = drag.drops(at: CGPoint(x: 95, y: 12), divider: currentDivider,
                               candidates: [candidate("app.one", x: 90)])
        XCTAssertEqual(drops.first?.zone, .visible)
    }

    func testNativeDragRejectsAmbiguousOwnersAndDesktopDrops() throws {
        let source = candidate("app.one", x: 130)
        let divider = CGRect(x: 100, y: 0, width: 9, height: 24)
        let drag = try XCTUnwrap(LiveDividerDragSession(start: CGPoint(x: 140, y: 12), divider: divider,
            candidates: [source], alwaysHidden: [], ownPID: 999))
        XCTAssertTrue(drag.drops(at: CGPoint(x: 70, y: 12), divider: divider,
            candidates: [source, candidate("app.one", x: 60)]).isEmpty)
        XCTAssertTrue(drag.drops(at: CGPoint(x: 70, y: 100), divider: divider, candidates: [source]).isEmpty)
        XCTAssertNil(LiveDividerDragSession(start: CGPoint(x: 140, y: 12), divider: divider,
            candidates: [source], alwaysHidden: ["app.one"], ownPID: 999))
    }

    func testNativeHitTestingDoesNotOverlapAdjacentIcons() throws {
        let first = candidate("app.one", x: 130)
        let next = candidate("app.two", x: 151)
        let divider = CGRect(x: 100, y: 0, width: 9, height: 24)
        let drag = try XCTUnwrap(LiveDividerDragSession(start: CGPoint(x: 149, y: 12), divider: divider,
            candidates: [first, next], alwaysHidden: [], ownPID: 999))
        XCTAssertEqual(drag.drops(at: CGPoint(x: 70, y: 12), divider: divider,
                                  candidates: [first, next]).first?.candidate.bundleIdentifier, "app.one")
    }

    func testMirroredMenuItemsOnAnotherDisplayDoNotMakeOwnerAmbiguous() throws {
        let main = candidate("app.one", x: 130)
        let external = candidate("app.one", x: 2130)
        let filtered = MenuBarAccessibility.candidates([main, external], on: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(LiveDividerDragSession.resolve(main, in: filtered)?.id, main.id)
    }

    func testDropOnAnotherDisplayCannotChangeTheSourceSection() throws {
        let source = candidate("app.one", x: 130)
        let divider = CGRect(x: 100, y: 0, width: 9, height: 24)
        let drag = try XCTUnwrap(LiveDividerDragSession(start: CGPoint(x: 140, y: 12), divider: divider,
            candidates: [source], alwaysHidden: [], ownPID: 999,
            displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080)))
        XCTAssertTrue(drag.drops(at: CGPoint(x: 2100, y: 12), divider: divider, candidates: [source]).isEmpty)
    }

    func testMovingNativeDividerReassignsOnlyItemsThatCrossIt() throws {
        let first = candidate("app.one", x: 60)
        let second = candidate("app.two", x: 130)
        let divider = CGRect(x: 100, y: 0, width: 9, height: 24)
        let drag = try XCTUnwrap(LiveDividerDragSession(start: CGPoint(x: 104, y: 12), divider: divider,
            candidates: [first, second], alwaysHidden: [], ownPID: 999))
        let drops = drag.drops(at: CGPoint(x: 160, y: 12), divider: CGRect(x: 156, y: 0, width: 9, height: 24),
                               candidates: [first, second])
        XCTAssertEqual(drops.count, 1)
        XCTAssertEqual(drops.first?.candidate.bundleIdentifier, "app.two")
        XCTAssertEqual(drops.first?.zone, .hidden)
    }

    func testLayoutIconNormalizationRemovesTransparentCanvasAndPreservesProportions() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 96, height: 96, bitsPerComponent: 8,
            bytesPerRow: 384, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 24, y: 36, width: 48, height: 24))
        let input = NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: NSSize(width: 96, height: 96))
        let normalized = try XCTUnwrap(MenuBarAccessibility.normalizedLayoutImage(input))
        XCTAssertEqual(normalized.size.width, 48, accuracy: 1)
        XCTAssertEqual(normalized.size.height, 24, accuracy: 1)
    }

    func testEffectiveColorsFollowAppKitAppearance() throws {
        let app = NSApplication.shared
        let oldAppearance = app.appearance
        defer { app.appearance = oldAppearance }
        let store = SettingsStore(defaults: makeDefaults())
        app.appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        store.updateEffectiveAppearance(app.effectiveAppearance)
        XCTAssertEqual(store.effectiveColorScheme, .light)
        app.appearance = nil
        store.updateEffectiveAppearance(try XCTUnwrap(NSAppearance(named: .darkAqua)))
        XCTAssertEqual(store.effectiveColorScheme, .dark)
        store.updateEffectiveAppearance(try XCTUnwrap(NSAppearance(named: .aqua)))
        XCTAssertEqual(store.effectiveColorScheme, .light)
    }

    func testProxyGestureKeepsItsDisplayAndRejectsStaleOrAmbiguousOwners() throws {
        let source = candidate("app.one", x: 2130)
        let bounds = CGRect(x: 2000, y: 0, width: 1920, height: 1080)
        let drag = try XCTUnwrap(LiveIconDragSession(source: source, candidates: [source], displayID: 2,
            displayBounds: bounds, menuBarBounds: CGRect(x: 2000, y: 0, width: 1920, height: 24),
            dividerX: 2100, start: CGPoint(x: 2140, y: 12), generation: 5, alwaysHidden: [], ownPID: 999))
        let drop = try XCTUnwrap(drag.drop(at: CGPoint(x: 2070, y: 12), currentDisplay: 2,
                                         generation: 5, liveCandidates: [source]))
        XCTAssertEqual(drop.0.frame, source.frame)
        XCTAssertEqual(drop.1, .hidden)
        XCTAssertNil(drag.drop(at: CGPoint(x: 2070, y: 12), currentDisplay: 1, generation: 5, liveCandidates: [source]))
        XCTAssertNil(drag.drop(at: CGPoint(x: 2070, y: 12), currentDisplay: 2, generation: 6, liveCandidates: [source]))
        XCTAssertNil(drag.drop(at: CGPoint(x: 2070, y: 12), currentDisplay: 2, generation: 5,
                              liveCandidates: [source, candidate("app.one", x: 2190)]))
        XCTAssertNil(drag.drop(at: CGPoint(x: 1070, y: 12), currentDisplay: 2, generation: 5, liveCandidates: [source]))
    }

    func testProxyCannotStartFromAnotherDisplaysCachedIcon() {
        let stale = candidate("app.one", x: 130)
        XCTAssertNil(LiveIconDragSession(source: stale, candidates: [stale], displayID: 2,
            displayBounds: CGRect(x: 2000, y: 0, width: 1920, height: 1080),
            menuBarBounds: CGRect(x: 2000, y: 0, width: 1920, height: 24), dividerX: 2100,
            start: CGPoint(x: 140, y: 12), generation: 1, alwaysHidden: [], ownPID: 999))
        XCTAssertNil(LiveIconDragSession(source: stale, candidates: [stale, candidate("app.overlap", x: 135)], displayID: 1,
            displayBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            menuBarBounds: CGRect(x: 0, y: 0, width: 1920, height: 24), dividerX: 100,
            start: CGPoint(x: 140, y: 12), generation: 1, alwaysHidden: [], ownPID: 999))
    }

    func testUnconfiguredUpdatesKeepPreferencesWithoutInventingACheck() async {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.updateMode, .manual)
        store.updateMode = .installAutomatically
        XCTAssertEqual(SettingsStore(defaults: defaults).updateMode, .installAutomatically)
        let updater = AppUpdateController(settings: store)
        await updater.performPrimaryAction()
        await updater.automaticTick()
        XCTAssertEqual(updater.state, .unconfigured)
        XCTAssertTrue(updater.requestedWithoutSource)
        XCTAssertNil(updater.lastCheckDate)
        XCTAssertNil(store.lastUpdateCheckDate)
    }

    func testAutomaticCheckHonorsDailyCadenceAndDoesNotDownload() async {
        let store = SettingsStore(defaults: makeDefaults())
        store.updateMode = .checkAutomatically
        let service = FakeUpdateService()
        let updater = AppUpdateController(settings: store, service: service, currentVersion: "0.2.0", currentBuild: 36)
        let date = Date(timeIntervalSince1970: 1_000_000)
        await updater.automaticTick(at: date)
        XCTAssertEqual(updater.primaryActionTitle, L10n.text("Scarica e installa"))
        await updater.automaticTick(at: date.addingTimeInterval(3600))
        XCTAssertEqual(service.checks, 1)
        XCTAssertEqual(service.downloads, 0)
        XCTAssertEqual(service.installs, 0)
        await updater.automaticTick(at: date.addingTimeInterval(AppUpdateController.checkInterval))
        XCTAssertEqual(service.checks, 2)
    }

    func testAutomaticDownloadWaitsUntilIdleBeforeInstalling() async {
        let store = SettingsStore(defaults: makeDefaults())
        store.updateMode = .installAutomatically
        let service = FakeUpdateService()
        var idle = false
        let updater = AppUpdateController(settings: store, service: service, currentVersion: "0.2.0", currentBuild: 36,
                                          canInstallAutomatically: { idle })
        await updater.automaticTick()
        XCTAssertEqual(service.downloads, 1)
        XCTAssertEqual(service.installs, 0)
        guard case .readyToInstall = updater.state else { return XCTFail("Update must wait for the user to stop editing") }
        idle = true
        await updater.automaticTick()
        XCTAssertEqual(service.installs, 1)
        guard case .installed = updater.state else { return XCTFail("Expected an installed update") }
    }

    func testManualUpdateNeedsExplicitDownloadAndDoesNotOfferOlderBuilds() async {
        let store = SettingsStore(defaults: makeDefaults())
        let service = FakeUpdateService()
        let updater = AppUpdateController(settings: store, service: service, currentVersion: "0.2.0", currentBuild: 36)
        await updater.automaticTick()
        XCTAssertEqual(service.checks, 0)
        await updater.performPrimaryAction()
        XCTAssertEqual(service.downloads, 0)
        await updater.performPrimaryAction()
        XCTAssertEqual(service.downloads, 1)
        XCTAssertEqual(service.installs, 1)
        XCTAssertFalse(AppUpdateRelease(version: "0.2.0", build: 35, assetURL: service.release.assetURL)
            .isNewer(than: "0.2.0", build: 36))
    }

    func testMouseFilterLatchesEntireGestureWithoutReadingKeyboardEvents() {
        var route = MenuBarMouseRouting()
        route.editing = true
        route.menuBarRegions = [CGRect(x: 100, y: 0, width: 20, height: 24)]
        XCTAssertTrue(route.shouldConsume(.leftMouseDown, point: CGPoint(x: 110, y: 12), modifiers: 3))
        // The user can release the shortcut and leave both the icon and display.
        XCTAssertTrue(route.shouldConsume(.leftMouseDragged, point: CGPoint(x: 2100, y: 900), modifiers: 0))
        XCTAssertTrue(route.shouldConsume(.leftMouseUp, point: CGPoint(x: 2100, y: 900), modifiers: 0))
        XCTAssertFalse(route.captured)
        XCTAssertFalse(route.shouldConsume(.leftMouseDragged, point: CGPoint(x: 110, y: 12), modifiers: 3))
    }

    func testMouseFilterLeavesNormalReorderingAndOtherControlsAlone() {
        var route = MenuBarMouseRouting()
        route.editing = true
        route.menuBarRegions = [CGRect(x: 100, y: 0, width: 20, height: 24)]
        XCTAssertFalse(route.shouldConsume(.leftMouseDown, point: CGPoint(x: 110, y: 12), modifiers: 1))
        XCTAssertFalse(route.shouldConsume(.leftMouseDown, point: CGPoint(x: 300, y: 12), modifiers: 3))
        XCTAssertFalse(route.shouldConsume(.rightMouseDown, point: CGPoint(x: 110, y: 12), modifiers: 3))
        XCTAssertFalse(route.shouldConsume(.keyDown, point: CGPoint(x: 110, y: 12), modifiers: 3))
        route.editing = false
        XCTAssertFalse(route.shouldConsume(.leftMouseDown, point: CGPoint(x: 110, y: 12), modifiers: 3))
        route.editing = true
        route.shortcut = 5
        XCTAssertTrue(route.shouldConsume(.leftMouseDown, point: CGPoint(x: 110, y: 12), modifiers: 5))
    }

    func testDividerSlidesOneIconSlotAndReversesAtTheNewBoundary() throws {
        let source = candidate("app.one", x: 300)
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        var drag = try XCTUnwrap(LiveIconDragSession(source: source, candidates: [source], displayID: 1,
            displayBounds: bounds, menuBarBounds: CGRect(x: 0, y: 0, width: 1000, height: 24),
            dividerX: 200, start: CGPoint(x: 310, y: 12), generation: 1,
            alwaysHidden: [], ownPID: 999, minimumDividerX: 5, maximumDividerX: 700))
        XCTAssertEqual(drag.shiftDivider(by: source.frame.width), source.frame.width, accuracy: 0.01)
        XCTAssertEqual(drag.dividerX, 220, accuracy: 0.01)
        XCTAssertEqual(drag.preview(at: CGPoint(x: 210, y: 12)), .hidden)
        XCTAssertEqual(drag.shiftDivider(by: -source.frame.width), -source.frame.width, accuracy: 0.01)
        XCTAssertEqual(drag.dividerX, 200, accuracy: 0.01)
        XCTAssertEqual(drag.preview(at: CGPoint(x: 210, y: 12)), .visible)
        XCTAssertEqual(drag.shiftDivider(by: source.frame.width * 30), 500, accuracy: 0.01)
        XCTAssertEqual(drag.dividerX, 700, accuracy: 0.01)
    }

    func testImmediateCrossingReversesWithoutWaitingForMouseUpAndKeepsOffBarState() {
        var crossing = LiveCrossingState(initialSide: .visible)
        XCTAssertNil(crossing.cross(to: .visible))
        XCTAssertEqual(crossing.cross(to: .hidden), .hidden)
        XCTAssertNil(crossing.cross(to: .hidden))
        XCTAssertNil(crossing.cross(to: nil))
        XCTAssertEqual(crossing.side, .hidden)
        XCTAssertEqual(crossing.cross(to: .visible), .visible)
        XCTAssertEqual(crossing.cross(to: .hidden), .hidden)
        XCTAssertEqual(crossing.side, .hidden)
    }

    func testBlankClickCanRecoverOnlyNimBarEvenWithNoManagedHiddenApps() {
        XCTAssertTrue(MenuBarRevealPolicy.shouldReveal(isCollapsed: true, hasHiddenItems: false, ownIconHidden: true))
        XCTAssertTrue(MenuBarRevealPolicy.shouldReveal(isCollapsed: true, hasHiddenItems: true, ownIconHidden: false))
        XCTAssertFalse(MenuBarRevealPolicy.shouldReveal(isCollapsed: false, hasHiddenItems: true, ownIconHidden: false))
        XCTAssertFalse(MenuBarRevealPolicy.shouldReveal(isCollapsed: true, hasHiddenItems: false, ownIconHidden: false))
    }

    func testLanguageStartsEnglishAndSelectionPersistsWithImmediateMessages() {
        let previous = L10n.language
        defer { L10n.language = previous }
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.language, .english)
        XCTAssertFalse(store.hasLanguageSelection)
        let message = LocalizedMessage("Trovate %@ icone nella barra macOS.", [.number(12)])
        XCTAssertEqual(message.text, "Found 12 icons in the macOS menu bar.")
        var callbacks = 0
        store.onLanguageChanged = { callbacks += 1 }
        store.language = .italian
        XCTAssertEqual(callbacks, 1)
        XCTAssertEqual(message.text, "Trovate 12 icone nella barra macOS.")
        XCTAssertEqual(SettingsStore(defaults: defaults).language, .italian)
        XCTAssertTrue(store.hasLanguageSelection)
        store.language = .english
        XCTAssertEqual(message.text, "Found 12 icons in the macOS menu bar.")
    }

    func testContinueSavesDefaultEnglishWithoutRequiringPickerChange() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.hasLanguageSelection)
        store.confirmLanguageChoice()
        XCTAssertTrue(SettingsStore(defaults: defaults).hasLanguageSelection)
        XCTAssertEqual(store.language, .english)
    }

    func testBothLanguageTablesContainSameKeysAndCompatiblePlaceholders() throws {
        let englishURL = try XCTUnwrap(L10n.bundle(for: .english).url(forResource: "Localizable", withExtension: "strings"))
        let italianURL = try XCTUnwrap(L10n.bundle(for: .italian).url(forResource: "Localizable", withExtension: "strings"))
        func table(_ url: URL) throws -> [String: String] {
            try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
        }
        let english = try table(englishURL), italian = try table(italianURL)
        XCTAssertGreaterThan(english.count, 130)
        XCTAssertEqual(Set(english.keys), Set(italian.keys))
        for (key, value) in english {
            XCTAssertEqual(value.components(separatedBy: "%@").count,
                           italian[key]?.components(separatedBy: "%@").count, key)
            XCTAssertFalse(value.isEmpty, key)
        }
        XCTAssertEqual(L10n.text("Benvenuti in NimBar", language: .english), "Welcome to NimBar")
        XCTAssertEqual(L10n.text("Icona originale", language: .english), "Original icon")
        let error = NSError(domain: "NimBar.MenuBarNativeHider", code: 2)
        XCTAssertEqual(L10n.errorDescription(error, language: .english), "The macOS request timed out; icons were restored.")
        XCTAssertEqual(L10n.errorDescription(error, language: .italian), "La richiesta macOS è scaduta; le icone sono state ripristinate.")
    }

    func testReflowPreservesOrderAndReversesWithoutTouchingSystemItems() throws {
        let left = candidate("app.left", x: 100)
        let near = candidate("app.near", x: 130)
        let source = candidate("app.source", x: 160)
        let right = candidate("app.right", x: 190)
        let system = candidate("com.apple.controlcenter", x: 220)
        let foreignDisplay = candidate("app.otherDisplay", x: 1200)
        let plan = LiveMenuBarReflowPlan(source: source,
            neighbours: [left, near, source, right, system, foreignDisplay],
            bounds: CGRect(x: 80, y: 0, width: 160, height: 24))
        let hidden = plan.frames(displacement: 20)
        XCTAssertEqual(hidden[left.id]?.minX, 120)
        XCTAssertEqual(hidden[near.id]?.minX, 150)
        XCTAssertEqual(hidden[right.id], right.frame)
        XCTAssertNil(hidden[source.id])
        XCTAssertNil(hidden[system.id])
        XCTAssertNil(hidden[foreignDisplay.id])
        let restored = plan.frames(displacement: 0)
        XCTAssertEqual(restored[left.id], left.frame)
        XCTAssertEqual(restored[near.id], near.frame)
        let shown = plan.frames(displacement: -20)
        XCTAssertEqual(shown[left.id]?.minX, 80)
        XCTAssertEqual(shown[near.id]?.minX, 110)
        XCTAssertEqual(plan.frames(displacement: -500), shown)
    }

    func testBackdropClearsOnlyIconSlotsAndRefusesUnsafeEdges() throws {
        let region = CGRect(x: 100, y: 0, width: 20, height: 12)
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 40, height: 24, bitsPerComponent: 8,
            bytesPerRow: 160, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 24))
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(CGRect(x: 12, y: 6, width: 8, height: 12))
        let image = try XCTUnwrap(ctx.makeImage())
        let cleared = try XCTUnwrap(LiveMenuBarBackdrop.clearingSlots(in: image, region: region,
            slots: [CGRect(x: 106, y: 0, width: 4, height: 12)]))
        ctx.draw(cleared, in: CGRect(x: 0, y: 0, width: 40, height: 24))
        let pixels = try XCTUnwrap(ctx.data).assumingMemoryBound(to: UInt8.self)
        XCTAssertTrue((0..<(40 * 24 * 4)).allSatisfy { pixels[$0] == 255 })
        XCTAssertNil(LiveMenuBarBackdrop.clearingSlots(in: image, region: region,
            slots: [CGRect(x: 99, y: 0, width: 5, height: 12)]))
        XCTAssertNil(LiveMenuBarBackdrop.clearingSlots(in: image, region: region,
            slots: [CGRect(x: 117, y: 0, width: 8, height: 12)]))
    }

    func testReflowLayersShareMotionAndKeepSourceHiddenUntilHandoff() throws {
        let source = candidate("app.source", x: 160)
        let left = candidate("app.left", x: 120)
        let image = NSImage(size: CGSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.systemBlue.setFill(); rect.fill(); return true
        }
        let bitmap = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let region = CGRect(x: 100, y: 0, width: 100, height: 24)
        let surface = LiveMenuBarReflowSurface(region: region, candidates: [source, left],
            images: [source.id: image, left.id: image], screenshot: bitmap, scale: 2, signature: "fixture")
        let view = LiveMenuBarReflowView(surface: surface, background: bitmap, source: source,
            sprites: [source, left])
        let layers = try XCTUnwrap(view.layer?.sublayers)
        XCTAssertEqual(layers.count, 3)
        XCTAssertTrue(layers[1].isHidden)
        let start = CACurrentMediaTime()
        view.moveNeighbours(displacement: 20, start: start)
        XCTAssertEqual(layers[2].position.x, 50)
        XCTAssertEqual(layers[2].bounds.width, 16)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let motion = try XCTUnwrap(layers[2].animation(forKey: "menu-bar-motion") as? CASpringAnimation)
            XCTAssertEqual(motion.duration, LiveMenuBarMotion.duration)
            XCTAssertEqual(motion.beginTime, layers[2].convertTime(start, from: nil), accuracy: 0.001)
        }
        view.moveNeighbours(displacement: 0, start: start + 0.1)
        XCTAssertEqual(layers[2].position.x, 30)
        view.settle(to: [source, left], start: start + 0.2)
        XCTAssertFalse(layers[1].isHidden)
    }

    private func candidate(_ bundle: String, x: Double) -> MenuBarCandidate {
        MenuBarCandidate(id: "\(bundle):\(x)", bundleIdentifier: bundle, applicationName: bundle,
            label: bundle, identifier: "status", processIdentifier: 123, index: 0,
            x: x, y: 0, width: 20, height: 24)
    }
    private func makeDefaults() -> UserDefaults {
        let suite = "NimBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

@MainActor
private final class FakeUpdateService: AppUpdateService {
    var checks = 0
    var downloads = 0
    var installs = 0
    let release = AppUpdateRelease(version: "0.2.1", build: 37, assetURL: URL(string: "https://example.invalid/NimBar.zip")!)
    func latestRelease() async throws -> AppUpdateRelease? { checks += 1; return release }
    func download(_ release: AppUpdateRelease) async throws -> URL {
        downloads += 1
        return URL(fileURLWithPath: "/private/tmp/NimBar-update-test.zip")
    }
    func install(_ release: AppUpdateRelease, downloadedFile: URL) async throws { installs += 1 }
}


@MainActor
private final class FakeLoginItemService: LoginItemServicing {
    var status: SMAppService.Status = .notRegistered
    var registrationResult: SMAppService.Status = .enabled
    var registrations = 0
    var unregistrations = 0
    var failure: Error?
    func register() throws {
        registrations += 1
        if let failure { throw failure }
        status = registrationResult
    }
    func unregister() throws {
        unregistrations += 1
        if let failure { throw failure }
        status = .notRegistered
    }
}

/// Serves a fixed release feed locally; no test request reaches GitHub.
private final class ReleaseFixtureURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let tags: [(String, Bool)] = [
            ("v0.2.1", false), ("v0.3.0-beta.49", true), ("v0.4.0.2-alpha.48", true),
            ("v9.0.0.1-beta.90", true), ("v9.0.0-alpha.90", true), ("v9.0.0.1-alpha.90", false)
        ]
        let feed = tags.map { tag, prerelease in
            ["tag_name": tag, "html_url": "https://github.com/emanuele0409/NimBar/releases/tag/\(tag)",
             "draft": false, "prerelease": prerelease] as [String: Any]
        }
        let data = try! JSONSerialization.data(withJSONObject: feed)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
