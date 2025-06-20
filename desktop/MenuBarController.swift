import Cocoa
import UserNotifications

class MenuBarController {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var languageConfigWindow: LanguageConfigWindow?
    private var statusInfoStorage: [String: String] = [:] // 存储状态信息

    init() {
        print("[LOG] MenuBarController initialized")
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
        
        let forceHealthCheckItem = NSMenuItem(title: "Force Health Check", action: #selector(forceHealthCheck), keyEquivalent: "")
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
        print("[LOG] Settings menu clicked")
        
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
        print("[LOG] Manual trigger test requested")
        
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
        print("[LOG] Discord trigger test requested")
        
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
        print("[LOG] Space key capture test requested")
        InputMonitor.shared.testSpaceKeyCapture()
    }
    
    @objc func showStatus() {
        print("[LOG] Status info requested")
        
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
        print("[LOG] Event monitoring restart requested")
        
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
        print("[LOG] Opening Console app")
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
                        print("[NOTIFICATION ERROR] \(error)")
                    }
                }
            } else {
                // 如果没有权限，只在控制台输出
                print("[NOTIFICATION] \(title): \(message)")
            }
        }
        
        // 同时在控制台输出
        print("[NOTIFICATION] \(title): \(message)")
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
    
    @objc func forceHealthCheck() {
        print("[LOG] Force health check requested")
        
        // 在后台线程执行健康检查，避免阻塞主线程
        DispatchQueue.global(qos: .userInitiated).async {
            InputMonitor.shared.forceHealthCheck()
            
            // 回到主线程显示非阻塞通知
            DispatchQueue.main.async {
                self.showNonBlockingNotification(
                    title: "Health Check Completed",
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
        report += "【系统信息】\n"
        report += "- 操作系统: \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        report += "- 应用版本: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知")\n"
        report += "- 进程ID: \(ProcessInfo.processInfo.processIdentifier)\n"
        report += "- 运行时间: \(String(format: "%.1f", ProcessInfo.processInfo.systemUptime / 3600)) 小时\n\n"
        
        // 2. 权限状态检查
        report += "【权限状态】\n"
        let hasAccessibility = AXIsProcessTrusted()
        report += "- Accessibility 权限: \(hasAccessibility ? "✅ 已授权" : "❌ 未授权")\n"
        
        if let bundleId = Bundle.main.bundleIdentifier {
            report += "- Bundle ID: \(bundleId)\n"
        }
        
        // 检查沙盒状态
        let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        report += "- 沙盒状态: \(isSandboxed ? "⚠️ 已启用" : "✅ 已禁用")\n\n"
        
        // 3. Event Tap 状态检查
        report += "【Event Tap 状态】\n"
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            if let eventTap = appDelegate.eventTap {
                let isValid = CFMachPortIsValid(eventTap)
                let isEnabled = CGEvent.tapIsEnabled(tap: eventTap)
                
                report += "- Event Tap 创建: ✅ 成功\n"
                report += "- Event Tap 有效性: \(isValid ? "✅ 有效" : "❌ 无效")\n"
                report += "- Event Tap 启用状态: \(isEnabled ? "✅ 已启用" : "❌ 已禁用")\n"
                
                // 获取 Event Tap 的详细配置信息
                report += "- 监听位置: Tail Append\n"
                report += "- 监听选项: Default Tap\n"
                report += "- 监听事件: Key Down\n"
                
                if let runLoopSource = appDelegate.runLoopSource {
                    let isScheduled = CFRunLoopContainsSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
                    report += "- RunLoop Source: \(isScheduled ? "✅ 已添加" : "❌ 未添加")\n"
                } else {
                    report += "- RunLoop Source: ❌ 不存在\n"
                }
            } else {
                report += "- Event Tap 创建: ❌ 失败\n"
                report += "- 可能原因: 权限不足或系统限制\n"
            }
            
            let isMonitoringActive = appDelegate.isEventMonitoringActive
            report += "- 监听状态: \(isMonitoringActive ? "✅ 活跃" : "❌ 非活跃")\n"
        } else {
            report += "- 无法获取 AppDelegate 实例\n"
        }
        report += "\n"
        
        // 4. InputMonitor 状态
        report += "【输入监听状态】\n"
        let inputMonitor = InputMonitor.shared
        let lastEventTime = inputMonitor.getLastEventTime()
        let timeSinceLastEvent = Date().timeIntervalSince(lastEventTime)
        
        report += "- 总键盘事件: \(inputMonitor.totalKeyEventCount)\n"
        report += "- 空格键事件: \(inputMonitor.spaceKeyEventCount)\n"
        report += "- 最后事件时间: \(DateFormatter.localizedString(from: lastEventTime, dateStyle: .none, timeStyle: .medium))\n"
        report += "- 距离最后事件: \(String(format: "%.1f", timeSinceLastEvent)) 秒\n"
        
        if inputMonitor.totalKeyEventCount > 0 {
            let spaceRatio = Double(inputMonitor.spaceKeyEventCount) / Double(inputMonitor.totalKeyEventCount) * 100
            report += "- 空格键比例: \(String(format: "%.1f", spaceRatio))%\n"
        }
        report += "\n"
        
        // 5. 系统干扰检查
        report += "【系统干扰检查】\n"
        
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
            report += "- 潜在冲突应用: ✅ 未检测到常见的键盘工具\n"
        } else {
            report += "- 潜在冲突应用: ⚠️ 检测到以下应用:\n"
            for app in keyboardApps {
                report += "  • \(app)\n"
            }
        }
        
        // 检查当前前台应用
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            report += "- 当前前台应用: \(frontApp.localizedName ?? "未知") (\(frontApp.bundleIdentifier ?? "未知"))\n"
        }
        report += "\n"
        
        // 6. 内存和性能状态
        report += "【性能状态】\n"
        let processInfo = ProcessInfo.processInfo
        report += "- 物理内存: \(String(format: "%.1f", Double(processInfo.physicalMemory) / 1024 / 1024 / 1024)) GB\n"
        
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
            report += "- 应用内存使用: \(String(format: "%.1f", usedMemoryMB)) MB\n"
        }
        report += "\n"
        
        // 7. 建议和解决方案
        report += "【诊断建议】\n"
        
        if !hasAccessibility {
            report += "🔴 关键问题: Accessibility 权限未授权\n"
            report += "   解决方案: 前往 系统偏好设置 > 安全性与隐私 > 隐私 > 辅助功能，添加此应用\n\n"
        }
        
        if isSandboxed {
            report += "🟡 注意: 应用在沙盒环境中运行\n"
            report += "   这可能会影响 Event Tap 的稳定性\n\n"
        }
        
        if timeSinceLastEvent > 300 { // 5分钟
            report += "🟡 注意: 长时间未检测到键盘事件\n"
            report += "   可能原因: Event Tap 失效或用户不活跃\n\n"
        }
        
        if !keyboardApps.isEmpty {
            report += "🟡 注意: 检测到其他键盘工具\n"
            report += "   这些应用可能与 Glotera 产生冲突\n\n"
        }
        
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate,
           let eventTap = appDelegate.eventTap,
           !CGEvent.tapIsEnabled(tap: eventTap) {
            report += "🔴 关键问题: Event Tap 被系统禁用\n"
            report += "   解决方案: 将自动尝试重新启用或重启监听\n\n"
        }
        
        report += "【报告生成时间】\n"
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
        
        diagnosticsWindow.title = "Glotera 诊断报告"
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
        let copyButton = NSButton(title: "复制到剪贴板", target: self, action: #selector(copyDiagnosticsToClipboard(_:)))
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
                title: "已复制",
                message: "诊断报告已复制到剪贴板"
            )
        }
    }

} 