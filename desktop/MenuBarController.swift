import Cocoa
import UserNotifications

class MenuBarController {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var languageConfigWindow: LanguageConfigWindow?
    private var statusInfoStorage: [String: String] = [:] // 存储状态信息

    init() {
        Logger.info("MenuBarController initialized")
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "Translator")
        }
        constructMenu()
    }

    func constructMenu() {
        let menu = NSMenu()
        
        // Main function menu
        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        // Debug menu
        menu.addItem(NSMenuItem.separator())
        let debugMenu = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        let debugSubMenu = NSMenu()
        
        let detailedDiagnosticsItem = NSMenuItem(title: "Detailed Diagnostics", action: #selector(detailedDiagnostics), keyEquivalent: "")
        detailedDiagnosticsItem.target = self
        debugSubMenu.addItem(detailedDiagnosticsItem)
        
        debugSubMenu.addItem(NSMenuItem.separator())
        
        let testTriggerItem = NSMenuItem(title: "Test Trigger", action: #selector(testTrigger), keyEquivalent: "")
        testTriggerItem.target = self
        debugSubMenu.addItem(testTriggerItem)
        
        let testDiscordTriggerItem = NSMenuItem(title: "Test Discord Trigger", action: #selector(testDiscordTrigger), keyEquivalent: "")
        testDiscordTriggerItem.target = self
        debugSubMenu.addItem(testDiscordTriggerItem)
        
        let testSpaceKeyItem = NSMenuItem(title: "Test Space Key Capture", action: #selector(testSpaceKeyCapture), keyEquivalent: "")
        testSpaceKeyItem.target = self
        debugSubMenu.addItem(testSpaceKeyItem)
        
        let testWeChatEnterItem = NSMenuItem(title: "Test WeChat Enter Key", action: #selector(testWeChatEnterKey), keyEquivalent: "")
        testWeChatEnterItem.target = self
        debugSubMenu.addItem(testWeChatEnterItem)
        
        let testEnterLoopItem = NSMenuItem(title: "Test Enter Key Loop", action: #selector(testEnterKeyLoop), keyEquivalent: "")
        testEnterLoopItem.target = self
        debugSubMenu.addItem(testEnterLoopItem)
        
        debugSubMenu.addItem(NSMenuItem.separator())
        
        let showCacheInfoItem = NSMenuItem(title: "Show Language Cache Info", action: #selector(showLanguageCacheInfo), keyEquivalent: "")
        showCacheInfoItem.target = self
        debugSubMenu.addItem(showCacheInfoItem)
        
        let refreshCacheItem = NSMenuItem(title: "Refresh Language Cache", action: #selector(refreshLanguageCache), keyEquivalent: "")
        refreshCacheItem.target = self
        debugSubMenu.addItem(refreshCacheItem)
        
        let showStatusItem = NSMenuItem(title: "Show Status", action: #selector(showStatus), keyEquivalent: "")
        showStatusItem.target = self
        debugSubMenu.addItem(showStatusItem)
        
        let restartEventItem = NSMenuItem(title: "Restart Event Monitoring", action: #selector(restartEventMonitoring), keyEquivalent: "")
        restartEventItem.target = self
        debugSubMenu.addItem(restartEventItem)
        
        debugSubMenu.addItem(NSMenuItem.separator())
        
        let resetCountersItem = NSMenuItem(title: "Reset Counters", action: #selector(resetCounters), keyEquivalent: "")
        resetCountersItem.target = self
        debugSubMenu.addItem(resetCountersItem)
        
        let forceHealthCheckItem = NSMenuItem(title: "Force Business Logic Check", action: #selector(forceBusinessLogicCheck), keyEquivalent: "")
        forceHealthCheckItem.target = self
        debugSubMenu.addItem(forceHealthCheckItem)
        
        debugSubMenu.addItem(NSMenuItem.separator())
        
        let openConsoleItem = NSMenuItem(title: "Open Console", action: #selector(openConsole), keyEquivalent: "")
        openConsoleItem.target = self
        debugSubMenu.addItem(openConsoleItem)
        
        debugMenu.submenu = debugSubMenu
        menu.addItem(debugMenu)
        
        // Exit menu
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }

    @objc func openSettings() {
        Logger.info("Settings menu clicked")
        
        // 如果窗口已存在，直接显示
        if let existingWindow = languageConfigWindow {
            existingWindow.show()
            return
        }
        
        // 创建新的语言配置窗口
        languageConfigWindow = LanguageConfigWindow()
        languageConfigWindow?.show()
        
        // 监听窗口关闭事件，释放引用
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: languageConfigWindow,
            queue: .main
        ) { [weak self] _ in
            self?.languageConfigWindow = nil
        }
    }
    
    @objc func testTrigger() {
        Logger.info("Manual trigger test requested")
        
        // 在后台线程执行测试，避免阻塞主线程
        DispatchQueue.global(qos: .userInitiated).async {
            InputMonitor.shared.manualTriggerTest()
            
            // 回到主线程显示非阻塞通知
            DispatchQueue.main.async {
                self.showNonBlockingNotification(
                    title: "Trigger Test Completed",
                    message: "Please check console output for detailed information"
                )
            }
        }
    }
    
    @objc func testDiscordTrigger() {
        Logger.info("Discord trigger test requested")
        
        // 在后台线程执行测试，避免阻塞主线程
        DispatchQueue.global(qos: .userInitiated).async {
            InputMonitor.shared.testDiscordTrigger()
            
            // 回到主线程显示非阻塞通知
            DispatchQueue.main.async {
                self.showNonBlockingNotification(
                    title: "Discord Trigger Test Completed",
                    message: "Please check console output for detailed information.\nRecommend entering test content (like 'hello #@en') in Discord input box before running this test."
                )
            }
        }
    }
    
    @objc func testSpaceKeyCapture() {
        Logger.info("Space key capture test requested")
        InputMonitor.shared.testSpaceKeyCapture()
    }
    
    @objc func testWeChatEnterKey() {
        Logger.info("WeChat Enter key test requested")
        
        // 在后台线程执行测试，避免阻塞主线程
        DispatchQueue.global(qos: .userInitiated).async {
            InputMonitor.shared.testWeChatEnterKey()
        }
    }
    
    @objc func testEnterKeyLoop() {
        Logger.info("Enter key loop test requested")
        
        // 在后台线程执行测试，避免阻塞主线程
        DispatchQueue.global(qos: .userInitiated).async {
            InputMonitor.shared.testEnterKeyLoop()
        }
    }
    
    @objc func showLanguageCacheInfo() {
        Logger.info("Language cache info requested")
        
        let cacheInfo = LanguageConfigManager.shared.getCacheInfo()
        Logger.info("Cache info: \(cacheInfo)")
        
        // 显示缓存信息窗口
        DispatchQueue.main.async {
            self.showStatusWindow(statusInfo: cacheInfo)
        }
    }
    
    @objc func refreshLanguageCache() {
        Logger.info("Language cache refresh requested")
        
        DispatchQueue.global(qos: .userInitiated).async {
            LanguageConfigManager.shared.refreshCache()
            
            DispatchQueue.main.async {
                self.showNonBlockingNotification(
                    title: "Cache Refreshed",
                    message: "Language configuration cache has been refreshed"
                )
            }
        }
    }
    
    @objc func showStatus() {
        Logger.info("Status info requested")
        
        // 在后台线程获取状态信息，避免阻塞主线程
        DispatchQueue.global(qos: .userInitiated).async {
            let statusInfo = InputMonitor.shared.getStatusInfo()
            
            // 回到主线程显示状态信息
            DispatchQueue.main.async {
                // 使用非阻塞的窗口显示状态信息
                self.showStatusWindow(statusInfo: statusInfo)
            }
        }
    }
    
    @objc func restartEventMonitoring() {
        Logger.info("Event monitoring restart requested")
        
        // 在后台线程执行重启，避免阻塞主线程
        DispatchQueue.global(qos: .userInitiated).async {
            // Notify AppDelegate to restart event monitoring
            DispatchQueue.main.async {
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.restartEventMonitoring()
                }
                
                // 显示非阻塞通知
                self.showNonBlockingNotification(
                    title: "Restart Completed",
                    message: "Event monitoring has been restarted"
                )
            }
        }
    }
    
    @objc func openConsole() {
        Logger.info("Opening Console app")
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Utilities/Console.app"))
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
    
    // MARK: - 非阻塞通知方法
    
    // 显示非阻塞的系统通知
    private func showNonBlockingNotification(title: String, message: String) {
        // 使用现代的 UserNotifications 框架
        let center = UNUserNotificationCenter.current()
        
        // 请求通知权限
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = message
                content.sound = UNNotificationSound.default
                
                let request = UNNotificationRequest(
                    identifier: UUID().uuidString,
                    content: content,
                    trigger: nil
                )
                
                center.add(request) { error in
                    if let error = error {
                        Logger.error("Notification error: \(error)")
                    }
                }
            } else {
                // 如果没有权限，只在控制台输出
                Logger.warn("\(title): \(message)")
            }
        }
        
        // 同时在控制台输出
        Logger.warn("\(title): \(message)")
    }
    
    // 显示非阻塞的状态窗口
    private func showStatusWindow(statusInfo: String) {
        let statusWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        statusWindow.title = "System Status"
        statusWindow.center()
        statusWindow.isReleasedWhenClosed = true
        
        // 创建文本视图显示状态信息
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.string = statusInfo
        
        scrollView.documentView = textView
        statusWindow.contentView = scrollView
        
        // 添加复制按钮
        let copyButton = NSButton(title: "Copy to Clipboard", target: self, action: #selector(copyStatusToClipboard(_:)))
        let windowId = UUID().uuidString
        copyButton.tag = windowId.hash // 使用 UUID hash 作为标识
        copyButton.frame = NSRect(x: 20, y: 20, width: 150, height: 30)
        
        // 存储状态信息
        statusInfoStorage[windowId] = statusInfo
        
        // 创建容器视图
        let containerView = NSView()
        containerView.addSubview(scrollView)
        containerView.addSubview(copyButton)
        
        // 设置约束
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: copyButton.topAnchor, constant: -10),
            
            copyButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            copyButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -20),
            copyButton.heightAnchor.constraint(equalToConstant: 30)
        ])
        
        statusWindow.contentView = containerView
        statusWindow.makeKeyAndOrderFront(nil)
    }
    
    @objc private func copyStatusToClipboard(_ sender: NSButton) {
        // 通过按钮的 tag 找到对应的状态信息
        if let statusInfo = statusInfoStorage.values.first(where: { $0.hash == sender.tag }) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(statusInfo, forType: .string)
            
            showNonBlockingNotification(
                title: "Copied",
                message: "Status information copied to clipboard"
            )
        }
    }

    @objc func resetCounters() {
        print("[LOG] Reset counters requested")
        
        // 在后台线程执行重置，避免阻塞主线程
        DispatchQueue.global(qos: .userInitiated).async {
            InputMonitor.shared.resetEventCounters()
            
            // 回到主线程显示非阻塞通知
            DispatchQueue.main.async {
                self.showNonBlockingNotification(
                    title: "Counters Reset",
                    message: "Event counters have been reset to zero"
                )
            }
        }
    }
    
    @objc func forceBusinessLogicCheck() {
        Logger.info("Force business logic check requested from menu")
        
        // 在后台线程执行业务逻辑检查，避免阻塞主线程
        DispatchQueue.global(qos: .userInitiated).async {
            InputMonitor.shared.forceBusinessLogicCheck()
            
            // 回到主线程显示非阻塞通知
            DispatchQueue.main.async {
                self.showNonBlockingNotification(
                    title: "Business Logic Check Completed",
                    message: "Please check console output for detailed information"
                )
            }
        }
    }

    @objc func openLanguageConfig() {
        if languageConfigWindow == nil {
            languageConfigWindow = LanguageConfigWindow()
        }
        languageConfigWindow?.show()
    }
    
    // 新增的详细诊断方法
    @objc func detailedDiagnostics() {
        print("[LOG] Detailed diagnostics requested")
        
        // 在后台线程执行详细诊断，避免阻塞主线程
        DispatchQueue.global(qos: .userInitiated).async {
            let diagnostics = self.performDetailedDiagnostics()
            
            // 回到主线程显示结果
            DispatchQueue.main.async {
                self.showDetailedDiagnosticsWindow(diagnostics: diagnostics)
            }
        }
    }
    
    // 执行详细的系统诊断
    private func performDetailedDiagnostics() -> String {
        var report = "=== Glotera Event Tap 详细诊断报告 ===\n\n"
        
        // 1. 基本系统信息
        report += "[System Information]\n"
        report += "- Operating System: \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        report += "- Application Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")\n"
        report += "- Process ID: \(ProcessInfo.processInfo.processIdentifier)\n"
        report += "- Runtime: \(String(format: "%.1f", ProcessInfo.processInfo.systemUptime / 3600)) hours\n\n"
        
        // 2. 权限状态检查
        report += "[Permission Status]\n"
        let hasAccessibility = AXIsProcessTrusted()
        report += "- Accessibility Permission: \(hasAccessibility ? "✅ Granted" : "❌ Denied")\n"
        
        if let bundleId = Bundle.main.bundleIdentifier {
            report += "- Bundle ID: \(bundleId)\n"
        }
        
        // 检查沙盒状态
        let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        report += "- Sandbox Status: \(isSandboxed ? "⚠️ Enabled" : "✅ Disabled")\n\n"
        
        // 3. Event Tap 状态检查
        report += "[Event Tap Status]\n"
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            if let eventTap = appDelegate.eventTap {
                let isValid = CFMachPortIsValid(eventTap)
                let isEnabled = CGEvent.tapIsEnabled(tap: eventTap)
                
                report += "- Event Tap Creation: ✅ Success\n"
                report += "- Event Tap Validity: \(isValid ? "✅ Valid" : "❌ Invalid")\n"
                report += "- Event Tap Enable Status: \(isEnabled ? "✅ Enabled" : "❌ Disabled")\n"
                
                // 获取 Event Tap 的详细配置信息
                report += "- Listening Position: Tail Append\n"
                report += "- Listening Options: Default Tap\n"
                report += "- Listening Event: Key Down\n"
                
                if let runLoopSource = appDelegate.runLoopSource {
                    let isScheduled = CFRunLoopContainsSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
                    report += "- RunLoop Source: \(isScheduled ? "✅ Added" : "❌ Not Added")\n"
                } else {
                    report += "- RunLoop Source: ❌ Not Exist\n"
                }
            } else {
                report += "- Event Tap Creation: ❌ Failed\n"
                report += "- Possible Reasons: Insufficient Permissions or System Restrictions\n"
            }
            
            let isMonitoringActive = appDelegate.isEventMonitoringActive
            report += "- Monitoring Status: \(isMonitoringActive ? "✅ Active" : "❌ Inactive")\n"
        } else {
            report += "- Failed to get AppDelegate instance\n"
        }
        report += "\n"
        
        // 4. InputMonitor 状态
        report += "[Input Monitoring Status]\n"
        let inputMonitor = InputMonitor.shared
        let lastEventTime = inputMonitor.getLastEventTime()
        let timeSinceLastEvent = Date().timeIntervalSince(lastEventTime)
        
        report += "- Total Keyboard Events: \(inputMonitor.totalKeyEventCount)\n"
        report += "- Space Key Events: \(inputMonitor.spaceKeyEventCount)\n"
        report += "- Last Event Time: \(DateFormatter.localizedString(from: lastEventTime, dateStyle: .none, timeStyle: .medium))\n"
        report += "- Time Since Last Event: \(String(format: "%.1f", timeSinceLastEvent)) seconds\n"
        
        if inputMonitor.totalKeyEventCount > 0 {
            let spaceRatio = Double(inputMonitor.spaceKeyEventCount) / Double(inputMonitor.totalKeyEventCount) * 100
            report += "- Space Key Ratio: \(String(format: "%.1f", spaceRatio))%\n"
        }
        report += "\n"
        
        // 5. 系统干扰检查
        report += "[System Interference Check]\n"
        
        // 检查其他可能占用 Event Tap 的应用
        let runningApps = NSWorkspace.shared.runningApplications
        var keyboardApps = [String]()
        
        for app in runningApps {
            if let bundleId = app.bundleIdentifier {
                // 常见的键盘相关应用
                if bundleId.contains("keyboard") || bundleId.contains("input") || 
                   bundleId.contains("karabiner") || bundleId.contains("bettertouchtool") ||
                   bundleId.contains("alfred") || bundleId.contains("textexpander") {
                    keyboardApps.append("\(app.localizedName ?? bundleId) (\(bundleId))")
                }
            }
        }
        
        if keyboardApps.isEmpty {
            report += "- Potential Conflict Apps: ✅ No Common Keyboard Tools Detected\n"
        } else {
            report += "- Potential Conflict Apps: ⚠️ Detected the following apps:\n"
            for app in keyboardApps {
                report += "  • \(app)\n"
            }
        }
        
        // 检查当前前台应用
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            report += "- Current Frontmost App: \(frontApp.localizedName ?? "Unknown") (\(frontApp.bundleIdentifier ?? "Unknown"))\n"
        }
        report += "\n"
        
        // 6. 内存和性能状态
        report += "[Performance Status]\n"
        let processInfo = ProcessInfo.processInfo
        report += "- Physical Memory: \(String(format: "%.1f", Double(processInfo.physicalMemory) / 1024 / 1024 / 1024)) GB\n"
        
        // 获取当前内存使用
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let usedMemoryMB = Double(info.resident_size) / 1024 / 1024
            report += "- Application Memory Usage: \(String(format: "%.1f", usedMemoryMB)) MB\n"
        }
        report += "\n"
        
        // 7. 建议和解决方案
        report += "[Diagnostic Suggestions]\n"
        
        if !hasAccessibility {
            report += "🔴 Critical Issue: Accessibility Permission Not Granted\n"
            report += "   Solution: Go to System Preferences > Security & Privacy > Privacy > Accessibility, and add this app\n\n"
        }
        
        if isSandboxed {
            report += "🟡 Warning: Application is running in sandbox environment\n"
            report += "   This may affect the stability of Event Tap\n\n"
        }
        
        if timeSinceLastEvent > 300 { // 5 minutes
            report += "🟡 Warning: Long time not detected keyboard event\n"
            report += "   Possible reasons: Event Tap is invalid or user is inactive\n\n"
        }
        
        if !keyboardApps.isEmpty {
            report += "🟡 Warning: Detected other keyboard tools\n"
            report += "   These apps may conflict with Glotera\n\n"
        }
        
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate,
           let eventTap = appDelegate.eventTap,
           !CGEvent.tapIsEnabled(tap: eventTap) {
            report += "🔴 Critical Issue: Event Tap is disabled by system\n"
            report += "   Solution: Automatically try to re-enable or restart monitoring\n\n"
        }
        
        report += "[Report Generation Time]\n"
        report += DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .full)
        
        return report
    }
    
    // 显示详细诊断窗口
    private func showDetailedDiagnosticsWindow(diagnostics: String) {
        let diagnosticsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        diagnosticsWindow.title = "Glotera Diagnostics Report"
        diagnosticsWindow.center()
        
        // 创建滚动视图
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        
        // 创建文本视图
        let textView = NSTextView()
        textView.string = diagnostics
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        
        scrollView.documentView = textView
        
        // 创建容器视图
        let containerView = NSView()
        containerView.frame = diagnosticsWindow.contentRect(forFrameRect: diagnosticsWindow.frame)
        
        // 设置约束
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 60),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -20)
        ])
        
        // 添加复制按钮
        let copyButton = NSButton(title: "Copy to Clipboard", target: self, action: #selector(copyDiagnosticsToClipboard(_:)))
        let windowId = UUID().uuidString
        copyButton.tag = windowId.hash
        copyButton.frame = NSRect(x: 20, y: 20, width: 150, height: 30)
        containerView.addSubview(copyButton)
        
        // 存储诊断信息
        statusInfoStorage[windowId] = diagnostics
        
        diagnosticsWindow.contentView = containerView
        diagnosticsWindow.makeKeyAndOrderFront(nil)
    }
    
    @objc private func copyDiagnosticsToClipboard(_ sender: NSButton) {
        if let diagnostics = statusInfoStorage.values.first(where: { $0.hash == sender.tag }) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(diagnostics, forType: .string)
            
            showNonBlockingNotification(
                title: "Copied",
                message: "Diagnostics report copied to clipboard"
            )
        }
    }

} 