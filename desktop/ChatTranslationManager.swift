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
    

    
    private override init() {
        super.init()
        Logger.info("ChatTranslationManager initialized with chat translation enabled by default")
        setupNotifications()
        
        // Start monitoring since feature is enabled by default
        startMonitoring()
    }
    
    deinit {
        Logger.info("ChatTranslationManager deallocating")
        stopMonitoring()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    /// Enable chat translation feature
    func enable() {
        guard !isEnabled else { return }
        
        isEnabled = true
        Logger.info("Chat translation feature enabled")
        
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
        
        // Stop monitoring
        stopMonitoring()
        
        // Hide the floating window
        hideFloatingWindow()
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
                hideFloatingWindow()
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
                hideFloatingWindow()
                Logger.info("Chat application hidden: \(app.localizedName ?? "Unknown")")
            }
        }
    }
    
    @objc private func windowDidMove(_ notification: Notification) {
        guard isEnabled, let _ = notification.object as? NSWindow else { return }
        
        // Check if the moved window belongs to our active chat application
        if let activeApp = NSWorkspace.shared.frontmostApplication,
           let bundleId = activeApp.bundleIdentifier,
           bundleId == lastActiveAppBundleId {
            
            // Update floating window position after a short delay to avoid excessive updates
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.updateFloatingWindowPosition()
            }
        }
    }
    
    @objc private func windowDidResize(_ notification: Notification) {
        guard isEnabled, let _ = notification.object as? NSWindow else { return }
        
        // Check if the resized window belongs to our active chat application
        if let activeApp = NSWorkspace.shared.frontmostApplication,
           let bundleId = activeApp.bundleIdentifier,
           bundleId == lastActiveAppBundleId {
            
            // Update floating window position after resize
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.updateFloatingWindowPosition()
            }
        }
    }
    
    private func checkAndHandleAppActivation(_ app: NSRunningApplication) {
        guard let bundleId = app.bundleIdentifier else { return }
        
        // Check if this is a supported chat application using AppDetectionManager
        if AppDetectionManager.shared.isChatApp(bundleId: bundleId) {
            // Check if this is the same app we're already monitoring
            if bundleId == lastActiveAppBundleId {
                // Same app, no need to reinitialize
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
            
            showFloatingWindow(for: appInfo)
            lastActiveAppBundleId = bundleId
            currentActiveApp = appInfo
            
            Logger.info("Chat application activated: \(cleanAppName)")
        } else if lastActiveAppBundleId != nil {
            // If a non-chat app was activated, hide the floating window
            hideFloatingWindow()
            lastActiveAppBundleId = nil
            currentActiveApp = nil
        }
    }
    
    private func startMonitoring() {
        // Start a timer to periodically check for active applications
        appMonitoringTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkCurrentActiveApp()
        }
        
        // Start a timer to periodically update floating window position
        windowPositionTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.updateFloatingWindowPositionIfNeeded()
        }
    }
    
    private func stopMonitoring() {
        appMonitoringTimer?.invalidate()
        appMonitoringTimer = nil
        
        windowPositionTimer?.invalidate()
        windowPositionTimer = nil
    }
    
    private func checkCurrentActiveApp() {
        guard isEnabled else { return }
        
        if let activeApp = NSWorkspace.shared.frontmostApplication {
            checkAndHandleAppActivation(activeApp)
        }
    }
    
    private func showFloatingWindow(for appInfo: AppInfo) {
        // Create window if it doesn't exist
        if chatTranslationWindow == nil {
            chatTranslationWindow = ChatTranslationWindow()
        }
        
        // Show the window next to the chat application
        chatTranslationWindow?.showNextToApp(appInfo)
    }
    
    private func hideFloatingWindow() {
        chatTranslationWindow?.hideWindow()
    }
    
    private func updateFloatingWindowPosition() {
        chatTranslationWindow?.updatePosition()
    }
    
    private func updateFloatingWindowPositionIfNeeded() {
        guard isEnabled, 
              let activeApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = activeApp.bundleIdentifier,
              bundleId == lastActiveAppBundleId,
              chatTranslationWindow?.isVisible == true else { return }
        
        // Update the floating window position to follow the chat application
        updateFloatingWindowPosition()
    }
} 
