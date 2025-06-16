import Cocoa
import Carbon

class InputMonitor {
    private var eventTap: CFMachPort?
    private let triggerPattern = #"(.*?)[@#](id|en|zh|ja|jp|ko|fr|de|es|ru|th)\s*$"#
    private let regex: NSRegularExpression
    
    // 添加健康检查相关属性
    private var lastEventTime: Date = Date()
    private var lastSpaceKeyTime: Date = Date.distantPast
    private var healthCheckTimer: Timer?
    private var eventTapEnabled = false
    private var spaceKeyEventCount = 0
    private var totalKeyEventCount = 0

    init() {
        regex = try! NSRegularExpression(pattern: triggerPattern, options: .caseInsensitive)
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
    private func performHealthCheck() {
        print("[LOG] Performing health check...")
        
        // 检查权限状态
        let hasPermissions = checkAccessibilityPermissions()
        print("[LOG] Health check - Accessibility permissions: \(hasPermissions)")
        
        // 检查事件监听器状态
        let eventTapValid = eventTap != nil && CFMachPortIsValid(eventTap!)
        print("[LOG] Health check - Event tap valid: \(eventTapValid)")
        
        // 检查最近是否有事件活动
        let timeSinceLastEvent = Date().timeIntervalSince(lastEventTime)
        let timeSinceLastSpaceKey = Date().timeIntervalSince(lastSpaceKeyTime)
        print("[LOG] Health check - Time since last event: \(timeSinceLastEvent)s")
        print("[LOG] Health check - Time since last space key: \(timeSinceLastSpaceKey)s")
        print("[LOG] Health check - Total key events: \(totalKeyEventCount)")
        print("[LOG] Health check - Space key events: \(spaceKeyEventCount)")
        
        // 检查空格键事件是否被正常捕获
        let spaceKeyWorking = timeSinceLastSpaceKey < 300 || spaceKeyEventCount == 0 // 5分钟内有空格键或者刚启动
        if !spaceKeyWorking && totalKeyEventCount > 10 {
            print("[LOG] Health check - WARNING: Space key events may not be captured properly")
            print("[LOG] Health check - Total events: \(totalKeyEventCount), Space events: \(spaceKeyEventCount)")
        }
        
        // 如果权限丢失或事件监听器失效，尝试重新启动
        if !hasPermissions || !eventTapValid {
            print("[LOG] Health check failed - attempting to restart event monitoring")
            restartEventMonitoring()
        }
        
        // 如果空格键长时间没有被捕获但其他键有，可能是事件过滤问题
        if !spaceKeyWorking && totalKeyEventCount > 50 {
            print("[LOG] Health check - Space key capture issue detected, restarting event monitoring")
            restartEventMonitoring()
        }
        
        // 测试焦点元素获取
        if let focused = AXController.shared.getFocusedElement() {
            print("[LOG] Health check - Focused element available")
            if let value = AXController.shared.getValue(of: focused) {
                print("[LOG] Health check - Can get value from focused element: \(value.count) chars")
            } else {
                print("[LOG] Health check - Cannot get value from focused element")
            }
        } else {
            print("[LOG] Health check - No focused element found")
        }
    }
    
    // 重启事件监听
    private func restartEventMonitoring() {
        print("[LOG] Restarting event monitoring...")
        
        // 清理旧的事件监听器
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
            eventTapEnabled = false
        }
        
        // 重新创建事件监听器
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let newEventTap = self.startMonitoringAndReturnEventTap()
            if newEventTap != nil {
                print("[LOG] Event monitoring restarted successfully")
            } else {
                print("[LOG] Failed to restart event monitoring")
            }
        }
    }

    func startMonitoringAndReturnEventTap() -> CFMachPort? {
        print("[LOG] InputMonitor startMonitoring called")
        
        // Check accessibility permissions first
        if !checkAccessibilityPermissions() {
            print("[LOG] Accessibility permissions not granted")
            requestAccessibilityPermissions()
            return nil
        }
        
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                // 更新最后事件时间
                InputMonitor.shared.lastEventTime = Date()
                InputMonitor.shared.totalKeyEventCount += 1
                
                if type == .keyDown {
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    
                    if keyCode == kVK_Space { // 空格键
                        InputMonitor.shared.lastSpaceKeyTime = Date()
                        InputMonitor.shared.spaceKeyEventCount += 1
                        print("[LOG] Space key event detected (count: \(InputMonitor.shared.spaceKeyEventCount))")
                        DispatchQueue.main.async {
                            InputMonitor.shared.handleSpaceKey()
                        }
                    } else if keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter { // 回车键
                        // 检查是否需要翻译，如果需要则阻止回车事件
                        if InputMonitor.shared.shouldInterceptEnter() {
                            print("[LOG] Intercepting Enter key for translation")
                            DispatchQueue.main.async {
                                InputMonitor.shared.handleInterceptedEnter()
                            }
                            return nil // 阻止回车事件
                        }
                    } else if keyCode == kVK_Tab { // Tab键
                        DispatchQueue.main.async {
                            InputMonitor.shared.handleTabKey()
                        }
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        )
        
        if eventTap == nil {
            print("[LOG] Failed to create event tap - this usually indicates:")
            print("[LOG] 1. Accessibility permissions not granted")
            print("[LOG] 2. App Sandbox restrictions")
            print("[LOG] 3. System security settings blocking access")
            eventTapEnabled = false
        } else {
            eventTapEnabled = true
            print("[LOG] Event tap created successfully")
        }
        
        return eventTap
    }
    
    private func checkAccessibilityPermissions() -> Bool {
        let trusted = AXIsProcessTrusted()
        print("[LOG] Accessibility permission check result: \(trusted)")
        
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
        print("[LOG] Space key detected - starting trigger detection")
        
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
            print("[LOG] Trigger detected: text=\(result.text), lang=\(result.lang)")
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
                print("[LOG] No trigger detected in input after delay")
                // 添加更多诊断信息
                if let value = AXController.shared.getValue(of: focused) {
                    print("[LOG] Current input content for diagnosis: '\(value)'")
                    print("[LOG] Content length: \(value.count)")
                    
                    // 检查是否包含我们期望的模式
                    let patterns = ["@en", "#en", "@zh", "#zh", "@id", "#id"]
                    for pattern in patterns {
                        if value.lowercased().contains(pattern) {
                            print("[LOG] Found pattern '\(pattern)' in content but regex didn't match")
                            break
                        }
                    }
                } else {
                    print("[LOG] Cannot get value from focused element")
                }
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
                    print("[LOG] Status window hidden before auto-translation replacement")
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
        print("[LOG] Tab key detected")
        // Tab键可能在某些应用中完成自动补全，然后触发翻译
        attemptTriggerDetection(source: "Tab")
    }
    
    private func attemptTriggerDetection(source: String) {
        if let result = AXController.shared.detectTriggerAndExtract() {
            print("[LOG] Trigger detected via \(source): text=\(result.text), lang=\(result.lang)")
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

    // 检查是否应该拦截回车键进行翻译
    func shouldInterceptEnter() -> Bool {
        // 快速检查当前输入内容是否包含触发器
        guard let focused = AXController.shared.getFocusedElement(),
              let value = AXController.shared.getValue(of: focused) else {
            return false
        }
        
        // 简单检查是否包含语言代码
        let supportedLangs = ["id", "en", "zh", "ja", "jp", "ko", "fr", "de", "es", "ru", "th"]
        let content = value.lowercased()
        
        for lang in supportedLangs {
            if content.contains(" \(lang) ") || content.hasSuffix(" \(lang)") || 
               content.contains("@\(lang)") || content.contains("#\(lang)") {
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
        let eventTapValid = eventTap != nil && CFMachPortIsValid(eventTap!)
        print("[LOG] Test - Event tap valid: \(eventTapValid)")
        print("[LOG] Test - Event tap enabled: \(eventTapEnabled)")
        
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
        status += "- Event Tap Valid: \(eventTap != nil && CFMachPortIsValid(eventTap!))\n"
        status += "- Event Tap Enabled: \(eventTapEnabled)\n"
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
        
        let eventTapValid = eventTap != nil && CFMachPortIsValid(eventTap!)
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
        print("[LOG] Space Key Test - Event tap valid: \(eventTap != nil && CFMachPortIsValid(eventTap!))")
        print("[LOG] Space Key Test - Event tap enabled: \(eventTapEnabled)")
        
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
} 