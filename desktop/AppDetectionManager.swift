import Cocoa
import Carbon
import CoreFoundation
import ApplicationServices


/// Application information structure for detection and management
struct AppInfo {
    let bundleId: String
    let appName: String
    let isBrowser: Bool
    let isWeChat: Bool
    let isChrome: Bool
    var javaScriptPermissionsEnabled: Bool
}

/// High-performance application detection manager with accessibility caching
class AppDetectionManager {
    static let shared = AppDetectionManager()
    
    // Supported browser application bundle identifiers
    private let browserBundleIds = [
        "com.google.Chrome",
        "com.apple.Safari", 
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "com.operasoftware.Opera",
        "com.brave.Browser",
        "com.adspower.SunBrowser",
        "com.vivaldi.Vivaldi"
    ]
    
    // Mail application bundle identifiers
    private let mailAppBundleIds = [
        "com.apple.mail",
        "com.microsoft.Outlook",
        "notion.mail.id"
    ]
    
    // Text editor application bundle identifiers
    private let textEditorBundleIds = [
        "com.apple.Notes",
        "com.apple.TextEdit",
        "com.coderforart.One-Markdown",
        "com.microsoft.Word",
        "com.microsoft.Excel",
        "com.microsoft.Powerpoint",
        "com.microsoft.OneNote",
        "com.cursor.Cursor",
        "com.trae.TRAE",
        "com.microsoft.VSCode",
        "com.jetbrains.intellij",
        "com.sublimetext.4"
    ]
    
    // Chat application bundle identifiers
    private let chatAppBundleIds = [
        "com.tencent.xinWeChat",
        "com.alibaba.DingTalkMac",
        "net.whatsapp.WhatsApp",
        "com.hnc.Discord", 
        "com.tdesktop.Telegram",
        "com.slack.Slack",
        "com.electron.lark",
        "com.microsoft.Teams"
    ]
    
    // Terminal application bundle identifiers
    private let terminalAppBundleIds = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.panic.Terminal"
    ]

    // Mail domain list
    private let mailDomains = [
            "gmail.com", "mail.google.com", "outlook.com",
            "mail.live.com","outlook.live.com",
            "hotmail.com", "mail.yahoo.com",
            "mail.icloud.com", "protonmail.com",
            "mail.zoho.com", "mail.yandex.ru",
            "mail.qq.com", "mail.163.com",
            "mail.126.com",  "mail.sina.com"
        ]
    
    // MARK: - Failed Accessibility Apps Cache
    private var failedAccessibilityApps: Set<String> = []
    private let userDefaults = UserDefaults.standard
    private let failedAppsKey = "failed_accessibility_apps"
    
    // MARK: - Debug Options
    private var forceClipboardMode = false // 强制开启剪切板方案
    
    private init() {
        loadFailedAppsFromDisk()
    }
    
    // MARK: - Failed Accessibility Apps Methods
    
    /// Check if we should skip accessibility and use clipboard directly
    func shouldUseClipboardDirectly(for bundleId: String? = nil) -> Bool {
        // 如果强制开启剪切板方案，直接返回true
        if forceClipboardMode {
            Logger.debug("Force clipboard mode enabled - using clipboard directly")
            return true
        }
        
        let targetBundleId = bundleId ?? getBundleId()
        
        if failedAccessibilityApps.contains(targetBundleId) {
            Logger.debug("Using clipboard directly for known failed app: \(targetBundleId)")
            return true
        }
        
        return false
    }
    
    /// Record accessibility failure and enable clipboard fallback
    func recordAccessibilityFailure(for bundleId: String? = nil) {
        let targetBundleId = bundleId ?? getBundleId()
        
        if !failedAccessibilityApps.contains(targetBundleId) {
            Logger.warn("Accessibility failed for \(targetBundleId) - adding to failed apps cache")
            failedAccessibilityApps.insert(targetBundleId)
            saveFailedAppsToDisk()
        }
    }
    
    /// Reset accessibility status for an app (useful for testing or updates)
    func resetAccessibilityStatus(for bundleId: String? = nil) {
        let targetBundleId = bundleId ?? getBundleId()
        
        if failedAccessibilityApps.contains(targetBundleId) {
            Logger.info("Removing \(targetBundleId) from failed accessibility apps")
            failedAccessibilityApps.remove(targetBundleId)
            saveFailedAppsToDisk()
        }
    }
    
    /// Get debug info for failed apps
    func getAccessibilityDebugInfo() -> String {
        var info = "Failed Accessibility Apps Cache:\n"
        
        if failedAccessibilityApps.isEmpty {
            info += "  No failed apps cached yet - all apps will try accessibility first\n"
        } else {
            for bundleId in failedAccessibilityApps.sorted() {
                // Try to get app name
                let appName = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?.localizedName ?? 
                             getAppNameFromBundleId(bundleId)
                
                info += "  ❌ \(appName) (\(bundleId)): Using clipboard fallback\n"
            }
        }
        
        info += "\nDebug Options:\n"
        info += "  Force Clipboard Mode: \(forceClipboardMode ? "✅ Enabled" : "❌ Disabled")\n"
        
        return info
    }
    
    // MARK: - Debug Control Methods
    
    /// Toggle force clipboard mode
    func toggleForceClipboardMode() {
        forceClipboardMode.toggle()
        Logger.info("Force clipboard mode \(forceClipboardMode ? "enabled" : "disabled")")
        
        // 如果当前状态被置为false，则清除failed apps
        if !forceClipboardMode {
            Logger.info("Force clipboard mode disabled, clearing failed accessibility apps cache")
            failedAccessibilityApps.removeAll()
            saveFailedAppsToDisk()
        }
    }
    
    /// Get current force clipboard mode status
    func isForceClipboardModeEnabled() -> Bool {
        return forceClipboardMode
    }
    
    // MARK: - Private Failed Apps Cache Methods
    
    private func loadFailedAppsFromDisk() {
        guard let failedAppsArray = userDefaults.array(forKey: failedAppsKey) as? [String] else {
            Logger.debug("No failed accessibility apps found on disk")
            return
        }
        
        failedAccessibilityApps = Set(failedAppsArray)
        Logger.info("Loaded \(failedAccessibilityApps.count) failed accessibility apps from disk")
        
        // Log loaded failed apps for debugging
        for bundleId in failedAccessibilityApps.sorted() {
            Logger.debug("  Failed app: \(bundleId)")
        }
    }
    
    private func saveFailedAppsToDisk() {
        let failedAppsArray = Array(failedAccessibilityApps).sorted()
        userDefaults.set(failedAppsArray, forKey: failedAppsKey)
        Logger.debug("Saved \(failedAppsArray.count) failed accessibility apps to disk")
    }
    
    private func getAppNameFromBundleId(_ bundleId: String) -> String {
        // Simple mapping for common apps
        switch bundleId {
        case "com.google.Chrome": return "Google Chrome"
        case "com.tencent.xinWeChat": return "WeChat"
        case "net.whatsapp.WhatsApp": return "WhatsApp"
        case "com.hnc.Discord": return "Discord"
        case "com.apple.Safari": return "Safari"
        case "com.microsoft.edgemac": return "Microsoft Edge"
        default:
            // Extract app name from bundle ID
            let components = bundleId.components(separatedBy: ".")
            return components.last?.capitalized ?? "Unknown App"
        }
    }
    
    // MARK: - Public Browser Detection Methods
    
    /// Check if the current active application is a browser
    func getCurrentBrowserInfo() -> (bundleId: String, appName: String)? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return nil
        }
        
        if browserBundleIds.contains(bundleId) {
            return (bundleId: bundleId, appName: frontmostApp.localizedName ?? "Browser")
        }
        
        return nil
    }
    
    /// Check if currently in a web environment
    func isWebEnvironment() -> Bool {
        return getCurrentBrowserInfo() != nil
    }
    
    /// Check if currently on a web mail page
    func isWebMailPage() -> Bool {
        guard getCurrentBrowserInfo() != nil else {
            return false
        }
        
        // Detect current page as mail application via URL
        let url = getWebpageURL()
        if !url.isEmpty {
            let urlLower = url.lowercased()
            for domain in mailDomains {
                if urlLower.contains(domain) {
                    Logger.info("Detected Web mail page via URL: \(domain)")
                    return true
                }
            }
        }
        
        return false
    }
    
    // MARK: - Public Application Type Detection Methods

    //文本编辑或者邮件编辑时，需要使用智能选择
    func isNeedSmartSelectionApp() -> Bool {
        return isMailApp() || isTextEditorApp() || isWebMailPage()
    }
    
    /// Check if current application is a mail client
    func isMailApp() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        }
        
        return mailAppBundleIds.contains(bundleId)
    }
    
    /// Check if current application is a text editor
    func isTextEditorApp() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        }
        
        return textEditorBundleIds.contains(bundleId)
    }
    
    /// Check if current application is a chat application
    func isChatApp() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        }
        
        return chatAppBundleIds.contains(bundleId)
    }
    
    /// Check if current application is Discord
    func isDiscordApp() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        }
        
        return bundleId == "com.hnc.Discord" || bundleId == "com.discord.Discord"
    }
     
    /// Check if current application is a terminal
    func isTerminalApp() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        } 
        
        if terminalAppBundleIds.contains(bundleId) {
            Logger.info("Detected terminal app: \(frontmostApp.localizedName ?? "Unknown") (\(bundleId))")
            return true
        }
        
        return false
    }
    
    /// Check if current application is WeChat
    func isWeChatApp() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        }
        
        return bundleId.contains("wechat") || bundleId.contains("WeChat")
    }
    
    /// Check if current application is WhatsApp
    func isWhatsAppApp() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        }
        
        return bundleId == "net.whatsapp.WhatsApp"
    }
    
    /// Check if current application is TRAE
    func isTRAEApp() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        }
        
        return bundleId == "com.trae.TRAE"
    }
    
    /// Check if current application is Microsoft Teams
    func isTeamsApp() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        }
        
        return bundleId == "com.microsoft.Teams"
    }
    
    /// Check if current application is AdsPower
    func isAdsPowerApp() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        }
        
        return bundleId.contains("adspower") || bundleId.contains("AdsPower")
    } 

    // 历史消息比较特殊，需要单独处理
    func isDingTalkApp() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        }
        
        return bundleId.contains("DingTalk") || bundleId.contains("dingtalk")   
    }
    // MARK: - Public Element Information Methods
    
    /// Get application information for a specific element
    func getAppInfo(for element: AXUIElement) -> AppInfo {
        let pid = getPid(for: element)
        var appName = "Unknown"
        var bundleId = ""
        
        if let app = NSRunningApplication(processIdentifier: pid) {
            appName = app.localizedName ?? "Unknown"
            bundleId = app.bundleIdentifier ?? ""
        }
        
        let isBrowser = browserBundleIds.contains(bundleId)
        let isWeChat = bundleId.contains("wechat") || bundleId.contains("WeChat")
        let isChrome = bundleId == "com.google.Chrome"
        
        // Check Chrome JavaScript permissions
        var jsEnabled = false
        if isChrome {
            jsEnabled = checkChromeJavaScriptPermission()
        }
        
        return AppInfo(
            bundleId: bundleId,
            appName: appName,
            isBrowser: isBrowser,
            isWeChat: isWeChat,
            isChrome: isChrome,
            javaScriptPermissionsEnabled: jsEnabled
        )
    }

    func getBundleId() -> String {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return ""
        }
        return bundleId
    }
    
    /// Get PID for an element
    func getPid(for element: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        let result = AXUIElementGetPid(element, &pid)
        if result != .success {
            Logger.error("Failed to get PID for element")
        }
        return pid
    }
    
    // MARK: - Private Helper Methods
    
    /// Detect web mail page via URL
    private func getWebpageURL() -> String {
        guard let browserInfo = getCurrentBrowserInfo() else {
            return ""
        }
        
        var script = ""
        
        switch browserInfo.bundleId {
       
        case "com.google.Chrome":
            script = """
                tell application "Google Chrome"
                    try
                        tell active tab of front window
                            set currentUrl to URL
                            return currentUrl
                        end tell
                    on error
                        return ""
                    end try
                end tell
            """
        case "com.apple.Safari":
            script = """
                tell application "Safari"
                    try
                        tell front document
                            set currentUrl to URL
                            return currentUrl
                        end tell
                    on error
                        return ""
                    end try
                end tell
            """
        default:
            return getUrlFromBrowser(bundleId: browserInfo.bundleId)
        }
        
        guard let appleScript = NSAppleScript(source: script) else {
            Logger.warn("Failed to create AppleScript for URL detection")
            return ""
        }
        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)
        
        if let error = error {
            Logger.warn("URL detection failed: \(error)")
            return ""
        }
        
        let url = result.stringValue ?? ""
        return url
    }

    private func getUrlFromBrowser(bundleId: String) -> String {
        // 1. 获取 SunBrowser 应用进程
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
            print("⚠️ \(bundleId) is not running")
            return ""
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // 2. 递归搜索地址栏控件，提取 URL
        func findURLInAX(element: AXUIElement, depth: Int = 0) -> String? {
            if depth > 8 { return nil }

            var childrenRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)

            if result == .success, let children = childrenRef as? [AXUIElement] {
                for child in children {
                    // 2.1 检查 AXValue 是否是 URL
                    var value: CFTypeRef?
                    if AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &value) == .success,
                    let str = value as? String,
                    str.lowercased().hasPrefix("http") || str.contains(".com") || str.contains(".org") {
                        print("✅ Found URL in AXValue: \(str)")
                        return str
                    }

                    // 2.2 检查 AXTitle 是否是 URL（备用方案）
                    var title: CFTypeRef?
                    if AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &title) == .success,
                    let str = title as? String,
                    str.lowercased().hasPrefix("http") || str.contains(".com") {
                        print("✅ Found URL in AXTitle: \(str)")
                        return str
                    }

                    // 2.3 递归查找子元素
                    if let found = findURLInAX(element: child, depth: depth + 1) {
                        return found
                    }
                }
            }

            return nil
        }

        // 3. 启动查找流程
        let url = findURLInAX(element: appElement)
        return url ?? ""
    }

    
    // 检查Chrome的AppleScript JavaScript权限
    private func checkChromeJavaScriptPermission() -> Bool {
        // 先检查自动化权限
        let bundleId = "com.google.Chrome"
        _ = URL(fileURLWithPath: "/Applications/Google Chrome.app")
        
        // 检查应用是否安装
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil else {
            Logger.error("Chrome application not found")
            return false
        }
        
        // 检查自动化权限
        let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false]
        let isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !isTrusted {
            Logger.warn("App does not have automation permission for Chrome")
            return false
        }
        
        // 尝试执行简单的Chrome AppleScript命令来验证
        let scriptSource = """
        tell application "Google Chrome"
            try
                get name of first window
                return true
            on error
                return false
            end try
        end tell
        """
        
        // Use cached AppleScript compilation for better performance
        let templateKey = "check_chrome_permission"
        if let script = AppleScriptTemplateCache.shared.getCompiledScript(
            templateKey: templateKey,
            browserType: "com.google.Chrome",
            generator: { scriptSource }
        ) {
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            if error == nil {
                return result.booleanValue
            } else {
                Logger.error("Error executing Chrome AppleScript: \(error!)")
            }
        }
        
        return false
    }
    
    // MARK: - Chrome Accessibility Warm-up
    
    /// 主动触发 Chrome 的 Accessibility 权限，解决某些电脑上权限不生效的问题
    /// 可以在应用启动时、切换到 Chrome 时或手动调用此方法来确保权限生效
    func chromeWarmUpAccessibility() {
        Logger.info("Starting Chrome accessibility warm-up...")
        
        // 检查 Chrome 是否正在运行
        guard let chromeApp = NSWorkspace.shared.runningApplications.first(where: { app in
            guard let bundleId = app.bundleIdentifier else { return false }
            return bundleId.lowercased().contains("chrome")
        }) else {
            Logger.info("Chrome is not running, skipping accessibility warm-up")
            return
        }
        
        Logger.info("Chrome found, PID: \(chromeApp.processIdentifier)")
        
        // 创建 Chrome 的 AXUIElement
        let chromeElement = AXUIElementCreateApplication(chromeApp.processIdentifier)
        
        // 尝试获取 Chrome 的主窗口
        var mainWindow: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(chromeElement, kAXMainWindowAttribute as CFString, &mainWindow)
        
        if windowResult == .success, let window = mainWindow {
            let windowElement = window as! AXUIElement
            Logger.info("Chrome main window found, attempting accessibility warm-up")
            
            // 执行一系列 Accessibility API 调用来"唤醒"Chrome 的权限
            warmUpChromeAccessibility(windowElement)
        } else {
            Logger.warn("Failed to get Chrome main window for accessibility warm-up")
        }
    }
    
    /// 执行 Chrome Accessibility 预热操作
    private func warmUpChromeAccessibility(_ windowElement: AXUIElement) {
        Logger.info("Executing Chrome accessibility warm-up operations...")
        
        // 1. 获取窗口的子元素
        var children: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(windowElement, kAXChildrenAttribute as CFString, &children)
        
        if childrenResult == .success, let childrenArray = children as? NSArray {
            Logger.info("Found \(childrenArray.count) child elements in Chrome window")
            
            // 2. 遍历子元素，尝试获取各种属性来触发权限
            for i in 0..<min(childrenArray.count, 10) { // 限制遍历数量，避免性能问题
                let child = childrenArray[i] as! AXUIElement
                
                // 尝试获取元素的角色
                var role: CFTypeRef?
                let roleResult = AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)
                
                if roleResult == .success, let roleString = role as? String {
                    Logger.debug("Chrome child element \(i) role: \(roleString)")
                    
                    // 3. 对于特定类型的元素，尝试获取更多属性来触发权限
                    if roleString == "AXWebArea" || roleString == "AXGroup" || roleString == "AXGenericElement" {
                        warmUpElementAccessibility(child)
                    }
                }
            }
        }
        
        // 4. 尝试获取窗口的标题和位置信息
        var title: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &title)
        if titleResult == .success, let titleString = title as? String {
            Logger.info("Chrome window title: \(titleString)")
        }
        
        var position: CFTypeRef?
        let positionResult = AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &position)
        if positionResult == .success {
            Logger.info("Chrome window position retrieved successfully")
        }
        
        Logger.info("Chrome accessibility warm-up completed")
    }
    
    /// 对单个元素执行 Accessibility 预热
    private func warmUpElementAccessibility(_ element: AXUIElement) {
        // 尝试获取各种属性来触发 Accessibility 权限
        let attributesToTry: [CFString] = [
            kAXValueAttribute as CFString,
            kAXTitleAttribute as CFString,
            kAXDescriptionAttribute as CFString,
            "AXLabel" as CFString,
            kAXHelpAttribute as CFString,
            kAXSelectedTextAttribute as CFString
        ]
        
        for attribute in attributesToTry {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, attribute, &value)
            
            if result == .success {
                Logger.debug("Successfully accessed Chrome element attribute: \(attribute)")
                // 不需要处理返回值，目的只是触发权限检查
            }
        }
    }
} 
