import Cocoa
import Carbon

class InputMonitor {
    // 移除独立的 eventTap 管理，改为依赖 AppDelegate
    private let triggerPattern = #"(.*?)[@#](id|en|zh|ja|jp|ko|fr|de|es|ru|th)\s*$"#
    private let regex: NSRegularExpression
    
    // 添加健康检查相关属性
    private var lastEventTime: Date = Date()
    private var lastSpaceKeyTime: Date = Date.distantPast
    private var healthCheckTimer: Timer?
    var spaceKeyEventCount = 0
    var totalKeyEventCount = 0
    private var lastHealthCheckRestart: Date?
    private var lastTranslationTime: Date?
    
    // 添加 AppDelegate 引用以便统一管理
    private weak var appDelegate: AppDelegate?

    init() {
        regex = try! NSRegularExpression(pattern: triggerPattern, options: .caseInsensitive)
        // 获取 AppDelegate 引用
        appDelegate = NSApp.delegate as? AppDelegate
        startHealthCheck()
    }
    
    // 启动健康检查定时器
    private func startHealthCheck() {
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.performHealthCheck()
        }
        print("[LOG] Health check timer started")
    }
    
    // 执行健康检查
    func performHealthCheck() {
        let currentTime = Date()
        let timeSinceLastEvent = currentTime.timeIntervalSince(lastEventTime)
        let timeSinceLastSpaceKey = currentTime.timeIntervalSince(lastSpaceKeyTime)
        
        // 检查是否刚刚进行过翻译（可能导致 Event Tap 暂时失效）
        let timeSinceLastTranslation = lastTranslationTime.map { currentTime.timeIntervalSince($0) } ?? Double.infinity
        let isRecentTranslation = timeSinceLastTranslation < 10.0 // 10秒内的翻译被认为是"最近的"
        
        // 检查权限
        let hasPermissions = checkAccessibilityPermissions()
        
        // 检查事件监听器是否有效（通过 AppDelegate）
        let eventTapValid = appDelegate?.isEventTapValid() ?? false
        
        // 检查空格键是否正常工作
        let spaceKeyWorking = (spaceKeyEventCount > 0 && timeSinceLastSpaceKey < 300) || totalKeyEventCount < 10
        
        // 更智能的健康检查条件
        var shouldRestart = false
        var shouldQuickRecover = false
        var reason = ""
        
        // 优先级处理：权限问题最严重
        if !hasPermissions {
            shouldRestart = true
            reason = "Accessibility permissions lost"
        } else if !eventTapValid && totalKeyEventCount > 0 {
            // Event Tap 失效 - 先尝试快速恢复
            if isRecentTranslation {
                Logger.debug("Event tap invalid after recent translation (\(String(format: "%.1f", timeSinceLastTranslation))s ago) - attempting quick recovery")
            } else {
                Logger.warn("Event tap invalid detected during health check - attempting quick recovery")
            }
            
            if let appDelegate = appDelegate, appDelegate.quickEnableEventTap() {
                let message = isRecentTranslation ? 
                    "Event tap quick recovery successful after recent translation" :
                    "Event tap quick recovery successful during health check"
                Logger.info(message)
                return // 快速恢复成功，跳过重启
            } else {
                shouldRestart = true
                let reasonSuffix = isRecentTranslation ? " (post-translation)" : ""
                reason = "Event tap invalid after having events (quick recovery failed)\(reasonSuffix)"
            }
        } else if !spaceKeyWorking && totalKeyEventCount > 100 {
            // 空格键问题，可能是部分功能失效
            shouldQuickRecover = true
            reason = "Space key not working after \(totalKeyEventCount) events"
        }
        
        // 如果只是快速恢复需求，尝试轻量级修复
        if shouldQuickRecover && !shouldRestart {
            Logger.info("Attempting quick recovery for: \(reason)")
            if let appDelegate = appDelegate, appDelegate.quickEnableEventTap() {
                Logger.info("Quick recovery successful")
                return
            } else {
                // 快速恢复失败，升级为重启
                shouldRestart = true
                reason = "\(reason) (quick recovery failed)"
            }
        }
        
        // 增加重启间隔限制，避免频繁重启
        if shouldRestart {
            // 使用递增的重启间隔：第一次60秒，第二次120秒，第三次300秒
            let minInterval: TimeInterval
            if let lastRestart = lastHealthCheckRestart {
                let timeSinceLastRestart = currentTime.timeIntervalSince(lastRestart)
                if timeSinceLastRestart < 60 {
                    minInterval = 60
                } else if timeSinceLastRestart < 300 {
                    minInterval = 120
                } else {
                    minInterval = 300
                }
            } else {
                minInterval = 60
            }
            
            if let lastRestart = lastHealthCheckRestart, currentTime.timeIntervalSince(lastRestart) < minInterval {
                Logger.warn("InputMonitor: Skipping restart request - last restart was less than \(Int(minInterval)) seconds ago")
                return
            }
            
            // 根据是否为翻译后的问题调整日志级别
            if isRecentTranslation {
                Logger.warn("InputMonitor health check failed after recent translation: \(reason)")
            } else {
                Logger.error("InputMonitor health check failed: \(reason)")
            }
            lastHealthCheckRestart = currentTime
            requestEventMonitoringRestart()
        } else {
            // 减少调试输出
            if Int(currentTime.timeIntervalSince1970) % 300 == 0 { // 每5分钟输出一次
                Logger.info("InputMonitor health: OK - Events: \(totalKeyEventCount), Space: \(spaceKeyEventCount), Last event: \(Int(timeSinceLastEvent))s ago")
            }
        }
    }
    
    // 请求 AppDelegate 重启事件监听
    private func requestEventMonitoringRestart() {
        Logger.warn("InputMonitor requesting AppDelegate to restart event monitoring...")
        appDelegate?.restartEventMonitoring()
    }

    // 创建事件监听器的回调函数（供 AppDelegate 调用）
    func createEventTapCallback() -> CGEventTapCallBack {
        return { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
            // 处理 Event Tap 被禁用的情况
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                let disableReason = type == .tapDisabledByTimeout ? "timeout" : "user input"
                Logger.warn("Event tap disabled by \(disableReason), attempting immediate recovery")
                
                // 立即提交恢复任务到后台，不阻塞回调
                DispatchQueue.global(qos: .utility).async {
                    // 先尝试立即快速恢复
                    if let appDelegate = InputMonitor.shared.appDelegate {
                        var recovered = false
                        
                        // 尝试3次快速恢复，间隔递增
                        for attempt in 1...3 {
                            if appDelegate.quickEnableEventTap() {
                                Logger.info("Event tap quick recovery successful on attempt \(attempt)")
                                recovered = true
                                break
                            } else {
                                Logger.warn("Quick recovery attempt \(attempt) failed")
                                if attempt < 3 {
                                    Thread.sleep(forTimeInterval: Double(attempt) * 0.1) // 0.1s, 0.2s delays
                                }
                            }
                        }
                        
                        if !recovered {
                            DispatchQueue.main.async {
                                Logger.warn("All quick recovery attempts failed, performing full restart")
                                InputMonitor.shared.appDelegate?.restartEventMonitoring()
                            }
                        }
                    }
                }
                return Unmanaged.passUnretained(event)
            }
            
            // 极简的事件统计更新
            let shared = InputMonitor.shared
            shared.lastEventTime = Date()
            shared.totalKeyEventCount += 1
            
            // 只处理关键事件，快速返回
            if type == .keyDown {
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                
                if keyCode == kVK_Space { // 空格键
                    shared.lastSpaceKeyTime = Date()
                    shared.spaceKeyEventCount += 1
                    // 立即提交处理任务，不在回调中等待
                    DispatchQueue.global(qos: .userInitiated).async {
                        DispatchQueue.main.async {
                            shared.handleSpaceKey()
                        }
                    }
                } else if keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter { // 回车键
                    // 快速检查，避免复杂逻辑
                    if shared.shouldInterceptEnter() {
                        // 立即提交处理任务
                        DispatchQueue.global(qos: .userInitiated).async {
                            DispatchQueue.main.async {
                                shared.handleInterceptedEnter()
                            }
                        }
                        return nil // 阻止回车事件
                    }
                } else if keyCode == kVK_Tab { // Tab键
                    DispatchQueue.global(qos: .background).async {
                        DispatchQueue.main.async {
                            shared.handleTabKey()
                        }
                    }
                } else if keyCode == 0 && event.flags.contains(.maskCommand) { // Cmd+A 检测
                    DispatchQueue.global(qos: .background).async {
                        DispatchQueue.main.async {
                            shared.handleCmdA()
                        }
                    }
                }
            }
            
            return Unmanaged.passUnretained(event)
        }
    }
    
    private func checkAccessibilityPermissions() -> Bool {
        let trusted = AXIsProcessTrusted()
        // print("[LOG] Accessibility permission check result: \(trusted)")
        
        if !trusted {
            // 获取当前应用的Bundle ID和路径以便调试
            if let bundleId = Bundle.main.bundleIdentifier {
                print("[LOG] Current Bundle ID: \(bundleId)")
            }
            let bundlePath = Bundle.main.bundlePath
            print("[LOG] Current Bundle Path: \(bundlePath)")
        }
        
        return trusted
    }
    
    private func requestAccessibilityPermissions() {
        print("[LOG] Requesting accessibility permissions...")
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let result = AXIsProcessTrustedWithOptions(options as CFDictionary)
        print("[LOG] Permission request result: \(result)")
    }

    static let shared = InputMonitor()

    func handleSpaceKey() {
        // print("[LOG] Space key detected - starting trigger detection")
        
        // 添加更详细的诊断信息
        guard let focused = AXController.shared.getFocusedElement() else {
            print("[LOG] ERROR: No focused element found")
            return
        }
        print("[LOG] Focused element found")
        
        // 检查是否为Discord应用
        let isDiscord = isDiscordApp()
        if isDiscord {
            print("[LOG] Discord detected - using extended delay for trigger detection")
        }
        
        // 首先尝试标准检测
        if let result = AXController.shared.detectTriggerAndExtract() {
            // print("[LOG] Trigger detected: text=\(result.text), lang=\(result.lang)")
            startTranslation(text: result.text, lang: result.lang)
            return
        }
        
        print("[LOG] Standard detection failed, trying delayed detection...")
        // 如果标准检测失败，等待一小段时间后重试（Discord需要更长的延迟）
        let delayTime = isDiscord ? 0.3 : 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + delayTime) {
            if let result = AXController.shared.detectTriggerAndExtract() {
                print("[LOG] Delayed trigger detected: text=\(result.text), lang=\(result.lang)")
                self.startTranslation(text: result.text, lang: result.lang)
            } else {
                // print("[LOG] No trigger detected in input after delay")
                // // 添加更多诊断信息
                // if let value = AXController.shared.getValue(of: focused) {
                //     print("[LOG] Current input content for diagnosis: '\(value)'")
                //     print("[LOG] Content length: \(value.count)")
                    
                //     // 检查是否包含我们期望的模式
                //     let patterns = ["@en", "#en", "@zh", "#zh", "@id", "#id"]
                //     for pattern in patterns {
                //         if value.lowercased().contains(pattern) {
                //             print("[LOG] Found pattern '\(pattern)' in content but regex didn't match")
                //             break
                //         }
                //     }
                // } else {
                //     print("[LOG] Cannot get value from focused element")
                // }
            }
        }
    }
    
    // 检查当前应用是否为Discord
    private func isDiscordApp() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        }
        
        return bundleId == "com.hnc.Discord" || bundleId == "com.discord.Discord"
    }
    
    private func startTranslation(text: String, lang: String) {
        // 记录翻译时间，用于健康检查的智能调整
        lastTranslationTime = Date()
        
        // 标记自动翻译开始，用于后续过滤
        AXController.shared.markAutoTranslationStart(withText: text)
        
        // 获取当前焦点元素用于定位状态窗口
        let focusedElement = AXController.shared.getFocusedElement()
        
        // 显示翻译中状态
        TranslationStatusWindow.shared.showTranslating(near: focusedElement)
        
        // 开始翻译（不禁用输入，避免死锁）
        TranslatorClient.shared.translate(text: text, to: lang) { [weak self] translated in
            DispatchQueue.main.async {
                if let translated = translated {
                    print("[LOG] Translation result: \(translated)")
                    // 翻译成功后立即隐藏状态窗口，然后开始回填
                    TranslationStatusWindow.shared.hideStatus()
                    // print("[LOG] Status window hidden before auto-translation replacement")
                    // 回填翻译结果
                    AXController.shared.replaceInput(with: translated) {
                        print("[LOG] Auto-translation replacement completed")
                    }
                } else {
                    print("[LOG] Translation failed")
                    // 显示失败状态
                    TranslationStatusWindow.shared.showFailure()
                }
            }
        }
    }

    func handleEnterKey() {
        print("[LOG] Enter key detected (non-intercepted)")
        // 非拦截的Enter键处理，用于某些特殊情况
        attemptTriggerDetection(source: "Enter")
    }
    
    func handleTabKey() {
        // print("[LOG] Tab key detected")
        // Tab键可能在某些应用中完成自动补全，然后触发翻译
        // attemptTriggerDetection(source: "Tab")
    }
    
    private func attemptTriggerDetection(source: String) {
        if let result = AXController.shared.detectTriggerAndExtract() {
            //print("[LOG] Trigger detected via \(source): text=\(result.text), lang=\(result.lang)")
            startTranslation(text: result.text, lang: result.lang)
        } else {
            // 对于Enter和Tab键，我们给更多时间让应用更新内容
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if let result = AXController.shared.detectTriggerAndExtract() {
                    print("[LOG] Delayed trigger detected via \(source): text=\(result.text), lang=\(result.lang)")
                    self.startTranslation(text: result.text, lang: result.lang)
                }
            }
        }
    }

    // 检查是否应该拦截回车键进行翻译 - 优化版本
    func shouldInterceptEnter() -> Bool {
        // 使用缓存的最后一次空格键事件时间来决定是否需要检查
        let timeSinceLastSpace = Date().timeIntervalSince(lastSpaceKeyTime)
        
        // 如果距离上次空格键超过5秒，很可能没有触发器
        if timeSinceLastSpace > 5.0 {
            return false
        }
        
        // 快速检查当前输入内容是否包含触发器
        guard let focused = AXController.shared.getFocusedElement(),
              let value = AXController.shared.getValue(of: focused) else {
            return false
        }
        
        // 快速预筛选：如果内容太短或太长，不太可能有触发器
        if value.count < 3 || value.count > 1000 {
            return false
        }
        
        // 简单检查是否包含语言代码的前缀字符
        let content = value.lowercased()
        if !content.contains("@") && !content.contains("#") && !content.contains(" ") {
            return false
        }
        
        // 检查常见的语言代码模式
        let quickPatterns = ["@en", "#en", "@zh", "#zh", "@id", "#id", " en ", " zh ", " id "]
        for pattern in quickPatterns {
            if content.contains(pattern) {
                return true
            }
        }
        
        return false
    }
    
    // 处理被拦截的回车键
    func handleInterceptedEnter() {
        print("[LOG] Handling intercepted Enter key")
        
        if let result = AXController.shared.detectTriggerAndExtract() {
            print("[LOG] Trigger detected via intercepted Enter: text=\(result.text), lang=\(result.lang)")
            
            // 开始翻译，完成后自动发送
            startTranslationWithAutoSend(text: result.text, lang: result.lang)
        } else {
            print("[LOG] No trigger found, sending original Enter key")
            // 如果没有检测到触发器，发送原始回车键
            sendEnterKey()
        }
    }
    
    // 翻译完成后自动发送
    private func startTranslationWithAutoSend(text: String, lang: String) {
        // 标记自动翻译开始，用于后续过滤
        AXController.shared.markAutoTranslationStart(withText: text)
        
        // 获取当前焦点元素用于定位状态窗口
        let focusedElement = AXController.shared.getFocusedElement()
        
        // 显示翻译中状态
        TranslationStatusWindow.shared.showTranslating(near: focusedElement)
        
        // 开始翻译（不禁用输入，避免死锁）
        TranslatorClient.shared.translate(text: text, to: lang) { [weak self] translated in
            DispatchQueue.main.async {
                if let translated = translated {
                    print("[LOG] Translation result: \(translated)")
                    // 翻译成功后立即隐藏状态窗口，然后开始回填
                    TranslationStatusWindow.shared.hideStatus()
                    print("[LOG] Status window hidden before auto-translation with send")
                    // 回填翻译结果，完成后发送回车键
                    AXController.shared.replaceInput(with: translated) {
                        print("[LOG] Auto-translation with send completed")
                        
                        // 等待一小段时间确保内容更新，然后发送回车键
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self?.sendEnterKey()
                        }
                    }
                } else {
                    print("[LOG] Translation failed")
                    // 显示失败状态
                    TranslationStatusWindow.shared.showFailure()
                    // 翻译失败时发送原始内容
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self?.sendEnterKey()
                    }
                }
            }
        }
    }
    
    // 发送回车键事件
    private func sendEnterKey() {
        print("[LOG] Sending Enter key event")
        
        let source = CGEventSource(stateID: .hidSystemState)
        if let enterKeyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: true),
           let enterKeyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: false) {
            
            enterKeyDown.post(tap: .cghidEventTap)
            enterKeyUp.post(tap: .cghidEventTap)
        }
    }

    // 手动测试触发器检测（用于调试）
    func manualTriggerTest() {
        print("[LOG] === Manual Trigger Test Started ===")
        
        // 检查权限
        let hasPermissions = checkAccessibilityPermissions()
        print("[LOG] Test - Accessibility permissions: \(hasPermissions)")
        
        // 检查事件监听器
        let eventTapValid = appDelegate?.isEventTapValid() ?? false
        print("[LOG] Test - Event tap valid: \(eventTapValid)")
        
        // 检查焦点元素
        if let focused = AXController.shared.getFocusedElement() {
            print("[LOG] Test - Focused element found")
            
            // 尝试获取内容
            if let value = AXController.shared.getValue(of: focused) {
                print("[LOG] Test - Current content: '\(value)'")
                print("[LOG] Test - Content length: \(value.count)")
                
                // 测试触发器检测
                if let result = AXController.shared.detectTriggerAndExtract() {
                    print("[LOG] Test - Trigger detected: text='\(result.text)', lang='\(result.lang)'")
                } else {
                    print("[LOG] Test - No trigger detected")
                    
                    // 检查是否包含常见模式
                    let testPatterns = ["@en", "#en", "@zh", "#zh"]
                    for pattern in testPatterns {
                        if value.lowercased().contains(pattern) {
                            print("[LOG] Test - Found '\(pattern)' in content but not detected as trigger")
                        }
                    }
                }
            } else {
                print("[LOG] Test - Cannot get value from focused element")
            }
        } else {
            print("[LOG] Test - No focused element found")
        }
        
        print("[LOG] === Manual Trigger Test Completed ===")
    }
    
    // 获取当前状态信息
    func getStatusInfo() -> String {
        var status = "InputMonitor Status:\n"
        status += "- Accessibility Permissions: \(checkAccessibilityPermissions())\n"
        status += "- Event Tap Valid: \(appDelegate?.isEventTapValid() ?? false)\n"
        status += "- Last Event Time: \(lastEventTime)\n"
        status += "- Time Since Last Event: \(Date().timeIntervalSince(lastEventTime))s\n"
        status += "- Last Space Key Time: \(lastSpaceKeyTime)\n"
        status += "- Time Since Last Space Key: \(Date().timeIntervalSince(lastSpaceKeyTime))s\n"
        status += "- Total Key Events: \(totalKeyEventCount)\n"
        status += "- Space Key Events: \(spaceKeyEventCount)\n"
        
        // 计算空格键事件比例
        if totalKeyEventCount > 0 {
            let spaceKeyRatio = Double(spaceKeyEventCount) / Double(totalKeyEventCount) * 100
            status += "- Space Key Ratio: \(String(format: "%.1f", spaceKeyRatio))%\n"
        }
        
        if let focused = AXController.shared.getFocusedElement() {
            status += "- Focused Element: Available\n"
            if let value = AXController.shared.getValue(of: focused) {
                status += "- Current Content Length: \(value.count) chars\n"
            } else {
                status += "- Current Content: Not accessible\n"
            }
        } else {
            status += "- Focused Element: None\n"
        }
        
        return status
    }

    // 获取最后事件时间
    func getLastEventTime() -> Date {
        return lastEventTime
    }

    // 专门的Discord测试方法
    func testDiscordTrigger() {
        print("[LOG] === Discord Trigger Test Started ===")
        
        // 检查是否在Discord中
        let isDiscord = isDiscordApp()
        print("[LOG] Discord Test - Is Discord app: \(isDiscord)")
        
        if !isDiscord {
            print("[LOG] Discord Test - Warning: Not currently in Discord app")
        }
        
        // 检查基本状态
        let hasPermissions = checkAccessibilityPermissions()
        print("[LOG] Discord Test - Accessibility permissions: \(hasPermissions)")
        
        let eventTapValid = appDelegate?.isEventTapValid() ?? false
        print("[LOG] Discord Test - Event tap valid: \(eventTapValid)")
        
        // 检查焦点元素
        if let focused = AXController.shared.getFocusedElement() {
            print("[LOG] Discord Test - Focused element found")
            
            // 尝试获取内容
            if let value = AXController.shared.getValue(of: focused) {
                print("[LOG] Discord Test - Current content: '\(value)'")
                print("[LOG] Discord Test - Content length: \(value.count)")
                
                // 测试预处理
                let isDiscordOrChat = AXController.shared.isDiscordOrChatApp()
                print("[LOG] Discord Test - Detected as chat app: \(isDiscordOrChat)")
                
                // 测试触发器检测
                if let result = AXController.shared.detectTriggerAndExtract() {
                    print("[LOG] Discord Test - Trigger detected: text='\(result.text)', lang='\(result.lang)'")
                } else {
                    print("[LOG] Discord Test - No trigger detected")
                    
                    // 检查常见模式
                    let testPatterns = ["@en", "#en", "@zh", "#zh"]
                    for pattern in testPatterns {
                        if value.lowercased().contains(pattern) {
                            print("[LOG] Discord Test - Found '\(pattern)' in content but not detected as trigger")
                            print("[LOG] Discord Test - Raw content: '\(value)'")
                            print("[LOG] Discord Test - Lowercased: '\(value.lowercased())'")
                        }
                    }
                }
            } else {
                print("[LOG] Discord Test - Cannot get value from focused element")
            }
        } else {
            print("[LOG] Discord Test - No focused element found")
        }
        
        print("[LOG] === Discord Trigger Test Completed ===")
    }

    // 专门测试空格键捕获
    func testSpaceKeyCapture() {
        print("[LOG] === Space Key Capture Test Started ===")
        
        let initialSpaceCount = spaceKeyEventCount
        let initialTotalCount = totalKeyEventCount
        
        print("[LOG] Space Key Test - Initial space key count: \(initialSpaceCount)")
        print("[LOG] Space Key Test - Initial total key count: \(initialTotalCount)")
        print("[LOG] Space Key Test - Event tap valid: \(appDelegate?.isEventTapValid() ?? false)")
        
        // 提示用户按空格键
        let alert = NSAlert()
        alert.messageText = "空格键测试"
        alert.informativeText = "请在任意输入框中按几次空格键，然后点击'完成测试'按钮。\n\n当前空格键事件计数: \(spaceKeyEventCount)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "完成测试")
        alert.addButton(withTitle: "取消")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // 检查空格键事件是否增加
            let finalSpaceCount = spaceKeyEventCount
            let finalTotalCount = totalKeyEventCount
            
            print("[LOG] Space Key Test - Final space key count: \(finalSpaceCount)")
            print("[LOG] Space Key Test - Final total key count: \(finalTotalCount)")
            print("[LOG] Space Key Test - Space key events captured: \(finalSpaceCount - initialSpaceCount)")
            print("[LOG] Space Key Test - Total key events captured: \(finalTotalCount - initialTotalCount)")
            
            let resultAlert = NSAlert()
            if finalSpaceCount > initialSpaceCount {
                resultAlert.messageText = "空格键测试成功"
                resultAlert.informativeText = "捕获到 \(finalSpaceCount - initialSpaceCount) 个空格键事件"
                resultAlert.alertStyle = .informational
                print("[LOG] Space Key Test - SUCCESS: Space key capture is working")
            } else {
                resultAlert.messageText = "空格键测试失败"
                resultAlert.informativeText = "没有捕获到空格键事件，但捕获到 \(finalTotalCount - initialTotalCount) 个其他键事件"
                resultAlert.alertStyle = .warning
                print("[LOG] Space Key Test - FAILURE: Space key capture is not working")
            }
            resultAlert.addButton(withTitle: "确定")
            resultAlert.runModal()
        }
        
        print("[LOG] === Space Key Capture Test Completed ===")
    }
    
    // 重置统计计数器
    func resetEventCounters() {
        spaceKeyEventCount = 0
        totalKeyEventCount = 0
        lastEventTime = Date()
        lastSpaceKeyTime = Date.distantPast
        print("[LOG] Event counters reset")
    }
    
    // 强制触发健康检查
    func forceHealthCheck() {
        print("[LOG] Force health check requested")
        performHealthCheck()
    }

    func handleCmdA() {
        print("[LOG] Handling Cmd+A event")
        // 延迟检查，让 Cmd+A 操作完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // 通知 AXController 检查文本选择
            AXController.shared.checkForTextSelectionAfterKeyboardSelection()
        }
    }
} 
