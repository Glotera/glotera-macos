import Cocoa
import Carbon

/// Manager for chat translation feature that monitors IM applications and shows floating windows
class ChatTranslationManager: NSObject {
    static let shared = ChatTranslationManager()
    
    private var chatTranslationWindow: ChatTranslationWindow?
    private var isEnabled: Bool = true
    private var currentActiveApp: AppInfo?
    private var appMonitoringTimer: Timer?
    private var lastActiveAppBundleId: String?
    private var windowPositionTimer: Timer?
    private var lastWindowFrame: NSRect?
    
    // Grammarly-style UX: hidden by default
    private var isTranslationWindowVisible: Bool = false
    private var isUserRequestedWindow: Bool = false // User control: whether user clicked logo bar
    private let logoBarManager = GloteraLogoBarManager.shared
    
    // Auto-reactivation and tolerance period for better UX
    private var previousActiveApp: NSRunningApplication?
    private var toleranceTimer: Timer?
    private var isInTolerancePeriod = false
    

    
    private override init() {
        super.init()
        Logger.info("ChatTranslationManager initialized with Grammarly-style UX (hidden by default)")
        setupNotifications()
        setupLogoBarManager()
        
        // Start monitoring only if user has chat translation access
        if SessionManager.shared.hasChatTranslationAccess() {
            startMonitoring()
        } else {
            isEnabled = false
            Logger.info("Chat translation disabled for free user")
        }
        
        // Listen for user login/logout to update feature access
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDidLogin),
            name: .userDidLogin,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDidLogout),
            name: .userDidLogout,
            object: nil
        )
    }
    
    deinit {
        Logger.info("ChatTranslationManager deallocating")
        stopMonitoring()
        logoBarManager.disable()
        clearTolerancePeriod() // Clean up tolerance period
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    /// Enable chat translation feature
    func enable() {
        guard !isEnabled else { return }
        
        // Check if user has access to chat translation feature
        guard SessionManager.shared.hasChatTranslationAccess() else {
            Logger.info("Cannot enable chat translation - user does not have Pro/Max access")
            return
        }
        
        isEnabled = true
        Logger.info("Chat translation feature enabled with Grammarly-style UX")
        
        // Enable logo bar manager
        logoBarManager.enable()
        
        // Start monitoring for chat applications
        startMonitoring()
        
        // Check if there's already an active chat application
        checkCurrentActiveApp()
    }
    
    /// Disable chat translation feature
    func disable() {
        guard isEnabled else { return }
        
        isEnabled = false
        Logger.info("Chat translation feature disabled")
        
        // Disable logo bar manager
        logoBarManager.disable()
        
        // Stop monitoring
        stopMonitoring()
        
        // Hide the floating window
        hideTranslationWindow()
    }
    
    /// Check if chat translation is enabled
    func isChatTranslationEnabled() -> Bool {
        return isEnabled
    }
    
    /// Print complete element tree for current chat application (debug method)
    func printChatElementTree() {
        guard let currentApp = currentActiveApp else {
            Logger.info("No active chat application to print element tree for")
            return
        }
        
        Logger.info("=== Printing Complete Element Tree for \(currentApp.appName) ===")
        
        // Get the frontmost application
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            Logger.info("No frontmost application found")
            return
        }
        
        // Check if the frontmost app is the same as our current active app
        guard frontmostApp.bundleIdentifier == currentApp.bundleId else {
            Logger.info("Frontmost app (\(frontmostApp.localizedName ?? "Unknown")) is not the current active chat app (\(currentApp.appName))")
            return
        }
        
        // Get the accessibility element for the application
        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        
        // Print the complete element tree
        printCompleteElementTree(appElement, depth: 0)
        
        Logger.info("=== End Element Tree for \(currentApp.appName) ===")
    }
    
    /// Recursively print the complete element tree
    private func printCompleteElementTree(_ element: AXUIElement, depth: Int) {
        let indent = String(repeating: "  ", count: depth)
        
        // Get element role
        var role: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        
        if roleResult == .success, let roleString = role as? String {
            Logger.info("\(indent)Role: \(roleString)")
        }
        
        // Get element title if available (important for WeChat history messages)
        var title: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
        
        if titleResult == .success, let titleString = title as? String, !titleString.isEmpty {
            Logger.info("\(indent)Title: \(titleString)")
        }
        
        // Get element description if available
        var description: CFTypeRef?
        let descResult = AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &description)
        
        if descResult == .success, let descString = description as? String, !descString.isEmpty {
            Logger.info("\(indent)Description: \(descString)")
        }
        
        // Get element value if available
        var value: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        
        if valueResult == .success, let valueString = value as? String, !valueString.isEmpty {
            Logger.info("\(indent)Value: \(valueString)")
        }
        
        // Get children and recursively print them
        var children: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        
        if childrenResult == .success, let childrenArray = children as? [AXUIElement] {
            Logger.info("\(indent)Children count: \(childrenArray.count)")
            
            for (index, child) in childrenArray.enumerated() {
                Logger.info("\(indent)Child \(index + 1):")
                printCompleteElementTree(child, depth: depth + 1)
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Setup logo bar manager callbacks
    private func setupLogoBarManager() {
        logoBarManager.onLogoBarClick = { [weak self] in
            self?.handleLogoBarClick()
        }
    }
    
    /// Handle logo bar click - show/hide translation window
    private func handleLogoBarClick() {
        Logger.info("Logo bar clicked - toggling translation window visibility")
        
        if isTranslationWindowVisible {
            hideTranslationWindow()
        } else {
            isUserRequestedWindow = true // User has requested to show window
            
            // Record the previous active app (before Glotera gets activated by the click)
            // We need to get the app that was active before the click event
            if let lastActiveApp = currentActiveApp {
                // Use the last known active chat app
                previousActiveApp = NSRunningApplication.runningApplications(withBundleIdentifier: lastActiveApp.bundleId).first
                Logger.info("Recorded previous active app from currentActiveApp: \(lastActiveApp.appName)")
            } else {
                // Fallback: try to get the frontmost app (might be Glotera already)
                let currentApp = NSWorkspace.shared.frontmostApplication
                previousActiveApp = currentApp
                Logger.info("Recorded current app as previous: \(currentApp?.localizedName ?? "Unknown")")
            }
            
            showTranslationWindow()
            
            // Start tolerance period immediately to prevent window hiding during app switching
            startTolerancePeriod()
            
            // Always try to auto-reactivate if we have a previous app
            if let app = previousActiveApp {
                Logger.info("Attempting to auto-reactivate app: \(app.localizedName ?? "Unknown")")
                
                // Delay reactivation to ensure window is fully shown
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.attemptReactivation()
                }
            }
        }
    }
    
    /// Show translation window for current active app
    private func showTranslationWindow() {
        guard let currentActiveApp = currentActiveApp else {
            Logger.warn("No active chat app to show translation window for")
            return
        }
        
        Logger.info("showTranslationWindow called with currentActiveApp: bundleId=\(currentActiveApp.bundleId), appName=\(currentActiveApp.appName)")
        
        // Check if this is WhatsApp or other chat app
        let isWhatsApp = AppDetectionManager.shared.isWhatsAppApp(bundleId: currentActiveApp.bundleId)
        
        // Create window if it doesn't exist
        if chatTranslationWindow == nil {
            chatTranslationWindow = ChatTranslationWindow()
            Logger.debug("Created new ChatTranslationWindow instance")
        }
        
        if isWhatsApp {
            // Show the normal translation window for WhatsApp
            chatTranslationWindow?.showWindowAtScreenSide(currentActiveApp)
            isTranslationWindowVisible = true
            Logger.info("Translation window shown for WhatsApp: \(currentActiveApp.appName)")
        } else {
            // Show unsupported app message for other chat apps
            showTranslationWindowForUnsupportedApp(currentActiveApp)
            Logger.info("Translation window shown with unsupported message for: \(currentActiveApp.appName)")
        }
        
        Logger.debug("Translation window visible state: \(isTranslationWindowVisible)")
    }
    
    /// Show translation window for unsupported app
    private func showTranslationWindowForUnsupportedApp(_ appInfo: AppInfo) {
        // Create window if it doesn't exist
        if chatTranslationWindow == nil {
            chatTranslationWindow = ChatTranslationWindow()
            Logger.debug("Created new ChatTranslationWindow instance for unsupported app")
        }
        
        // Show the window with unsupported app message
        chatTranslationWindow?.showWindowAtScreenSide(appInfo)
        isTranslationWindowVisible = true
        
        Logger.info("Translation window shown for unsupported app: \(appInfo.appName)")
        Logger.debug("Translation window visible state: \(isTranslationWindowVisible)")
    }
    
    /// Hide translation window
    private func hideTranslationWindow() {
        chatTranslationWindow?.hideWindow()
        isTranslationWindowVisible = false
        isUserRequestedWindow = false // Reset user control when manually hidden
        clearTolerancePeriod() // Clear tolerance period when hiding window
        Logger.info("Translation window hidden and marked as not visible")
        Logger.debug("Translation window visible state: \(isTranslationWindowVisible)")
    }
    
    /// Check if translation window is currently visible
    func isTranslationWindowCurrentlyVisible() -> Bool {
        return isTranslationWindowVisible
    }
    
    /// Notify that translation window was closed by user (via close button)
    func notifyWindowClosedByUser() {
        isTranslationWindowVisible = false
        isUserRequestedWindow = false // Reset user control when user closes window
        clearTolerancePeriod() // Clear tolerance period when user closes window
        Logger.info("Translation window closed by user - logo bar remains active")
        Logger.debug("Translation window visible state after user close: \(isTranslationWindowVisible)")
    }
    
    // MARK: - Auto-reactivation and Tolerance Period Methods
    
    /// Attempt to reactivate the previous chat application
    private func attemptReactivation() {
        guard let app = previousActiveApp else { 
            Logger.info("No previous app to reactivate")
            return 
        }
        
        // Check if app is still available
        if app.isTerminated {
            Logger.info("Previous app is terminated, using tolerance period")
            startTolerancePeriod()
            return
        }
        
        // Try to activate the app
        let activated = app.activate()
        
        if activated {
            Logger.info("Successfully reactivated previous app: \(app.localizedName ?? "Unknown")")
            // Reactivation successful, clear tolerance period
            clearTolerancePeriod()
        } else {
            Logger.info("Failed to reactivate app, using tolerance period")
            startTolerancePeriod()
        }
    }
    
    /// Start tolerance period to prevent window hiding during app switching
    private func startTolerancePeriod() {
        isInTolerancePeriod = true
        
        // Set 3-second tolerance period
        toleranceTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.endTolerancePeriod()
        }
        
        Logger.info("Started tolerance period for translation window")
    }
    
    /// End tolerance period and resume normal app detection
    private func endTolerancePeriod() {
        isInTolerancePeriod = false
        toleranceTimer?.invalidate()
        toleranceTimer = nil
        
        Logger.info("Tolerance period ended, resuming normal app detection")
    }
    
    /// Clear tolerance period and reset related state
    private func clearTolerancePeriod() {
        isInTolerancePeriod = false
        toleranceTimer?.invalidate()
        toleranceTimer = nil
        previousActiveApp = nil
        
        Logger.info("Tolerance period cleared")
    }
    
    private func setupNotifications() {
        // Monitor application activation
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidActivate),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        
        // Monitor application termination
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidTerminate),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
        
        // Monitor application hiding
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidHide),
            name: NSWorkspace.didHideApplicationNotification,
            object: nil
        )
        
        // Monitor window changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove),
            name: NSWindow.didMoveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResize),
            name: NSWindow.didResizeNotification,
            object: nil
        )
    }
    
    @objc private func userDidLogin(_ notification: Notification) {
        // Check if user now has chat translation access
        if SessionManager.shared.hasChatTranslationAccess() && !isEnabled {
            Logger.info("User upgraded - enabling chat translation feature")
            enable()
        }
    }
    
    @objc private func userDidLogout(_ notification: Notification) {
        // Disable chat translation when user logs out
        if isEnabled {
            Logger.info("User logged out - disabling chat translation feature")
            disable()
        }
    }
    
    @objc private func applicationDidActivate(_ notification: Notification) {
        guard isEnabled else { return }
        
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            checkAndHandleAppActivation(app)
        }
    }
    
    @objc private func applicationDidTerminate(_ notification: Notification) {
        guard isEnabled else { return }
        
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            if app.bundleIdentifier == lastActiveAppBundleId {
                hideTranslationWindow()
                logoBarManager.disable()
                lastActiveAppBundleId = nil
                currentActiveApp = nil
                Logger.info("Chat application terminated: \(app.localizedName ?? "Unknown")")
            }
        }
    }
    
    @objc private func applicationDidHide(_ notification: Notification) {
        guard isEnabled else { return }
        
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            if app.bundleIdentifier == lastActiveAppBundleId {
                // Don't hide translation window when app is hidden - keep it visible
                // Only disable logo bar, but keep translation window if user manually opened it
                if !isTranslationWindowVisible {
                    logoBarManager.disable()
                }
                Logger.info("Chat application hidden: \(app.localizedName ?? "Unknown") - keeping translation window if manually opened")
            }
        }
    }
    
    @objc private func windowDidMove(_ notification: Notification) {
        guard isEnabled, let _ = notification.object as? NSWindow else { return }
        
        // Check if the moved window belongs to our active chat application and translation window is visible
        if isTranslationWindowVisible,
           let activeApp = NSWorkspace.shared.frontmostApplication,
           let bundleId = activeApp.bundleIdentifier,
           bundleId == lastActiveAppBundleId {
            
            // Update floating window position after a short delay to avoid excessive updates
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.updateTranslationWindowPosition()
            }
        }
    }
    
    @objc private func windowDidResize(_ notification: Notification) {
        guard isEnabled, let _ = notification.object as? NSWindow else { return }
        
        // Check if the resized window belongs to our active chat application and translation window is visible
        if isTranslationWindowVisible,
           let activeApp = NSWorkspace.shared.frontmostApplication,
           let bundleId = activeApp.bundleIdentifier,
           bundleId == lastActiveAppBundleId {
            
            // Update floating window position after resize
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.updateTranslationWindowPosition()
            }
        }
    }
    
    private func checkAndHandleAppActivation(_ app: NSRunningApplication) {
        guard let bundleId = app.bundleIdentifier else { return }
        
        Logger.debug("checkAndHandleAppActivation: bundleId=\(bundleId), appName=\(app.localizedName ?? "Unknown")")
        
        // If in tolerance period, skip hiding logic to prevent window from being hidden during app switching
        if isInTolerancePeriod {
            Logger.debug("In tolerance period, skipping app activation check to prevent window hiding")
            return
        }
        
        // Check if this is Glotera app itself - if so, don't hide translation window
        if bundleId == "ai.glotera.desktop" {
            Logger.debug("Glotera app activated - keeping translation window visible")
            return
        }
        
        // Check if this is a supported chat application using AppDetectionManager
        let isChatApp = AppDetectionManager.shared.isChatApp(bundleId: bundleId)
        Logger.debug("AppDetectionManager.isChatApp(\(bundleId)) = \(isChatApp)")
        
        if isChatApp {
            // Check if this is WhatsApp (fully supported) or other chat app (needs user action)
            let isWhatsApp = AppDetectionManager.shared.isWhatsAppApp(bundleId: bundleId)
            
            // Check if this is the same app we're already monitoring
            if bundleId == lastActiveAppBundleId {
                // Same app, no need to reinitialize - preserve current state
                Logger.debug("Same chat app already active, preserving current state")
                return
            }
            
            // Clean the app name by removing invisible Unicode characters
            let rawAppName = app.localizedName ?? "Unknown"
            let cleanAppName = rawAppName.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\u{200E}", with: "") // Remove Left-to-Right Embedding
                .replacingOccurrences(of: "\u{200F}", with: "") // Remove Right-to-Left Embedding
                .replacingOccurrences(of: "\u{200D}", with: "") // Remove Zero Width Joiner
                .replacingOccurrences(of: "\u{200C}", with: "") // Remove Zero Width Non-Joiner
                .replacingOccurrences(of: "\u{FEFF}", with: "") // Remove Zero Width No-Break Space
            
            let appInfo = AppInfo(
                bundleId: bundleId,
                appName: cleanAppName,
                isBrowser: false,
                isWeChat: AppDetectionManager.shared.isWeChatApp(),
                isChrome: false,
                javaScriptPermissionsEnabled: false
            )
            
            if isWhatsApp {
                // WhatsApp: Enable logo bar and allow auto-show of translation window
                enableLogoBarForApp(appInfo)
                lastActiveAppBundleId = bundleId
                currentActiveApp = appInfo
                Logger.info("WhatsApp activated: \(cleanAppName) - Logo bar enabled, auto-translation supported")
            } else {
                // Other chat apps: Enable logo bar but hide translation window automatically
                enableLogoBarForApp(appInfo)
                lastActiveAppBundleId = bundleId
                currentActiveApp = appInfo
                
                // Hide translation window for unsupported chat apps (user needs to click logo to see unsupported message)
                if isTranslationWindowVisible {
                    chatTranslationWindow?.orderOut(nil)
                    isTranslationWindowVisible = false
                    Logger.info("Unsupported chat app activated: \(cleanAppName) - Logo bar enabled but translation window hidden")
                } else {
                    Logger.info("Unsupported chat app activated: \(cleanAppName) - Logo bar enabled (window already hidden)")
                }
            }
        } else if lastActiveAppBundleId != nil {
            // If a non-chat app was activated, hide translation window but keep user control state
            logoBarManager.disable()
            lastActiveAppBundleId = nil
            currentActiveApp = nil
            
            // Hide window if it was visible, but don't reset user control
            if isTranslationWindowVisible {
                chatTranslationWindow?.orderOut(nil)
                isTranslationWindowVisible = false
                Logger.info("Non-chat app activated - hiding translation window but keeping user control")
            } else {
                Logger.info("Non-chat app activated - logo bar disabled")
            }
        } else {
            // If a new app was activated but it's not a chat app
            // Hide translation window and don't show anything for non-chat apps
            if isTranslationWindowVisible {
                chatTranslationWindow?.orderOut(nil)
                isTranslationWindowVisible = false
                Logger.info("Non-chat app activated: \(app.localizedName ?? "Unknown") - hiding translation window")
            }
        }
    }
    
    private func startMonitoring() {
        // Start a timer to periodically check for active applications
        appMonitoringTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkCurrentActiveApp()
        }
        
        // Start a timer to periodically update translation window position
        windowPositionTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.updateTranslationWindowPositionIfNeeded()
        }
        
        Logger.info("Started monitoring with timers and NSWorkspace notifications")
    }
    
    private func stopMonitoring() {
        appMonitoringTimer?.invalidate()
        appMonitoringTimer = nil
        
        windowPositionTimer?.invalidate()
        windowPositionTimer = nil
        
        Logger.info("Stopped monitoring")
    }
    
    private func checkCurrentActiveApp() {
        guard isEnabled else { return }
        
        if let activeApp = NSWorkspace.shared.frontmostApplication {
            checkAndHandleAppActivation(activeApp)
        }
    }
    
    /// Enable logo bar for the specified chat application
    private func enableLogoBarForApp(_ appInfo: AppInfo) {
        // Store current app info for later use when logo bar is clicked
        currentActiveApp = appInfo
        
        // Enable logo bar manager to show logo bar on screen edge hover (only if not already enabled)
        if !logoBarManager.isLogoBarEnabled() {
            logoBarManager.enable()
            Logger.info("Logo bar enabled for chat app: \(appInfo.appName)")
        } else {
            Logger.debug("Logo bar already enabled for chat app: \(appInfo.appName)")
        }
        
        // If user has requested window, re-show it when chat app is activated
        if isUserRequestedWindow {
            Logger.info("User has requested window - re-showing translation window for chat app: \(appInfo.appName)")
            showTranslationWindow()
        }
    }
    
    private func updateTranslationWindowPosition() {
        guard isTranslationWindowVisible else { return }
        chatTranslationWindow?.updatePosition()
    }
    
    private func updateTranslationWindowPositionIfNeeded() {
        guard isEnabled, 
              isTranslationWindowVisible else { return }
        
        // Check if translation window should be visible but isn't - re-show it
        if let window = chatTranslationWindow {
            if !window.isVisible {
                Logger.warn("Translation window should be visible but isn't - re-showing it")
                window.makeKeyAndOrderFront(nil)
                
                // Only reposition when re-showing the window
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.updateTranslationWindowPosition()
                }
            }
        }
    }
    
    // positionWindowAtScreenRightEdge method removed - window positioning is now handled by ChatTranslationWindow
    
    /// Get the chat translation window instance
    func getChatTranslationWindow() -> ChatTranslationWindow? {
        return chatTranslationWindow
    }
    
    /// Check if translation window is currently visible
    func getTranslationWindowVisible() -> Bool {
        return isTranslationWindowVisible
    }
} 
