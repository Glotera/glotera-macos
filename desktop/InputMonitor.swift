import Cocoa
import Carbon

class InputMonitor {
    // 移除独立的 eventTap 管理，改为依赖 AppDelegate
    private let triggerPattern = #"(.*?)[@#](id|en|zh|ja|jp|ko|fr|de|es|ru|th)\s*$"#
    private let regex: NSRegularExpression
    
    // 事件统计和业务逻辑相关属性
    private var lastEventTime: Date = Date()
    private var lastSpaceKeyTime: Date = Date()
    private var lastSpaceTime: Date? // 用于检测双击空格
    var spaceKeyEventCount = 0
    var totalKeyEventCount = 0
    private var lastTranslationTime: Date?
    private var lastSelectionTranslationTime: Date?
    
    // 防止死循环的标志
    private var isSendingEnterKey = false
    private var enterKeySentTime: Date?
    
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
        // 移除独立的健康检查，改为依赖 AppDelegate 的统一管理
        // AppDelegate 已经有 proactiveEventTapCheck 在每30秒检查 Event Tap 状态
        // InputMonitor 只需要关注业务逻辑层面的问题
        Logger.info("InputMonitor initialized - relying on AppDelegate for Event Tap health monitoring")
    }
    
    // 简化的业务逻辑检查（仅在需要时调用）
    private func checkBusinessLogicHealth() {
        let currentTime = Date()
        let timeSinceLastEvent = currentTime.timeIntervalSince(lastEventTime)
        
        // 检查权限（这是业务逻辑必需的）
        let hasPermissions = checkAccessibilityPermissions()
        if !hasPermissions {
            Logger.error("Accessibility permissions lost - business logic cannot function")
            return
        }
        
        // 检查空格键是否正常工作（业务逻辑相关）
        let timeSinceLastSpaceKey = currentTime.timeIntervalSince(lastSpaceKeyTime)
        let spaceKeyWorking = (spaceKeyEventCount > 0 && timeSinceLastSpaceKey < 300) || totalKeyEventCount < 10
        
        if !spaceKeyWorking && totalKeyEventCount > 100 {
            Logger.warn("Space key detection may not be working properly - \(spaceKeyEventCount) space events out of \(totalKeyEventCount) total events")
        }
        
        // 输出业务逻辑状态
        Logger.info("Business logic health: Events: \(totalKeyEventCount), Space: \(spaceKeyEventCount), Last event: \(Int(timeSinceLastEvent))s ago")
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
            let currentTime = Date()
            shared.lastEventTime = currentTime
            shared.totalKeyEventCount += 1
            
            // 每1000个事件输出一次调试信息
            if shared.totalKeyEventCount % 1000 == 0 {
                Logger.debug("Event callback: \(shared.totalKeyEventCount) events processed, last event time: \(currentTime)")
            }
            
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
        
        if !trusted {
            // 获取当前应用的Bundle ID和路径以便调试
            if let bundleId = Bundle.main.bundleIdentifier {
                Logger.info("Current Bundle ID: \(bundleId)")
            }
            let bundlePath = Bundle.main.bundlePath
            Logger.info("Current Bundle Path: \(bundlePath)")
        }
        
        return trusted
    }
    
    private func requestAccessibilityPermissions() { 
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let result = AXIsProcessTrustedWithOptions(options as CFDictionary)
        Logger.info("Permission request result: \(result)")
    }

    static let shared = InputMonitor()

    func handleSpaceKey() {
        let currentTime = Date()
        
        // 检查是否为双击空格
        if let lastTime = lastSpaceTime, currentTime.timeIntervalSince(lastTime) < 0.3 {
            // 这是第二次点击，重置计时器，避免三次或更多次点击连续触发
            self.lastSpaceTime = nil
            
            // 检查是否为AdsPower应用，如果是，则执行特殊逻辑
            if AXController.shared.isAdsPowerApp() {
                Logger.info("Double space in AdsPower, using clipboard-based detection.")
                DispatchQueue.global(qos: .userInitiated).async {
                    if let result = AXController.shared.detectTriggerViaClipboard() {
                        // 成功检测到触发词，启动翻译
                        DispatchQueue.main.async {
                            self.startTranslation(text: result.text, lang: result.lang)
                        }
                    } else {
                        // 未检测到触发词（误触），发送右箭头键恢复
                        Logger.info("AdsPower misfire detected. No trigger in clipboard. Recovering.")
                        DispatchQueue.main.async {
                             AXController.shared.postRightArrowKey()
                        }
                    }
                }
                return // AdsPower 逻辑结束
            }

            // --- 以下为非 AdsPower 应用的常规流程 ---
            Logger.info("Double space in standard app, checking for trigger characters.")
            
            // 检查：仅当文本中包含触发字符时才继续
            // TODO: 因为用户可以自定义指令，所以不能仅仅检测@#，需要检测所有指令
            guard let content = AXController.shared.getCurrentInputValue(),
                  (content.contains("@") || content.contains("#")) else {
                Logger.info("Ignoring double space in standard app: trigger character not found.")
                return
            }

            // 如果当前是终端应用，则直接忽略
            if AXController.shared.isTerminalApp() {
                Logger.info("Terminal app detected, ignoring space key trigger.")
                return
            }
            
            // 检查是否为特殊应用（如Discord）
            let isDiscord = isDiscordApp()
            
            // 添加更详细的调试信息
            if let frontmostApp = NSWorkspace.shared.frontmostApplication {
                let appName = frontmostApp.localizedName ?? "Unknown"
                let bundleId = frontmostApp.bundleIdentifier ?? "N/A"
                Logger.info("Space key triggered in \(appName) (\(bundleId)) - Discord: \(isDiscord)")
            }
            
            // 尝试获取焦点元素
            guard let _ = AXController.shared.getFocusedElement() else {
                Logger.error("No focused element found for non-AdsPower app.")
                return
            }
            
            // 首先尝试标准检测
            Logger.info("Starting standard trigger detection.")
            if let result = AXController.shared.detectTriggerAndExtract() { 
                Logger.info("Standard trigger detected: text='\(result.text)', lang='\(result.lang)'")
                startTranslation(text: result.text, lang: result.lang)
                return
            }
            
            Logger.warn("Standard detection failed, trying delayed detection...")
            // 如果标准检测失败，等待一小段时间后重试 (Discord需要更长的延迟)
            let delayTime = isDiscord ? 0.3 : 0.1
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delayTime) {
                Logger.info("Attempting delayed trigger detection (delay: \(delayTime)s)")
                if let result = AXController.shared.detectTriggerAndExtract() {
                    Logger.info("Delayed trigger detected: text='\(result.text)', lang='\(result.lang)'")
                    self.startTranslation(text: result.text, lang: result.lang)
                } else {
                    Logger.info("No trigger detected after delay.")
                }
            }
        } else {
            // 这是第一次点击，只记录时间
            self.lastSpaceTime = currentTime
            Logger.info("Single space detected, waiting for second space.")
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
        
        // 对于输入框翻译（空格键触发），需要在翻译开始前记录应用信息
        // 选中文本翻译已在 checkSelectedTextAndShowMenu 中记录了
        EnvironmentManager.shared.recordTriggerApp()
        
        // 标记自动翻译开始，用于后续过滤
        AXController.shared.markAutoTranslationStart(withText: text)
        
        // 获取当前焦点元素用于定位状态窗口
        let focusedElement = AXController.shared.getFocusedElement()
        
        // 获取当前焦点元素用于定位状态窗口
        let mouseLocation = NSEvent.mouseLocation
        // 显示翻译中状态
        TranslationStatusWindow.shared.showTranslating(near: focusedElement,mousePoint:mouseLocation)
        
        
        // 开始翻译（不禁用输入，避免死锁）
        TranslatorClient.shared.translate(text: text, to: lang) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let translated):
                    Logger.info("Translation result: \(translated)")
                    // 翻译成功后立即隐藏状态窗口，然后开始回填
                    TranslationStatusWindow.shared.hideStatus()
                    // print("[LOG] Status window hidden before auto-translation replacement")
                    // 回填翻译结果
                    AXController.shared.replaceInput(with: translated) {
                        Logger.info("Auto-translation replacement completed")
                        // 翻译完成后清除缓存的应用信息
                        EnvironmentManager.shared.clearTriggerAppInfo()
                    }
                case .failure(let error):
                    Logger.warn("Translation failed: \(error.localizedDescription)")
                    // 显示失败状态
                    TranslationStatusWindow.shared.showFailure()
                    // 翻译失败后也清除缓存的应用信息
                    EnvironmentManager.shared.clearTriggerAppInfo()
                }
            }
        }
    }

    func handleEnterKey() {
        Logger.info("Enter key detected (non-intercepted)")
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
            startTranslation(text: result.text, lang: result.lang)
        } else {
            // 对于Enter和Tab键，我们给更多时间让应用更新内容
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if let result = AXController.shared.detectTriggerAndExtract() {
                    Logger.info("Delayed trigger detected via \(source): text=\(result.text), lang=\(result.lang)")
                    self.startTranslation(text: result.text, lang: result.lang)
                }
            }
        }
    }

    // 检查是否应该拦截回车键进行翻译 - 优化版本
    func shouldInterceptEnter() -> Bool {
        // 首先检查用户是否启用了Return键拦截功能
        guard ConfigManager.shared.isReturnKeyInterceptionEnabled() else {
            Logger.info("Return key interception is disabled in settings")
            return false
        }
        
        // 只在聊天软件中启用回车键拦截功能
        guard isChatApplication() else {
            Logger.info("Return key interception disabled - not a chat application")
            return false
        }
        
        // 防止拦截我们自己发送的Enter键
        if isSendingEnterKey {
            Logger.info("Ignoring Enter key - we are currently sending one")
            return false
        }
        
        // 如果最近刚发送过Enter键，也忽略（防止时序问题）
        if let sentTime = enterKeySentTime,
           Date().timeIntervalSince(sentTime) < 1.0 {
            Logger.info("Ignoring Enter key - recently sent one")
            return false
        }
        
        // 使用缓存的最后一次空格键事件时间来决定是否需要检查
        let timeSinceLastSpace = Date().timeIntervalSince(lastSpaceKeyTime) 
        
        // 快速检查当前输入内容是否包含触发器
        guard let focused = AXController.shared.getFocusedElement(),
              let value = AXController.shared.getValue(of: focused) else {
            return false
        } 
        
        // 如果最近通过菜单进行了划词翻译，不拦截回车
        if let selectionTime = lastSelectionTranslationTime, Date().timeIntervalSince(selectionTime) < 2.0 {
            return false
        }
        
        // 如果是终端应用，不拦截回车
        if AXController.shared.isTerminalApp() {
            return false
        }
        
        // 检查当前输入框内容是否有触发词
        if let focused = AXController.shared.getFocusedElement(),
           let value = AXController.shared.getValue(of: focused) {
            // 简单检查是否包含语言代码的前缀字符
            // let content = value.lowercased()
            // if !content.contains("@") && !content.contains("#") && !content.contains(" ") {
            //     return false
            // }
            
            // // 检查常见的语言代码模式
            // let quickPatterns = ["@en", "#en", "@zh", "#zh", "@id", "#id", " en ", " zh ", " id "]
            // for pattern in quickPatterns {
            //     if content.contains(pattern) {
            //         return true
            //     }
            // }
            
            return true
        }
        
        return false
    }
    
    // 处理被拦截的回车键
    func handleInterceptedEnter() {
        Logger.info("Handling intercepted Enter key")
        
        if let result = AXController.shared.detectTriggerAndExtract() {
            Logger.info("Trigger detected via intercepted Enter: text=\(result.text), lang=\(result.lang)")
            
            // 开始翻译，完成后自动发送
            startTranslationWithAutoSend(text: result.text, lang: result.lang)
        } else {
            Logger.warn("No trigger found, sending original Enter key")
            // 如果没有检测到触发器，发送原始回车键
            sendEnterKey()
        }
    }
    
    // 翻译完成后自动发送
    private func startTranslationWithAutoSend(text: String, lang: String) {
        // 对于输入框翻译（回车键触发），需要在翻译开始前记录应用信息
        // 选中文本翻译已在 checkSelectedTextAndShowMenu 中记录了
        EnvironmentManager.shared.recordTriggerApp()
        
        // 标记自动翻译开始，用于后续过滤
        AXController.shared.markAutoTranslationStart(withText: text)
        
        // 获取当前焦点元素用于定位状态窗口
        let focusedElement = AXController.shared.getFocusedElement()
        
        // 获取当前焦点元素用于定位状态窗口
        let mouseLocation = NSEvent.mouseLocation
        // 显示翻译中状态
        TranslationStatusWindow.shared.showTranslating(near: focusedElement,mousePoint:mouseLocation)
        
        
        // 开始翻译（不禁用输入，避免死锁）
        TranslatorClient.shared.translate(text: text, to: lang) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let translated):
                    Logger.info("Translation result: \(translated)")
                    // 翻译成功后立即隐藏状态窗口，然后开始回填
                    TranslationStatusWindow.shared.hideStatus() 
                    // 回填翻译结果，完成后发送回车键
                    AXController.shared.replaceInput(with: translated) {
                        Logger.info("Auto-translation with send completed")
                        
                        // 根据不同应用调整延迟时间
                        let isWeChat = self?.isWeChatApp() ?? false
                        let delay = isWeChat ? 0.05 : 0.05  // 稍微延迟，确保内容完全更新
                        
                        Logger.info("Waiting \(delay)s before sending Enter key (WeChat: \(isWeChat))")
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            self?.sendEnterKey()
                            // 翻译完成后清除缓存的应用信息
                            EnvironmentManager.shared.clearTriggerAppInfo()
                        }
                    }
                case .failure(let error):
                    Logger.warn("Translation failed: \(error.localizedDescription)")
                    // 显示失败状态
                    TranslationStatusWindow.shared.showFailure()
                    // 翻译失败时发送原始内容
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self?.sendEnterKey()
                        // 翻译失败后也清除缓存的应用信息
                        EnvironmentManager.shared.clearTriggerAppInfo()
                    }
                }
            }
        }
    }
    
    // 发送回车键事件
    private func sendEnterKey() {
        Logger.info("Sending Enter key event")
        
        // 设置标志防止拦截我们自己发送的Enter键
        isSendingEnterKey = true
        enterKeySentTime = Date()
        
        // 检查是否为微信，微信需要特殊处理
        let isWeChat = isWeChatApp()
        
        if isWeChat {
            // 微信需要特殊处理：确保焦点正确且使用适当的事件发送方式
            sendEnterKeyForWeChat()
        } else {
            // 其他应用（包括Discord、钉钉等）使用标准方式
            sendEnterKeyStandard()
        }
        
        // 延迟清除标志，确保Enter键事件已经处理完毕
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isSendingEnterKey = false
            Logger.info("Enter key sending flag cleared")
        }
    }
    
    // 微信专用的Enter键发送
    private func sendEnterKeyForWeChat() {
        Logger.info("Sending Enter key for WeChat")
        
        // 确保微信窗口获得焦点
        ensureWeChatFocus { focused in
            guard focused else {
                Logger.warn("WeChat: Failed to ensure focus for Enter key")
                return
            }
            
            // 等待焦点稳定后发送Enter键
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                // 使用最直接有效的方法发送Enter键
                self.sendWeChatEnterKeyDirect()
            }
        }
    }
    
    // 直接发送微信Enter键的优化方法
    private func sendWeChatEnterKeyDirect() {
        Logger.info("WeChat: Sending Enter key directly")
        
        // 先验证输入框内容是否已更新（可选的安全检查）
        if let focused = AXController.shared.getFocusedElement(),
           let currentContent = AXController.shared.getValue(of: focused) {
            Logger.info("WeChat: Current input content before Enter: '\(currentContent)'")
        }
        return  self.sendWeChatEnterKeyViaCGEvent()
    
        // 使用AppleScript是最可靠的方法，因为它直接与系统事件交互
        let script = """
        tell application "System Events"
            tell process "WeChat"
                key code 36
            end tell
        end tell
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            if error == nil {
                Logger.info("WeChat: Enter key sent successfully via AppleScript")
            } else {
                Logger.warn("WeChat: AppleScript failed: \(error?.description ?? "Unknown error"), trying CGEvent")
                // 如果AppleScript失败，回退到CGEvent方法
                self.sendWeChatEnterKeyViaCGEvent()
            }
        } else {
            Logger.warn("WeChat: Failed to create AppleScript, trying CGEvent")
            self.sendWeChatEnterKeyViaCGEvent()
        }
    }
    
    // 使用CGEvent发送微信Enter键（备用方法）
    private func sendWeChatEnterKeyViaCGEvent() {
        Logger.info("WeChat: Sending Enter key via CGEvent")
        
        let source = CGEventSource(stateID: .hidSystemState)
        if let enterKeyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: true),
           let enterKeyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: false) {
            
            // 设置事件标志以确保微信能够识别
            enterKeyDown.flags = []
            enterKeyUp.flags = []
            
            // 发送按下事件
            enterKeyDown.post(tap: .cghidEventTap)
            
            // 稍微延迟后发送释放事件
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                enterKeyUp.post(tap: .cghidEventTap)
                Logger.info("WeChat: Enter key sent via CGEvent")
            }
        } else {
            Logger.error("WeChat: Failed to create CGEvent Enter key events")
        }
    }
    

    
    // 标准的Enter键发送
    private func sendEnterKeyStandard() {
        Logger.info("Sending Enter key (standard method)")
        
        let source = CGEventSource(stateID: .hidSystemState)
        if let enterKeyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: true),
           let enterKeyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: false) {
            
            enterKeyDown.post(tap: .cghidEventTap)
            enterKeyUp.post(tap: .cghidEventTap)
            Logger.info("Standard: Enter key sent successfully")
        }
    }
    
    // 确保微信应用获得焦点
    private func ensureWeChatFocus(completion: @escaping (Bool) -> Void) {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier,
              bundleId.contains("wechat") || bundleId.contains("WeChat") else {
            Logger.warn("WeChat: Not currently the frontmost application")
            completion(false)
            return
        }
        
        // 微信已经是前台应用，直接成功
        Logger.info("WeChat: Already focused")
        completion(true)
    }
    
    // 检查当前应用是否为聊天软件
    private func isChatApplication() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        }
        
        // 常见聊天软件的Bundle ID列表
        let chatAppBundleIds = [
            // 微信
            "com.tencent.xinWeChat",
            "com.tencent.WeChat",
            "com.tencent.wechat",
            
            // Discord
            "com.hnc.Discord",
            "com.discord.Discord",
            
            // 钉钉
            "com.alibaba.DingTalkMac",
            "com.laiwang.DingTalk",
            
            // 企业微信
            "com.tencent.WeWorkMac",
            "com.tencent.wework",
            
            // QQ
            "com.tencent.qq",
            "com.tencent.QQ",
            
            // Telegram
            "ru.keepcoder.Telegram",
            "org.telegram.desktop",
            
            // Slack
            "com.tinyspeck.slackmacgap",
            
            // WhatsApp
            "net.whatsapp.WhatsApp",
            "WhatsApp",
            
            // Skype
            "com.skype.skype",
            
            // Microsoft Teams
            "com.microsoft.teams",
            "com.microsoft.teams2",
            
            // Zoom Chat
            "us.zoom.xos",
            
            // Line
            "jp.naver.line.mac",
            
            // Messenger
            "com.facebook.archon.developerID",
            "com.facebook.Messenger",
            
            // Signal
            "org.whispersystems.signal-desktop",
            
            // Element (Matrix)
            "im.riot.app",
            "io.element.Element",
            
            // Mattermost
            "Mattermost.Desktop",
            
            // Rocket.Chat
            "chat.rocket.desktop"
        ]
        
        // 检查精确匹配
        if chatAppBundleIds.contains(bundleId) {
            Logger.info("Chat app detected (exact match): \(frontmostApp.localizedName ?? "Unknown") (\(bundleId))")
            return true
        }
        
        // 检查模糊匹配（包含关键词）
        let chatKeywords = [
            "wechat", "discord", "dingtalk", "telegram", "slack", 
            "whatsapp", "skype", "teams", "zoom", "line", 
            "messenger", "signal", "element", "mattermost", "rocket"
        ]
        
        let bundleIdLower = bundleId.lowercased()
        for keyword in chatKeywords {
            if bundleIdLower.contains(keyword) {
                Logger.info("Chat app detected (keyword match): \(frontmostApp.localizedName ?? "Unknown") (\(bundleId)) - keyword: \(keyword)")
                return true
            }
        }
        
        Logger.debug("Not a chat application: \(frontmostApp.localizedName ?? "Unknown") (\(bundleId))")
        return false
    }
    
    // 检查当前应用是否为微信
    private func isWeChatApp() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        }
        
        // 微信的Bundle ID通常是com.tencent.xinWeChat
    
        let wechatBundleIds = [
            "com.tencent.xinWeChat",  // 官方微信
            "com.tencent.WeChat",     // 可能的变体
            "com.tencent.wechat"      // 可能的变体
        ]
        
        let isWeChat = wechatBundleIds.contains(bundleId) || 
                      bundleId.lowercased().contains("wechat")
        
        if isWeChat {
            Logger.info("WeChat detected with Bundle ID: \(bundleId)")
        }
        
        return isWeChat
    }
    
    // 手动测试触发器检测（用于调试）
    func manualTriggerTest() {
        Logger.info("=== Manual Trigger Test Started ===")
        
        // 检查权限
        let hasPermissions = checkAccessibilityPermissions()
        Logger.info("Test - Accessibility permissions: \(hasPermissions)")
        
        // 检查事件监听器
        let eventTapValid = appDelegate?.isEventTapValid() ?? false
        Logger.info("Test - Event tap valid: \(eventTapValid)")
        
        // 检查焦点元素
        if let focused = AXController.shared.getFocusedElement() {
            Logger.info("Test - Focused element found")
            
            // 尝试获取内容
            if let value = AXController.shared.getValue(of: focused) {
                Logger.info("Test - Current content: '\(value)'")
                Logger.info("Test - Content length: \(value.count)")
                
                // 测试触发器检测
                if let result = AXController.shared.detectTriggerAndExtract() {
                    Logger.info("Test - Trigger detected: text='\(result.text)', lang='\(result.lang)'")
                } else {
                    Logger.info("Test - No trigger detected")
                    
                    // 检查是否包含常见模式
                    let testPatterns = ["@en", "#en", "@zh", "#zh"]
                    for pattern in testPatterns {
                        if value.lowercased().contains(pattern) {
                            Logger.info("Test - Found '\(pattern)' in content but not detected as trigger")
                        }
                    }
                }
            } else {
                Logger.info("Test - Cannot get value from focused element")
            }
        } else {
            Logger.info("Test - No focused element found")
        }
        
        Logger.info("=== Manual Trigger Test Completed ===")
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
    
    // 获取距离上次选中翻译的时间间隔
    func getTimeSinceLastSelectionTranslation() -> TimeInterval {
        guard let lastTime = lastSelectionTranslationTime else {
            return Double.infinity
        }
        return Date().timeIntervalSince(lastTime)
    }
    
    // 标记选中文本翻译开始（由 TranslationMenuWindow 调用）
    func markSelectionTranslationStart() {
        lastSelectionTranslationTime = Date()
        Logger.debug("Marked selection translation start")
    }

    // 专门的Discord测试方法
    func testDiscordTrigger() {
        Logger.info("=== Discord Trigger Test Started ===")
        
        // 检查是否在Discord中
        let isDiscord = isDiscordApp()
        Logger.info("Discord Test - Is Discord app: \(isDiscord)")
        
        if !isDiscord {
            Logger.warn("Discord Test - Warning: Not currently in Discord app")
        }
        
        // 检查基本状态
        let hasPermissions = checkAccessibilityPermissions()
        Logger.info("Discord Test - Accessibility permissions: \(hasPermissions)")
        
        let eventTapValid = appDelegate?.isEventTapValid() ?? false
        Logger.info("Discord Test - Event tap valid: \(eventTapValid)")
        
        // 检查焦点元素
        if let focused = AXController.shared.getFocusedElement() {
            Logger.info("Discord Test - Focused element found")
            
            // 尝试获取内容
            if let value = AXController.shared.getValue(of: focused) {
                Logger.info("Discord Test - Current content: '\(value)'")
                Logger.info("Discord Test - Content length: \(value.count)")
                
                // 测试预处理
                let isDiscordOrChat = AXController.shared.isDiscordOrChatApp()
                Logger.info("Discord Test - Detected as chat app: \(isDiscordOrChat)")
                
                // 测试触发器检测
                if let result = AXController.shared.detectTriggerAndExtract() {
                    Logger.info("Discord Test - Trigger detected: text='\(result.text)', lang='\(result.lang)'")
                } else {
                    Logger.info("Discord Test - No trigger detected")
                    
                    // 检查常见模式
                    let testPatterns = ["@en", "#en", "@zh", "#zh"]
                    for pattern in testPatterns {
                        if value.lowercased().contains(pattern) {
                            Logger.info("Discord Test - Found '\(pattern)' in content but not detected as trigger")
                            Logger.info("Discord Test - Raw content: '\(value)'")
                            Logger.info("Discord Test - Lowercased: '\(value.lowercased())'")
                        }
                    }
                }
            } else {
                Logger.info("Discord Test - Cannot get value from focused element")
            }
        } else {
            Logger.info("Discord Test - No focused element found")
        }
        
        Logger.info("=== Discord Trigger Test Completed ===")
    }

    // 专门测试空格键捕获
    func testSpaceKeyCapture() {
        Logger.info("=== Space Key Capture Test Started ===")
        
        let initialSpaceCount = spaceKeyEventCount
        let initialTotalCount = totalKeyEventCount
        
        Logger.info("Space Key Test - Initial space key count: \(initialSpaceCount)")
        Logger.info("Space Key Test - Initial total key count: \(initialTotalCount)")
        Logger.info("Space Key Test - Event tap valid: \(appDelegate?.isEventTapValid() ?? false)")
        
        // 提示用户按空格键
        let alert = NSAlert()
        alert.messageText = "Space Key Test"
        alert.informativeText = "Please press the space key in any input field a few times, then click the 'Complete Test' button.\n\nCurrent space key event count: \(spaceKeyEventCount)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Complete Test")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // 检查空格键事件是否增加
            let finalSpaceCount = spaceKeyEventCount
            let finalTotalCount = totalKeyEventCount
            
            Logger.info("Space Key Test - Final space key count: \(finalSpaceCount)")
            Logger.info("Space Key Test - Final total key count: \(finalTotalCount)")
            Logger.info("Space Key Test - Space key events captured: \(finalSpaceCount - initialSpaceCount)")
            Logger.info("Space Key Test - Total key events captured: \(finalTotalCount - initialTotalCount)")
            
            let resultAlert = NSAlert()
            if finalSpaceCount > initialSpaceCount {
                resultAlert.messageText = "Space Key Test Success"
                resultAlert.informativeText = "Captured \(finalSpaceCount - initialSpaceCount) space key events"
                resultAlert.alertStyle = .informational
                Logger.info("Space Key Test - SUCCESS: Space key capture is working")
            } else {
                resultAlert.messageText = "Space Key Test Failed"
                resultAlert.informativeText = "No space key events captured, but captured \(finalTotalCount - initialTotalCount) other key events"
                resultAlert.alertStyle = .warning
                Logger.info("Space Key Test - FAILURE: Space key capture is not working")
            }
            resultAlert.addButton(withTitle: "OK")
            resultAlert.runModal()
        }
        
        Logger.info("=== Space Key Capture Test Completed ===")
    }
    
    // 重置统计计数器
    func resetEventCounters() {
        spaceKeyEventCount = 0
        totalKeyEventCount = 0
        lastEventTime = Date()
        lastSpaceKeyTime = Date()
        Logger.info("Event counters reset")
    }
    
    // 强制触发业务逻辑检查
    func forceBusinessLogicCheck() {
        Logger.info("Force business logic check requested")
        checkBusinessLogicHealth()
    }

    func handleCmdA() {
        Logger.info("Handling Cmd+A event")
        // 延迟检查，让 Cmd+A 操作完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // 通知 AXController 检查文本选择
            AXController.shared.checkForTextSelectionAfterKeyboardSelection()
        }
    }
    
    // 测试微信Enter键发送功能
    func testWeChatEnterKey() {
        Logger.info("=== WeChat Enter Key Test Started ===")
        
        let isWeChat = isWeChatApp()
        Logger.info("WeChat Test - Is WeChat app: \(isWeChat)")
        
        if !isWeChat {
            Logger.warn("WeChat Test - Warning: Not currently in WeChat app")
            
            // 显示当前应用信息
            if let frontmostApp = NSWorkspace.shared.frontmostApplication,
               let bundleId = frontmostApp.bundleIdentifier {
                Logger.info("WeChat Test - Current app: \(frontmostApp.localizedName ?? "Unknown") (\(bundleId))")
            }
            
            let alert = NSAlert()
            alert.messageText = "WeChat Enter Key Test"
            alert.informativeText = "Please switch to WeChat app first, then run this test again."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        
        // 提示用户准备测试
        let alert = NSAlert()
        alert.messageText = "WeChat Enter Key Test"
        alert.informativeText = "Please:\n1. Open a WeChat chat window\n2. Type some text in the input field\n3. Click 'Test Enter Key' to simulate sending\n\nThis will test if the Enter key sending works correctly."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Test Enter Key")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            Logger.info("WeChat Test - Starting Enter key test")
            sendEnterKey()
            
            // 显示测试结果
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                let resultAlert = NSAlert()
                resultAlert.messageText = "WeChat Enter Key Test"
                resultAlert.informativeText = "Enter key has been sent. Did the message get sent in WeChat?\n\nCheck the Console.app logs for detailed information."
                resultAlert.alertStyle = .informational
                resultAlert.addButton(withTitle: "OK")
                resultAlert.runModal()
            }
        }
        
        Logger.info("=== WeChat Enter Key Test Completed ===")
    }
    
    // 测试Enter键死循环问题
    func testEnterKeyLoop() {
        Logger.info("=== Enter Key Loop Test Started ===")
        
        Logger.info("Current state:")
        Logger.info("- isSendingEnterKey: \(isSendingEnterKey)")
        Logger.info("- enterKeySentTime: \(enterKeySentTime?.description ?? "nil")")
        
        let alert = NSAlert()
        alert.messageText = "Enter Key Loop Test"
        alert.informativeText = "This test will simulate sending an Enter key to check for infinite loops.\n\nWatch the console logs to see if the Enter key sending stops properly."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Test Enter Key")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            Logger.info("Testing Enter key loop prevention...")
            
            // 模拟发送Enter键
            sendEnterKey()
            
            // 延迟显示结果
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                Logger.info("Final state:")
                Logger.info("- isSendingEnterKey: \(self.isSendingEnterKey)")
                Logger.info("- enterKeySentTime: \(self.enterKeySentTime?.description ?? "nil")")
                
                let resultAlert = NSAlert()
                resultAlert.messageText = "Enter Key Loop Test"
                resultAlert.informativeText = "Test completed. Check Console.app for detailed logs.\n\nIf you see repeated 'Sending Enter key event' messages, there's still a loop issue."
                resultAlert.alertStyle = .informational
                resultAlert.addButton(withTitle: "OK")
                resultAlert.runModal()
            }
        }
        
        Logger.info("=== Enter Key Loop Test Completed ===")
    }
    
    // 测试聊天应用检测功能
    func testChatAppDetection() {
        Logger.info("=== Chat App Detection Test Started ===")
        
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            Logger.warn("Chat App Test - No frontmost application found")
            return
        }
        
        let appName = frontmostApp.localizedName ?? "Unknown"
        let isChatApp = isChatApplication()
        let shouldInterceptEnter = shouldInterceptEnter()
        
        Logger.info("Chat App Test - Current application: \(appName)")
        Logger.info("Chat App Test - Bundle ID: \(bundleId)")
        Logger.info("Chat App Test - Detected as chat app: \(isChatApp)")
        Logger.info("Chat App Test - Should intercept Enter: \(shouldInterceptEnter)")
        Logger.info("Chat App Test - Return key interception enabled: \(ConfigManager.shared.isReturnKeyInterceptionEnabled())")
        
        // 显示测试结果
        let alert = NSAlert()
        alert.messageText = "Chat App Detection Test"
        alert.informativeText = """
        Current App: \(appName)
        Bundle ID: \(bundleId)
        
        Is Chat App: \(isChatApp ? "✅ Yes" : "❌ No")
        Should Intercept Enter: \(shouldInterceptEnter ? "✅ Yes" : "❌ No")
        
        Return Key Interception Setting: \(ConfigManager.shared.isReturnKeyInterceptionEnabled() ? "✅ Enabled" : "❌ Disabled")
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
        
        Logger.info("=== Chat App Detection Test Completed ===")
    }
} 
