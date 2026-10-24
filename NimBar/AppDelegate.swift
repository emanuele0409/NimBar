// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI
import CoreGraphics
import Combine
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var updateMenuItem: NSMenuItem?
    private var isMenuTracking = false
    private var autoHideTimer: Timer?
    private var autoHideRemaining: TimeInterval = 0
    private var autoHideLastTick = Date()
    private var permissionPollTimer: Timer?
    private var dividerModifierTimer: Timer?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalRightMouseMonitor: Any?
    private var localRightMouseMonitor: Any?
    private var globalScrollMonitor: Any?
    private var localScrollMonitor: Any?
    private var swipeRecognizer = MenuBarSwipeRecognizer()
    private var dividerModifiersActive = false
    private var liveEditor: LiveMenuBarEditor?
    private var blankClickGeneration = 0
    private var isWaitingForPermissionGrant = false
    private let settings = SettingsStore()
    private let accessibility = MenuBarAccessibility()
    private let dividerAccessibility = MenuBarAccessibility()
    private let layout = MenuBarLayoutController()
    private lazy var updater = AppUpdateController(
        settings: settings,
        service: GitHubReleaseService(),
        canInstallAutomatically: { [weak self] in
            guard let self else { return false }
            return self.settingsWindow?.isVisible != true && !self.dividerModifiersActive
                && self.liveEditor?.isBusy != true && !self.isMenuTracking && !self.settings.showPermissionSetup
        }
    )
    private var settingsWindow: NSWindow?
    private var appearanceObservation: NSKeyValueObservation?
    private var safeMode = false
    private let loginItem = LoginItemController()
    private var welcomePanel: NSPanel?
    private var welcomeObservation: AnyCancellable?
    private var statusVisibilityRetry: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The XCTest host is the app executable. Keep unit-test launches from
        // creating status items, showing windows, or applying saved visibility.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }
        safeMode = ProcessInfo.processInfo.arguments.contains("--safe-mode")
        NSApp.setActivationPolicy(.accessory)
        layout.initializeHiddenSection()
        installBlankMenuBarClickMonitors()
        settings.onSwipePreferencesChanged = { [weak self] in self?.configureSwipeMonitors() }
        configureSwipeMonitors()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "NimBar.Main"
        item.button?.toolTip = L10n.text("NimBar — gestione della barra dei menu")
        let menu = NSMenu()
        menu.addItem(withTitle: L10n.text("Mostra tutte le icone gestite"), action: #selector(showManagedItems), keyEquivalent: "")
        menu.addItem(withTitle: L10n.text("Apri/chiudi sezione Nascoste"), action: #selector(recoverLayout), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.text("Impostazioni…"), action: #selector(showSettings), keyEquivalent: ",")
        let updateItem = menu.addItem(withTitle: updater.primaryActionTitle, action: #selector(checkForUpdates), keyEquivalent: "")
        updateMenuItem = updateItem
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.text("Esci da NimBar"), action: #selector(quit), keyEquivalent: "q")
        for menuItem in menu.items { menuItem.target = self }
        statusMenu = menu
        menu.delegate = self
        updater.onStateChanged = { [weak self] in self?.updateUpdateMenuItem() }
        settings.onUpdateModeChanged = { [weak self] in self?.updater.preferencesDidChange() }
        updater.start()
        item.menu = nil
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        installInteractiveDivider()
        settings.onMenuBarIconStyleChanged = { [weak self] in self?.updateStatusItemImage() }
        settings.onLanguageChanged = { [weak self] in self?.refreshLocalizedInterface() }
        settings.onAppearanceModeChanged = { [weak self] in self?.applyAppearanceMode() }
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.updateResolvedAppearance() }
        }
        settings.onMenuBarVisibilityChanged = { [weak self] in
            self?.updateStatusItemVisibility()
        }
        layout.onCollapsedChanged = { [weak self] collapsed in
            guard let self else { return }
            self.updateStatusItemVisibility()
            if collapsed {
                self.autoHideTimer?.invalidate()
                self.autoHideTimer = nil
            } else {
                self.scheduleAutoHide()
            }
        }
        layout.onVisibilityApplied = { [weak self] in self?.updateStatusItemVisibility() }
        applyAppearanceMode()
        updateStatusItemImage()
        updateStatusItemVisibility()
        accessibility.refreshPermissionStatus()
        if accessibility.isTrusted { liveEditor?.prepareInput() }
        // Show the welcome/permissions screen once for each app version.
        let version = AppVersion.version
        let permissionSetupKey = "didShowNimBarWelcome.\(version)"
        let shouldShowPermissionSetup = !UserDefaults.standard.bool(forKey: permissionSetupKey) || !settings.hasLanguageSelection
        UserDefaults.standard.set(true, forKey: permissionSetupKey)
        settings.showPermissionSetup = false
        let launchedAtLogin = NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if shouldShowPermissionSetup || !launchedAtLogin { openSettings() }
        welcomeObservation = settings.$showPermissionSetup.removeDuplicates().sink { [weak self] show in
            self?.setWelcomeVisible(show)
        }
        // Attach the welcome panel after the main window is on screen.
        if shouldShowPermissionSetup {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.settings.showPermissionSetup = true
            }
        }
        if permissionsReady {
            // Let the previous process's native assertion disappear before
            // caching real symbols and restoring this version's assignments.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, self.permissionsReady else { return }
                self.accessibility.refresh(afterCapture: { [weak self] in
                    self?.layout.resumeSavedAssignments()
                })
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        loginItem.refresh()
        let previouslyHadScreenCaptureAccess = accessibility.hasScreenCaptureAccess
        accessibility.refreshPermissionsAfterReturningToApp()
        if !previouslyHadScreenCaptureAccess && accessibility.hasScreenCaptureAccess {
            accessibility.refresh(afterCapture: { [weak self] in
                self?.layout.resumeSavedAssignments()
            })
        }
        if permissionsReady && isWaitingForPermissionGrant { permissionStatusDidChange() }
    }

    private func refreshLocalizedInterface() {
        statusItem?.button?.toolTip = L10n.text("NimBar — gestione della barra dei menu")
        settingsWindow?.title = L10n.text("NimBar — Impostazioni")
        for item in statusMenu?.items ?? [] {
            switch item.action {
            case #selector(showManagedItems): item.title = L10n.text("Mostra tutte le icone gestite")
            case #selector(recoverLayout): item.title = L10n.text("Apri/chiudi sezione Nascoste")
            case #selector(showSettings): item.title = L10n.text("Impostazioni…")
            case #selector(quit): item.title = L10n.text("Esci da NimBar")
            default: break
            }
        }
        updateUpdateMenuItem()
    }

    @objc private func statusItemClicked() {
        guard permissionsReady else { openSettings(); return }
        guard let button = statusItem?.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusMenu?.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
            return
        }
        autoHideTimer?.invalidate()
        layout.toggleHiddenSection()
        if !layout.isCollapsed { scheduleAutoHide() }
    }

    private func installBlankMenuBarClickMonitors() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            let location = NSEvent.mouseLocation
            Task { @MainActor [weak self] in self?.revealHiddenItemsIfBlankMenuBarClick(at: location) }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            let location = NSEvent.mouseLocation
            Task { @MainActor [weak self] in self?.revealHiddenItemsIfBlankMenuBarClick(at: location) }
            return event
        }
        globalRightMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] _ in
            let location = NSEvent.mouseLocation
            Task { @MainActor [weak self] in self?.showMenuForBlankMenuBarRightClick(at: location) }
        }
        localRightMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            let location = NSEvent.mouseLocation
            Task { @MainActor [weak self] in self?.showMenuForBlankMenuBarRightClick(at: location) }
            return event
        }
    }

    private func configureSwipeMonitors() {
        for monitor in [globalScrollMonitor, localScrollMonitor] {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        globalScrollMonitor = nil
        localScrollMonitor = nil
        swipeRecognizer.reset()
        blankClickGeneration += 1
        guard settings.menuBarSwipeEnabled, !safeMode else { return }
        globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let sample = MenuBarSwipeSample(event: event, location: NSEvent.mouseLocation)
            Task { @MainActor [weak self] in self?.handleMenuBarSwipe(sample) }
        }
        localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let sample = MenuBarSwipeSample(event: event, location: NSEvent.mouseLocation)
            Task { @MainActor [weak self] in self?.handleMenuBarSwipe(sample) }
            return event
        }
    }

    private func handleMenuBarSwipe(_ sample: MenuBarSwipeSample) {
        guard settings.menuBarSwipeEnabled, permissionsReady, !settings.showPermissionSetup,
              !dividerModifiersActive, !settings.isCapturingHotKey,
              liveEditor?.isBusy != true, !isMenuTracking else {
            swipeRecognizer.reset()
            blankClickGeneration += 1
            return
        }
        let screen = NSScreen.screens.first { $0.frame.contains(sample.location) }
        let displayNumber = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let overMenuBar = screen.flatMap { menuBarRect(on: $0) }?.contains(sample.location) == true
        guard let intent = swipeRecognizer.consume(sample, displayID: displayNumber?.uint32Value,
                                                    isOverMenuBar: overMenuBar) else { return }
        let shouldShow = intent.direction == settings.showSwipeDirection
        guard shouldShow == layout.isCollapsed else { return }
        blankClickGeneration += 1
        let token = blankClickGeneration
        dividerAccessibility.selectDisplay(CGDirectDisplayID(intent.displayID))
        // Scan once per recognized stroke, never once per scroll packet. Only
        // validate its original point before visibility changes move real items.
        dividerAccessibility.refresh { [weak self] in
            guard let self, token == self.blankClickGeneration,
                  self.settings.menuBarSwipeEnabled, self.permissionsReady,
                  !self.settings.showPermissionSetup, !self.dividerModifiersActive,
                  self.liveEditor?.isBusy != true, !self.isMenuTracking,
                  self.dividerAccessibility.displayID == intent.displayID,
                  ProcessInfo.processInfo.systemUptime - sample.timestamp < 1.5,
                  let sourceScreen = NSScreen.screens.first(where: {
                      ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == intent.displayID
                  }),
                  self.menuBarRect(on: sourceScreen)?.contains(NSEvent.mouseLocation) == true,
                  self.canInteractWithEmptyMenuBarSpace(at: intent.origin) else { return }
            if shouldShow {
                if self.layout.isCollapsed { self.showManagedItems() }
            } else if !self.layout.isCollapsed {
                self.layout.toggleHiddenSection()
            }
        }
    }

    private func revealHiddenItemsIfBlankMenuBarClick(at location: NSPoint) {
        let ownIconHidden = !settings.hideNimBarIcon && statusItem?.isVisible != true
        guard !dividerModifiersActive, liveEditor?.isBusy != true,
              permissionsReady, MenuBarRevealPolicy.shouldReveal(isCollapsed: layout.isCollapsed,
                hasHiddenItems: layout.hasHiddenItems, ownIconHidden: ownIconHidden) else { return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }),
              let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return }
        let displayID = CGDirectDisplayID(displayNumber.uint32Value)
        guard menuBarRect(on: screen)?.contains(location) == true else { return }
        blankClickGeneration += 1
        let token = blankClickGeneration
        dividerAccessibility.selectDisplay(displayID)
        // One fresh scan per click, including an empty result. Never recurse.
        dividerAccessibility.refresh { [weak self] in
            guard let self, token == self.blankClickGeneration, !self.dividerModifiersActive,
                  self.liveEditor?.isBusy != true, self.dividerAccessibility.displayID == displayID,
                  self.canInteractWithEmptyMenuBarSpace(at: location) else { return }
            self.showManagedItems()
        }
    }

    private func showMenuForBlankMenuBarRightClick(at location: NSPoint) {
        guard !dividerModifiersActive, liveEditor?.isBusy != true, let statusMenu,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }),
              menuBarRect(on: screen)?.contains(location) == true,
              let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return }
        let displayID = CGDirectDisplayID(displayNumber.uint32Value)
        blankClickGeneration += 1
        let token = blankClickGeneration
        dividerAccessibility.selectDisplay(displayID)
        dividerAccessibility.refresh { [weak self] in
            guard let self, token == self.blankClickGeneration,
                  !self.dividerModifiersActive, self.liveEditor?.isBusy != true,
                  self.dividerAccessibility.displayID == displayID,
                  self.canInteractWithEmptyMenuBarSpace(at: location) else { return }
            statusMenu.popUp(positioning: nil, at: location, in: nil)
        }
    }

    private func canInteractWithEmptyMenuBarSpace(at location: NSPoint) -> Bool {
        guard isBlankMenuBarLocation(location),
              let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }),
              let point = accessibilityPoint(for: location, on: screen) else { return false }

        switch MenuBarAccessibility.menuBarHitTest(at: point) {
        case .empty:
            return true
        case .unavailable:
            // A failed or incomplete hit test must never steal a system item's click.
            return false
        case .item(let processIdentifier):
            // macOS may still expose the old accessibility target of a managed
            // item after NimBar hides it. Only that exact hidden footprint is
            // allowed to open NimBar's menu.
            return dividerAccessibility.liveItems.contains { candidate in
                !candidate.isSystemOwned
                    && candidate.processIdentifier == processIdentifier
                    && (layout.isAlwaysHidden(candidate)
                        || (layout.isCollapsed && layout.hiddenBundleIDs.contains(candidate.bundleIdentifier)))
                    && candidate.frame.insetBy(dx: -3, dy: -3).contains(point)
            }
        }
    }

    private func isBlankMenuBarLocation(_ location: NSPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) else { return false }
        guard let menuBarRect = menuBarRect(on: screen) else { return false }
        guard menuBarRect.contains(location) else { return false }

        if statusItem?.isVisible == true, let button = statusItem?.button,
           let window = button.window,
           window.convertToScreen(button.convert(button.bounds, to: nil)).contains(location) {
            return false
        }
        guard let pointInAccessibilitySpace = accessibilityPoint(for: location, on: screen) else { return false }
        let isCurrentlyHidden: (MenuBarCandidate) -> Bool = { [layout] candidate in
            layout.isAlwaysHidden(candidate)
                || (layout.isCollapsed && layout.hiddenBundleIDs.contains(candidate.bundleIdentifier))
        }
        // Visible items win over stale footprints of hidden icons. In
        // particular, the clock must remain a native Notification Center target.
        if dividerAccessibility.liveItems.contains(where: { candidate in
            (candidate.isSystemOwned || !isCurrentlyHidden(candidate))
                && candidate.frame.insetBy(dx: -3, dy: -3).contains(pointInAccessibilitySpace)
        }) { return false }

        if let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           MenuBarAccessibility.applicationMenuBarFrames(processIdentifier: frontmostPID)
            .contains(where: { $0.insetBy(dx: -2, dy: -2).contains(pointInAccessibilitySpace) }) { return false }
        return true
    }

    private func accessibilityPoint(for location: NSPoint, on screen: NSScreen) -> CGPoint? {
        guard let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        let displayBounds = CGDisplayBounds(CGDirectDisplayID(displayNumber.uint32Value))
        return CGPoint(
            x: displayBounds.minX + location.x - screen.frame.minX,
            y: displayBounds.minY + screen.frame.maxY - location.y
        )
    }

    private func updateStatusItemImage() {
        guard let button = statusItem?.button else { return }
        let style = settings.menuBarIconStyle
        let image: NSImage?
        switch style {
        case .original:
            image = NSImage(named: "NimBarMenuBarMark")
            image?.size = NSSize(width: 16, height: 16)
            image?.isTemplate = true
        case .chevron:
            image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "NimBar")
            image?.size = NSSize(width: 12, height: 14)
            image?.isTemplate = true
        case .chevronDown:
            image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "NimBar")
            image?.size = NSSize(width: 12, height: 14)
            image?.isTemplate = true
        case .dot:
            image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "NimBar")
            image?.size = NSSize(width: 5, height: 5)
            image?.isTemplate = true
        }
        button.image = image
        button.imageScaling = .scaleProportionallyDown
    }

    /// `visibleFrame` already accounts for the current display configuration:
    /// built-in panels with a camera housing, ordinary MacBook displays, and
    /// external monitors can report different menu-bar heights.
    private func menuBarRect(on screen: NSScreen) -> CGRect? {
        // AppKit's visibleFrame excludes the currently occupied menu-bar area
        // and updates when display geometry or menu-bar settings change.
        let visibleHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let height = visibleHeight > 0 ? visibleHeight : max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)
        guard height > 0, height <= screen.frame.height / 4 else { return nil }
        return CGRect(x: screen.frame.minX, y: screen.frame.maxY - height,
                      width: screen.frame.width, height: height)
    }

    private func updateStatusItemVisibility() {
        statusVisibilityRetry?.cancel()
        let shouldBeVisible = !settings.hideNimBarIcon
        if statusItem?.isVisible != shouldBeVisible { statusItem?.isVisible = shouldBeVisible }
        guard shouldBeVisible else { return }
        let retry = DispatchWorkItem { [weak self] in
            guard let self, !self.settings.hideNimBarIcon, self.statusItem?.isVisible == false else { return }
            self.statusItem?.isVisible = true
        }
        statusVisibilityRetry = retry
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: retry)
    }

    private func applyAppearanceMode() {
        switch settings.appearanceMode {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        settingsWindow?.appearance = nil
        settingsWindow?.contentView?.appearance = nil
        updateResolvedAppearance()
    }

    private func updateResolvedAppearance() {
        settings.updateEffectiveAppearance(NSApp.effectiveAppearance)
        settingsWindow?.backgroundColor = .clear
        updateStatusItemImage()
    }

    @objc private func showManagedItems() {
        guard permissionsReady else { openSettings(); return }
        layout.showAllManagedItems(using: accessibility)
        updateStatusItemVisibility()
        if !layout.isCollapsed { scheduleAutoHide() }
    }
    @objc private func recoverLayout() {
        guard permissionsReady else { openSettings(); return }
        layout.toggleHiddenSection()
    }
    @objc private func showSettings() { openSettings() }
    @objc private func checkForUpdates() {
        if !updater.isConfigured { openSettings(section: .updates) }
        Task { await updater.performPrimaryAction() }
    }

    private func updateUpdateMenuItem() {
        updateMenuItem?.title = updater.primaryActionTitle
        updateMenuItem?.isEnabled = updater.canPerformPrimaryAction
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuTracking = true
        updateUpdateMenuItem()
    }

    func menuDidClose(_ menu: NSMenu) { isMenuTracking = false }
    @objc private func quit() {
        autoHideTimer?.invalidate()
        if layout.isCollapsed { layout.toggleHiddenSection() }
        NSApp.terminate(nil)
    }

    private func scheduleAutoHide() {
        autoHideTimer?.invalidate()
        guard settings.autoHideEnabled, settings.autoHideDelay != .never else { return }
        autoHideRemaining = TimeInterval(settings.autoHideDelay.rawValue)
        autoHideLastTick = Date()
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard !self.layout.isCollapsed else {
                    self.autoHideTimer?.invalidate()
                    self.autoHideTimer = nil
                    return
                }
                let now = Date()
                let elapsed = now.timeIntervalSince(self.autoHideLastTick)
                self.autoHideLastTick = now
                guard !self.isPointerOverMenuBar(), !self.dividerModifiersActive, !self.isMenuTracking,
                      self.liveEditor?.isBusy != true else { return }
                self.autoHideRemaining -= elapsed
                guard self.autoHideRemaining <= 0 else { return }
                self.autoHideTimer?.invalidate()
                self.autoHideTimer = nil
                self.layout.toggleHiddenSection()
            }
        }
    }

    private func isPointerOverMenuBar() -> Bool {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.contains { screen in
            menuBarRect(on: screen)?.contains(pointer) == true
        }
    }

    private func openSettings(section: SettingsStore.SettingsSection? = nil) {
        autoHideTimer?.invalidate()
        if let section { settings.selectedSettingsSection = section }
        if let window = settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView(
            store: settings,
            safeMode: safeMode,
            accessibility: accessibility,
            layout: layout,
            updater: updater,
            loginItem: loginItem,
            quit: { [weak self] in self?.quit() }
        ))
        let window = NSWindow(contentViewController: hosting)
        window.title = L10n.text("NimBar — Impostazioni")
        window.setContentSize(NSSize(width: 960, height: 680))
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        window.center()
        window.isReleasedWhenClosed = false
        settingsWindow = window
        window.delegate = self
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func setWelcomeVisible(_ visible: Bool) {
        if !visible {
            permissionPollTimer?.invalidate()
            permissionPollTimer = nil
            isWaitingForPermissionGrant = false
            if let panel = welcomePanel {
                settingsWindow?.removeChildWindow(panel)
                panel.orderOut(nil)
                welcomePanel = nil
            }
            return
        }
        guard welcomePanel == nil else { return }
        openSettings()
        guard let parent = settingsWindow else { return }
        let hosting = NSHostingView(rootView: PermissionGateView(store: settings, accessibility: accessibility) { [weak self] in
            self?.settings.confirmLanguageChoice()
            self?.settings.showPermissionSetup = false
        })
        let size = hosting.fittingSize
        let panel = WelcomePanel(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 24
        hosting.layer?.masksToBounds = true
        welcomePanel = panel
        panel.setFrameOrigin(NSPoint(x: parent.frame.midX - size.width / 2,
                                     y: parent.frame.midY - size.height / 2))
        parent.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        if !permissionsReady { startPermissionStatusMonitor() }
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === settingsWindow {
            settings.showPermissionSetup = false
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        autoHideTimer?.invalidate()
        permissionPollTimer?.invalidate()
        dividerModifierTimer?.invalidate()
        statusVisibilityRetry?.cancel()
        welcomeObservation?.cancel()
        for monitor in [globalMouseMonitor, localMouseMonitor, globalRightMouseMonitor, localRightMouseMonitor,
                        globalScrollMonitor, localScrollMonitor] {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }

    private func startPermissionStatusMonitor() {
        permissionPollTimer?.invalidate()
        isWaitingForPermissionGrant = true
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.settings.showPermissionSetup else {
                    self.permissionPollTimer?.invalidate()
                    self.permissionPollTimer = nil
                    self.isWaitingForPermissionGrant = false
                    return
                }
                self.accessibility.refreshPermissionStatus()
                if self.accessibility.isTrusted { self.liveEditor?.prepareInput() }
                if self.permissionsReady { self.permissionStatusDidChange() }
            }
        }
    }

    private func permissionStatusDidChange() {
        guard permissionsReady, isWaitingForPermissionGrant else { return }
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
        isWaitingForPermissionGrant = false
        layout.resumeSavedAssignments()
        accessibility.refresh()
    }

    private var permissionsReady: Bool {
        accessibility.requiredPermissionsGranted
    }

    private func installInteractiveDivider() {
        liveEditor = LiveMenuBarEditor(access: dividerAccessibility, layout: layout,
            onBegin: { [weak self] in self?.autoHideTimer?.invalidate() },
            onEnd: { [weak self] in
                guard let self else { return }
                if !self.layout.isCollapsed { self.scheduleAutoHide() }
            },
            onCommit: { [weak self] in self?.accessibility.refresh() })
        liveEditor?.onInputAvailabilityChanged = { [weak self] available in
            self?.settings.liveEditorAccessUnavailable = !available
            self?.accessibility.setLiveEditorAvailability(available)
        }
        liveEditor?.onBlankMouseDown = { [weak self] point in
            guard let self else { return }
            var display: CGDirectDisplayID = 0
            var count: UInt32 = 0
            guard CGGetDisplaysWithPoint(point, 1, &display, &count) == .success, count == 1,
                  let screen = NSScreen.screens.first(where: {
                      ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display
                  }) else { return }
            let bounds = CGDisplayBounds(display)
            self.revealHiddenItemsIfBlankMenuBarClick(at: CGPoint(x: screen.frame.minX + point.x - bounds.minX,
                y: screen.frame.maxY - point.y + bounds.minY))
        }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshInteractiveDivider() }
        }
        RunLoop.main.add(timer, forMode: .common)
        dividerModifierTimer = timer
    }

    private func refreshInteractiveDivider() {
        let modifierMask = currentModifierMask()
        let shouldShow = permissionsReady && !settings.isCapturingHotKey && settings.hotKeyModifiers != 0
            && modifierMask == settings.hotKeyModifiers
        dividerModifiersActive = shouldShow
        let pointer = liveEditor?.isBusy == true ? nil : CGEvent(source: nil)?.location
        liveEditor?.update(isActive: shouldShow, pointer: pointer, shortcut: settings.hotKeyModifiers)
    }

    private func currentModifierMask() -> Int {
        let flags = NSEvent.modifierFlags
        return (flags.contains(.command) ? 1 : 0) | (flags.contains(.option) ? 2 : 0)
            | (flags.contains(.control) ? 4 : 0) | (flags.contains(.shift) ? 8 : 0)
    }
}

enum MenuBarRevealPolicy {
    static func shouldReveal(isCollapsed: Bool, hasHiddenItems: Bool, ownIconHidden: Bool) -> Bool {
        ownIconHidden || (isCollapsed && hasHiddenItems)
    }
}


private final class WelcomePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
