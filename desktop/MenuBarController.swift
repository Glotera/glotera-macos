import Cocoa
import UserNotifications

class MenuBarController: NSObject, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var languageConfigWindow: ConfigWindow?
    private var audioTestWindow: AudioTestWindow?
    private var statusInfoStorage: [String: String] = [:] // 存储状态信息
    private var settingsObserver: NSObjectProtocol?
    private var lastQuotaInfo: QuotaInfo?
    private var lastQuotaFetchTime: Date?
    private let quotaCacheInterval: TimeInterval = 60 // Cache quota info for 60 seconds

    override init() {
        super.init()
        Logger.info("MenuBarController initialized")
        if let button = statusItem.button {
            if let image = NSImage(named: "StatusIcon") {
                image.size = NSSize(width: 24, height: 24)
                button.image = image
            }
        }
        constructMenu()
    }
    
    deinit {
        Logger.info("MenuBarController deallocating")
        
        // 清理所有观察者
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        // Remove notification observers
        NotificationCenter.default.removeObserver(self, name: .userDidLogin, object: nil)
        NotificationCenter.default.removeObserver(self, name: .userDidLogout, object: nil)
        NotificationCenter.default.removeObserver(self, name: .quotaInfoUpdated, object: nil)
    }

    func constructMenu() {
        let menu = NSMenu()
        
        // Set delegate to get notified when menu opens
        menu.delegate = self
        
        // Authentication menu 
        addAuthenticationMenuItems(to: menu)
        menu.addItem(NSMenuItem.separator()) 
        
        // Main function menu
        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let checkUpdatesItem = NSMenuItem(title: "Check for Updates", action: #selector(checkForUpdates), keyEquivalent: "")
        checkUpdatesItem.target = self
        menu.addItem(checkUpdatesItem)

        // Add Permissions menu item
        let permissionsItem = NSMenuItem(title: "Check Permissions", action: #selector(checkPermissions), keyEquivalent: "")
        permissionsItem.target = self
        menu.addItem(permissionsItem)

        menu.addItem(NSMenuItem.separator())

        let userGuideItem = NSMenuItem(title: "User Guide", action: #selector(openUserGuide), keyEquivalent: "")
        userGuideItem.target = self
        menu.addItem(userGuideItem)
        let releaseNotesItem = NSMenuItem(title: "Release Notes", action: #selector(openReleaseNotes), keyEquivalent: "")
        releaseNotesItem.target = self
        menu.addItem(releaseNotesItem)
        
        // Debug menu (only in development/debug builds)
        //#if DEBUG
        menu.addItem(NSMenuItem.separator())
        
        #if DEBUG
        let debugMenu = NSMenu()
        let debugMenuItem = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        debugMenuItem.submenu = debugMenu
        
        // Force Clipboard Mode toggle
        let isForceClipboardEnabled = AppDetectionManager.shared.isForceClipboardModeEnabled()
        let forceClipboardItem = NSMenuItem(title: "Force Clipboard Mode: \(isForceClipboardEnabled ? "ON" : "OFF")", action: #selector(toggleForceClipboardMode), keyEquivalent: "")
        forceClipboardItem.target = self
        debugMenu.addItem(forceClipboardItem)
        
        // Accessibility Debug Info
        let accessibilityDebugItem = NSMenuItem(title: "Accessibility Debug Info", action: #selector(showAccessibilityDebugInfo), keyEquivalent: "")
        accessibilityDebugItem.target = self
        debugMenu.addItem(accessibilityDebugItem)
        
        // Print Chat Element Tree
        let printChatElementTreeItem = NSMenuItem(title: "Print Chat Element Tree", action: #selector(printChatElementTree), keyEquivalent: "")
        printChatElementTreeItem.target = self
        debugMenu.addItem(printChatElementTreeItem)
        
        // Logo Bar Status Check
        let logoBarStatusItem = NSMenuItem(title: "Check Logo Bar Status", action: #selector(checkLogoBarStatus), keyEquivalent: "")
        logoBarStatusItem.target = self
        debugMenu.addItem(logoBarStatusItem)
        
        // Screenshot Debug Functions
        debugMenu.addItem(NSMenuItem.separator())
        
        let screenshotDiagnosisItem = NSMenuItem(title: "Screenshot Diagnosis", action: #selector(runScreenshotDiagnosis), keyEquivalent: "")
        screenshotDiagnosisItem.target = self
        debugMenu.addItem(screenshotDiagnosisItem)
        
        let testImmediateCaptureItem = NSMenuItem(title: "Test Immediate Capture", action: #selector(testImmediateCapture), keyEquivalent: "")
        testImmediateCaptureItem.target = self
        debugMenu.addItem(testImmediateCaptureItem)
        
        let testWorkflowItem = NSMenuItem(title: "Test Screenshot Workflow", action: #selector(testScreenshotWorkflow), keyEquivalent: "")
        testWorkflowItem.target = self
        debugMenu.addItem(testWorkflowItem)
        
        let checkPermissionsItem = NSMenuItem(title: "Check Screen Recording Permission", action: #selector(checkScreenRecordingPermission), keyEquivalent: "")
        checkPermissionsItem.target = self
        debugMenu.addItem(checkPermissionsItem)

        // Audio Test
        debugMenu.addItem(NSMenuItem.separator())
        let audioTestItem = NSMenuItem(title: "Audio Test", action: #selector(showAudioTest), keyEquivalent: "")
        audioTestItem.target = self
        debugMenu.addItem(audioTestItem)

        menu.addItem(debugMenuItem)
        #endif

        menu.addItem(NSMenuItem.separator())
         
        // Exit menu
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }

    @objc func openSettings() {
        Logger.info("Settings menu clicked")
        
        // 如果窗口已存在，确保它出现在最上层
        if let existingWindow = languageConfigWindow {
            // 多重确保窗口显示在最前面
            existingWindow.makeKeyAndOrderFront(nil)
            existingWindow.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // 创建新的语言配置窗口
        languageConfigWindow = ConfigWindow()
        languageConfigWindow?.show()
        
        // 清理之前的观察者
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        // 监听窗口关闭事件，释放引用
        settingsObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: languageConfigWindow,
            queue: .main
        ) { [weak self] _ in
            Logger.info("Settings window closed, releasing reference")
            self?.languageConfigWindow = nil
            if let observer = self?.settingsObserver {
                NotificationCenter.default.removeObserver(observer)
                self?.settingsObserver = nil
            }
        }
    }
    
    @objc func openUserGuide() {
        Logger.info("User Guide menu clicked - opening website user guide")
        
        // Get the user guide URL from environment manager
        let environmentManager = EnvironmentManager.shared
        let userGuideURL = "\(environmentManager.baseURL)/userguide"
        
        guard let url = URL(string: userGuideURL) else {
            Logger.error("Failed to create user guide URL: \(userGuideURL)")
            return
        }
        
        Logger.info("Opening user guide page: \(userGuideURL)")
        NSWorkspace.shared.open(url)
    }

    @objc func openReleaseNotes() {
        Logger.info("Release Notes menu clicked - opening website release notes")
        
        // Get the user guide URL from environment manager
        let environmentManager = EnvironmentManager.shared
        let releaseNotesURL = "\(environmentManager.baseURL)/release-notes"
        
        guard let url = URL(string: releaseNotesURL) else {
            Logger.error("Failed to create release notes URL: \(releaseNotesURL)")
            return
        }
        
        Logger.info("Opening release notes page: \(releaseNotesURL)")
        NSWorkspace.shared.open(url)
    }
    
    #if DEBUG
    @objc func toggleForceClipboardMode() {
        AppDetectionManager.shared.toggleForceClipboardMode()
        
        // Update menu item title to reflect current state
        if let menu = statusItem.menu {
            for item in menu.items {
                if let submenu = item.submenu {
                    for subItem in submenu.items {
                        if subItem.action == #selector(toggleForceClipboardMode) {
                            let isEnabled = AppDetectionManager.shared.isForceClipboardModeEnabled()
                            subItem.title = "Force Clipboard Mode: \(isEnabled ? "ON" : "OFF")"
                            break
                        }
                    }
                }
            }
        }
        
        Logger.info("Force clipboard mode toggled")
    }
    
    @objc func showAccessibilityDebugInfo() {
        Logger.info("Debug Accessibility Status menu clicked")
        
        let debugInfo = AppDetectionManager.shared.getAccessibilityDebugInfo()
        Logger.info("Accessibility Debug Info:\n\(debugInfo)")
        
        // Show in alert dialog
        let alert = NSAlert()
        alert.messageText = "Accessibility Status Debug"
        alert.informativeText = debugInfo
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Reset Current App")
        alert.addButton(withTitle: "Reset All Apps")
        
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            AppDetectionManager.shared.resetAccessibilityStatus()
            Logger.info("Reset accessibility status for current app")
        } else if response == .alertThirdButtonReturn {
            // Reset all apps (would need additional implementation)
            Logger.info("Reset all accessibility status requested")
            AppDetectionManager.shared.resetAllAccessibilityStatus()
        }
    }
    
    @objc func printChatElementTree() {
        Logger.info("Print Chat Element Tree menu clicked")
        
        // Call the ChatTranslationManager to print the element tree
        ChatTranslationManager.shared.printChatElementTree()
        
        // Show a notification to the user
        showNonBlockingNotification(
            title: "Element Tree Printed",
            message: "Complete element tree has been printed to the console. Check the console output for details."
        )
    }
    
    @objc func checkLogoBarStatus() {
        Logger.info("Check Logo Bar Status menu clicked")
        
        // Call the GloteraLogoBarManager to check logo bar status
        GloteraLogoBarManager.shared.debugLogoBarStatus()
        
        // Show a notification to the user
        showNonBlockingNotification(
            title: "Logo Bar Status Checked",
            message: "Logo bar status has been checked. Check the console output for details."
        )
    }
    #endif
    
    @objc func checkForUpdates() {
        Logger.info("Check for Updates menu clicked")

        // Use UpdateManager to check for updates
        UpdateManager.shared.checkForUpdates()

        // Note: In Sparkle 2.7.1, the standard updater shows its own UI
        // No need for manual notification as Sparkle handles user feedback
    }

    @objc func checkPermissions() {
        Logger.info("Check Permissions menu clicked")

        // Show current permission status
        let status = PermissionManager.shared.getPermissionStatus()

        let alert = NSAlert()
        alert.messageText = "Permission Status"
        alert.alertStyle = .informational

        var message = "Current permission status:\n\n"
        message += "• Screen Recording: \(status.screenRecording ? "✅ Granted" : "❌ Not Granted")\n"
        message += "• Accessibility: \(status.accessibility ? "✅ Granted" : "⚠️ Not Granted")\n\n"

        if !status.screenRecording {
            message += "⚠️ Screenshot translation requires Screen Recording permission.\n"
            if status.dontRemindScreenRecording {
                message += "(Automatic reminders are disabled)\n"
            }
        }

        if !status.accessibility {
            message += "⚠️ Some features may not work without Accessibility permission.\n"
        }

        alert.informativeText = message

        if !status.screenRecording {
            alert.addButton(withTitle: "Grant Screen Recording")
            alert.addButton(withTitle: "Close")
        } else {
            alert.addButton(withTitle: "OK")
        }

        let response = alert.runModal()

        if !status.screenRecording && response == .alertFirstButtonReturn {
            // Request permission
            PermissionManager.shared.requestScreenRecordingPermissionManually()
        }
    }

    
    @objc func showLanguageCacheInfo() {
        Logger.info("Language cache info requested")
        
        let configs = ConfigManager.shared.loadLanguageConfigs()
        let cacheInfo = """
        Language Configuration Cache Info:
        - Total configurations: \(configs.count)
        - Popular languages: \(configs.filter { $0.popular == 1 }.count)
        - Common languages: \(configs.filter { $0.popular == 2 }.count)
        - Other languages: \(configs.filter { $0.popular == 3 }.count)
        - Total triggers: \(configs.flatMap { $0.triggers }.count)
        
        Cache Management:
        - Language configurations are automatically loaded at startup
        - Cache is updated immediately when configurations are saved
        - No manual refresh needed
        """
        
        Logger.info("Cache info: \(cacheInfo)")
        
        // 显示缓存信息窗口
        DispatchQueue.main.async {
            self.showStatusWindow(statusInfo: cacheInfo)
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
    
    // MARK: - Memory Management Debug Methods
    
   
    
    @objc func cleanupIdleWindows() {
        Logger.info("Cleanup idle windows requested")
        
        DispatchQueue.global(qos: .userInitiated).async {
            SimpleMemoryManager.shared.forceCleanup()
            
            DispatchQueue.main.async {
                self.showNonBlockingNotification(
                    title: "Cleanup Complete",
                    message: "Idle translation windows have been cleaned up"
                )
            }
        }
    }
    
    @objc func forceCleanupAllWindows() {
        Logger.info("Force cleanup all windows requested")
        
        DispatchQueue.global(qos: .userInitiated).async {
            SimpleMemoryManager.shared.forceCleanup()
            
            DispatchQueue.main.async {
                self.showNonBlockingNotification(
                    title: "Cleanup Complete",
                    message: "Translation windows have been cleaned up"
                )
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
            languageConfigWindow = ConfigWindow()
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
    
    // MARK: - Authentication Menu
    
    private func addAuthenticationMenuItems(to menu: NSMenu) {
        if SessionManager.shared.isAuthenticated {
            // User is logged in - show user info and logout option
            if let user = SessionManager.shared.getCurrentUser() {
                let userInfoItem = NSMenuItem(title: "Signed in as \(user.username)", action: nil, keyEquivalent: "")
                userInfoItem.isEnabled = false
                menu.addItem(userInfoItem)
                
                // let userTypeItem = NSMenuItem(title: "Account: \(user.userType.capitalized)", action: nil, keyEquivalent: "")
                // userTypeItem.isEnabled = false
                // menu.addItem(userTypeItem)
                
                // Add quota information if available
                if let quotaInfo = lastQuotaInfo {
                    let quotaItem = NSMenuItem(title: quotaInfo.quotaDescription, action: nil, keyEquivalent: "")
                    quotaItem.isEnabled = false
                    menu.addItem(quotaItem)
                } else {
                    // Show loading state and fetch quota automatically
                    let quotaItem = NSMenuItem(title: "Loading quota info...", action: nil, keyEquivalent: "")
                    quotaItem.isEnabled = false
                    menu.addItem(quotaItem)
                    
                    // Automatically fetch quota information
                    fetchQuotaInfoIfNeeded()
                }
                
                menu.addItem(NSMenuItem.separator())
                
                let logoutItem = NSMenuItem(title: "Sign Out", action: #selector(signOut), keyEquivalent: "")
                logoutItem.target = self
                menu.addItem(logoutItem)
            }
        } else {
            // User is not logged in - show login requirement
            let signInItem = NSMenuItem(title: "Sign In Required", action: #selector(signIn), keyEquivalent: "")
            signInItem.target = self
            menu.addItem(signInItem)
            
            let pricingItem = NSMenuItem(title: "Learn About Pricing", action: #selector(openPricing), keyEquivalent: "")
            pricingItem.target = self
            menu.addItem(pricingItem)
            
            menu.addItem(NSMenuItem.separator())
            
            let statusItem = NSMenuItem(title: "⚠️ Login required for translations", action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)
            
            let helpItem = NSMenuItem(title: QuotaLimits.getPlanDescription(), action: nil, keyEquivalent: "")
            helpItem.isEnabled = false
            menu.addItem(helpItem)
        }
        
        // Listen for authentication changes
        setupAuthenticationObservers()
    }
    
    private func setupAuthenticationObservers() {
        // Remove existing observers first
        NotificationCenter.default.removeObserver(self, name: .userDidLogin, object: nil)
        NotificationCenter.default.removeObserver(self, name: .userDidLogout, object: nil)
        NotificationCenter.default.removeObserver(self, name: .quotaInfoUpdated, object: nil)
        
        // Add observers for authentication state changes
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
        
        // Add observer for quota updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(quotaInfoDidUpdate),
            name: .quotaInfoUpdated,
            object: nil
        )
    }
    
    @objc private func signIn() {
        Logger.info("Sign In menu item clicked")
        UserManager.shared.openLoginPage()
    }
    
    @objc private func signOut() {
        Logger.info("Sign Out menu item clicked")
        
        let alert = NSAlert()
        alert.messageText = "Sign Out"
        alert.informativeText = "Are you sure you want to sign out? You will need to sign in again to use translation features."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Sign Out")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            // Clear login state
            SessionManager.shared.clearSession()
            Logger.info("User signed out successfully")
            
            showNonBlockingNotification(
                title: "Signed Out",
                message: "You have been signed out. Please sign in again to use translation features."
            )
        }
    }
    
    @objc private func userDidLogin(_ notification: Notification) {
        DispatchQueue.main.async {
            self.constructMenu()
            
            if let user = notification.object as? User {
                self.showNonBlockingNotification(
                    title: "Welcome Back!",
                    message: "Signed in as \(user.username)"
                )
            }
            
            // Quota info will be automatically fetched when menu is opened
        }
    }
    
    @objc private func userDidLogout(_ notification: Notification) {
        DispatchQueue.main.async {
            // Clear quota info when user logs out
            self.lastQuotaInfo = nil
            self.lastQuotaFetchTime = nil
            self.constructMenu()
        }
    }
    
    @objc private func quotaInfoDidUpdate(_ notification: Notification) {
        guard let quotaInfo = notification.object as? QuotaInfo else {
            Logger.error("Invalid quota info in notification")
            return
        }
        
        Logger.debug("MenuBarController received quota update notification: \(quotaInfo.quotaDescription)")
        updateQuotaDisplay(quotaInfo)
    }
 
    
    @objc private func openPricing() {
        let environmentManager = EnvironmentManager.shared
        let pricingURL = "\(environmentManager.baseURL)/pricing"
        
        guard let url = URL(string: pricingURL) else {
            Logger.error("Failed to create pricing URL")
            return
        }
        
        Logger.info("Opening pricing page: \(pricingURL)")
        NSWorkspace.shared.open(url)
    }
    
    #if DEBUG
    // MARK: - Update Testing Methods (Debug Only)
    
    @objc private func testUpdateAvailable() {
        Logger.info("Testing update available scenario")
        
        // Show info about this test
        showNonBlockingNotification(
            title: "Testing Update Available",
            message: "This test simulates checking for updates when a newer version is available. Check console for details."
        )
        
        // Manually check for updates
        UpdateManager.shared.checkForUpdates()
    }
    
    @objc private func testNoUpdate() {
        Logger.info("Testing no update available scenario")
        
        showNonBlockingNotification(
            title: "Testing No Update",
            message: "This test simulates checking for updates when no update is available. Check console for details."
        )
        
        // Check the current appcast to see what version is advertised
        testAppcastEndpoint()
    }
    
    @objc private func testBetaChannel() {
        Logger.info("Testing beta channel switch")
        
        showNonBlockingNotification(
            title: "Testing Beta Channel",
            message: "Switching to beta channel and checking for updates..."
        )
        
        // Switch to beta channel and check
        UpdateManager.shared.setUpdateChannel("beta")
        UpdateManager.shared.checkForUpdates()
    }
    
    private func testAppcastEndpoint() {
        let url = "http://localhost:1145/api/appcast.xml"
        
        guard let requestURL = URL(string: url) else {
            Logger.error("Invalid appcast URL")
            return
        }
        
        let task = URLSession.shared.dataTask(with: requestURL) { data, response, error in
            if let error = error {
                Logger.error("Appcast test failed: \(error.localizedDescription)")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                Logger.info("Appcast HTTP Status: \(httpResponse.statusCode)")
            }
            
            if let data = data {
                let xmlString = String(data: data, encoding: .utf8) ?? "Unable to decode XML"
                Logger.info("Appcast XML Response:")
                Logger.info(String(xmlString.prefix(500))) // First 500 characters
            }
        }
        
        task.resume()
    }
    #endif
    
    // MARK: - Quota Management
    
    func updateQuotaDisplay(_ quotaInfo: QuotaInfo) {
        Logger.debug("MenuBarController updating quota display: \(quotaInfo.quotaDescription)")
        lastQuotaInfo = quotaInfo
        lastQuotaFetchTime = Date() // Update cache time since we got fresh data
        
        // Update menu to reflect new quota information
        DispatchQueue.main.async {
            Logger.debug("MenuBarController reconstructing menu with updated quota: \(quotaInfo.quotaDescription)")
            self.updateQuotaInCurrentMenu(quotaInfo)
        }
    }
    
    private func fetchQuotaInfoIfNeeded() {
        // Only fetch if user is authenticated and we don't have recent quota info
        guard SessionManager.shared.isAuthenticated else { return }
        
        // Check if we have cached quota info that's still fresh
        if let lastFetchTime = lastQuotaFetchTime,
           Date().timeIntervalSince(lastFetchTime) < quotaCacheInterval,
           lastQuotaInfo != nil {
            Logger.info("Using cached quota info (age: \(Int(Date().timeIntervalSince(lastFetchTime)))s)")
            return
        }
        
        Logger.info("Automatically fetching quota info for menu display")
        
        // Fetch quota information without consuming usage
        TranslatorClient.shared.fetchQuotaInfo { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let quotaInfo):
                    self?.lastQuotaInfo = quotaInfo
                    self?.lastQuotaFetchTime = Date()
                    self?.updateQuotaInCurrentMenu(quotaInfo) // Update current menu in place
                    Logger.debug("Quota info loaded automatically: \(quotaInfo.quotaDescription)")
                case .failure(let error):
                    Logger.error("Failed to fetch quota info automatically: \(error.localizedDescription)")
                    // Even on failure, we might have quota info in the error
                    if case .quotaExceeded(let quotaInfo) = error {
                        self?.lastQuotaInfo = quotaInfo
                        self?.lastQuotaFetchTime = Date()
                        self?.updateQuotaInCurrentMenu(quotaInfo)
                    }
                }
            }
        }
    }
    
    @objc private func refreshQuotaInfo() {
        Logger.info("Refreshing quota info manually")
        
        // Fetch quota information without consuming usage
        TranslatorClient.shared.fetchQuotaInfo { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let quotaInfo):
                    self?.lastQuotaInfo = quotaInfo
                    self?.constructMenu() // Refresh menu to show updated quota
                    Logger.info("Quota info refreshed: \(quotaInfo.quotaDescription)")
                case .failure(let error):
                    Logger.error("Failed to refresh quota info: \(error.localizedDescription)")
                    // Even on failure, we might have quota info in the error
                    if case .quotaExceeded(let quotaInfo) = error {
                        self?.lastQuotaInfo = quotaInfo
                        self?.constructMenu()
                    }
                }
            }
        }
    }
    
    private func updateQuotaInCurrentMenu(_ quotaInfo: QuotaInfo) {
        guard let menu = statusItem.menu else {
            Logger.info("No menu found, constructing new menu")
            constructMenu()
            return
        }
        
        // Find and update quota-related menu items
        for (index, item) in menu.items.enumerated() {
            if item.title.contains("Loading quota info") ||
               item.title.contains("Free -") ||
               item.title.contains("Pro -") ||
               item.title.contains("Max -") {
                
                Logger.debug("Found quota item at index \(index), updating to: \(quotaInfo.quotaDescription)")
                item.title = quotaInfo.quotaDescription
                item.action = nil // Make it non-clickable
                item.isEnabled = false
                return
            }
        }
        
        // If no quota item found, reconstruct the menu
        Logger.info("No quota item found in current menu, reconstructing")
        constructMenu()
    }
    

    
    // MARK: - NSMenuDelegate
    
    func menuWillOpen(_ menu: NSMenu) {
        Logger.debug("Menu will open - checking for fresh quota information")
        
        // Force refresh quota info when menu opens if cache is stale
        if let lastFetchTime = lastQuotaFetchTime,
           Date().timeIntervalSince(lastFetchTime) > quotaCacheInterval {
            Logger.debug("Quota cache is stale, refreshing before menu opens")
            fetchQuotaInfoIfNeeded()
        }
    }
    
    // MARK: - Screenshot Debug Methods
    
    #if DEBUG
    @objc func runScreenshotDiagnosis() {
        Logger.info("🔍 Running comprehensive screenshot diagnosis...")
        ScreenshotManager.shared.diagnoseDifferentCaptureMethods()
        
        // Show alert to user
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Screenshot Diagnosis Complete"
            alert.informativeText = "Test images have been saved to your Desktop. Check for files starting with 'glotera_test_' to see what each capture method produces."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    @objc func testImmediateCapture() {
        Logger.info("📸 Testing immediate screenshot capture...")
        ScreenshotTranslationManager.shared.testImmediateScreenshotCapture()
        
        // Show alert to user
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Immediate Capture Test Complete"
            alert.informativeText = "Test image saved to Desktop as 'glotera_immediate_capture_test.png'. This shows what the hotkey would capture right now."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    @objc func testScreenshotWorkflow() {
        Logger.info("🔄 Testing complete screenshot workflow...")
        ScreenshotTranslationManager.shared.testFullScreenshotWorkflow()
        
        // Show alert to user
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Screenshot Workflow Test Complete"
            alert.informativeText = "Test images saved to Desktop: 'glotera_workflow_precapture.png' and 'glotera_workflow_fullscreen.png' show the comparison between the two capture methods."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    @objc func checkScreenRecordingPermission() {
        Logger.info("🔒 Checking screen recording permission...")

        // Use PermissionManager to check and request permission
        PermissionManager.shared.requestScreenRecordingPermissionManually()

        // Also log current permission status
        let status = PermissionManager.shared.getPermissionStatus()
        Logger.info("Current permission status: \(status.summary)")
    }

    @objc func showAudioTest() {
        Logger.info("🔊 Showing Audio Test window")

        // If window already exists, bring it to front
        if let existingWindow = audioTestWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            existingWindow.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create new audio test window
        audioTestWindow = AudioTestWindow()
        audioTestWindow?.makeKeyAndOrderFront(nil)
        audioTestWindow?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
    #endif

} 
