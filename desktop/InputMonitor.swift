import Cocoa
import Carbon
import CryptoKit

/// 翻译结果缓存项
struct TranslationCacheItem {
    let originalText: String
    let translatedText: String
    let sourceLanguage: String?
    let targetLanguage: String
    let timestamp: Date
    let translatedTextHash: String
    
    /// 检查缓存是否已过期（5分钟有效期）
    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > 300 // 5分钟 = 300秒
    }
    
    init(originalText: String, translatedText: String, sourceLanguage: String?, targetLanguage: String) {
        self.originalText = originalText
        self.translatedText = translatedText
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.timestamp = Date()
        self.translatedTextHash = Self.calculateHash(translatedText)
    }
    
    /// 计算文本的SHA256哈希值
    static func calculateHash(_ text: String) -> String {
        let data = text.data(using: .utf8) ?? Data()
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

class InputMonitor {
    // 移除独立的 eventTap 管理，改为依赖 AppDelegate
    private let triggerPattern = #"(.*?)[@#](id|en|zh|ja|jp|ko|fr|de|es|ru|th)\s*$"#
    private let regex: NSRegularExpression
    
    // 翻译缓存相关
    private var translationCache: [String: TranslationCacheItem] = [:]
    private let cacheQueue = DispatchQueue(label: "com.glotera.translation-cache", attributes: .concurrent)
    
    // 事件统计和业务逻辑相关属性
    private var lastEventTime: Date = Date()
    private var lastSpaceKeyTime: Date = Date()
    private var lastSpaceTime: Date? // 用于检测双击空格
    private var lastSpaceKeyEventCount: Int = 0 // 记录第一次空格时的键盘事件计数
    private var keyEventsBetweenSpaces: [Int] = [] // 记录两次空格之间的键盘事件类型
    var spaceKeyEventCount = 0
    var totalKeyEventCount = 0
    private var lastTranslationTime: Date?
    private var lastSelectionTranslationTime: Date?
    // Using translation cache for consistency; no extra state needed for Enter bypass
    
    // MARK: - App Detection Caching
    private var cachedAppInfo: (bundleId: String, isChat: Bool, isWeChat: Bool, isDiscord: Bool, timestamp: Date)?
    private let appCacheTTL: TimeInterval = 30.0 // Cache app detection for 30 seconds
    

    
    // 添加 AppDelegate 引用以便统一管理
    private weak var appDelegate: AppDelegate?

    init() {
        regex = try! NSRegularExpression(pattern: triggerPattern, options: .caseInsensitive)
        // 获取 AppDelegate 引用
        appDelegate = NSApp.delegate as? AppDelegate
        
        // Set up app switching observer to clear cache
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidActivate),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        
        startHealthCheck()
        startPeriodicCacheCleanup()
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
            
            // 处理 Event Tap 被禁用的情况 - 优化恢复机制
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                let disableReason = type == .tapDisabledByTimeout ? "timeout" : "user input"
                Logger.warn("Event tap disabled by \(disableReason), attempting immediate recovery")
                
                // 快速尝试重新启用，不阻塞回调
                if let appDelegate = InputMonitor.shared.appDelegate {
                    let recovered = appDelegate.quickEnableEventTap()
                    if recovered {
                        Logger.info("Event tap quick recovery successful")
                    } else {
                        // 只有在快速恢复失败时才异步处理完整重启
                        Logger.warn("Quick recovery failed, scheduling full restart")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            InputMonitor.shared.appDelegate?.restartEventMonitoring()
                        }
                    }
                }
                return Unmanaged.passUnretained(event)
            }
            
            // 事件过滤：过滤掉自己发送的模拟事件
            if InputManager.shared.isEventSimulated(event) {
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                Logger.info("Filtered out simulated event (keyCode: \(keyCode), flags: \(flags))")
                return Unmanaged.passUnretained(event)
            }
            
            // 检查是否正在发送模拟事件（额外的安全检查）
            // if InputManager.shared.isSendingSimulatedEvent() {
            //     Logger.warn("Skipping event processing - currently sending simulated events")
            //     return Unmanaged.passUnretained(event)
            // }
            
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
                
                // 记录空格之间的键盘事件
                if shared.lastSpaceTime != nil {
                    shared.keyEventsBetweenSpaces.append(Int(keyCode))
                }
                
                if keyCode == kVK_Space { // 空格键
                    shared.lastSpaceKeyTime = currentTime
                    shared.spaceKeyEventCount += 1
                    
                    // 重要：直接在事件回调中处理时间敏感的双击检测
                    // 避免异步调度导致的时序问题，使用严格的时间检查
                    let isDoubleSpace = shared.lastSpaceTime != nil && 
                                      currentTime.timeIntervalSince(shared.lastSpaceTime!) < 0.4 &&
                                      currentTime.timeIntervalSince(shared.lastSpaceTime!) > 0.05 // 避免过快的重复检测
                    
                    if isDoubleSpace {
                        // 双击空格：立即标记并异步处理，但保持时序准确性
                        print(" ")
                        Logger.info("===========================================")
                        Logger.debug("Double space detected in callback (interval: \(String(format: "%.3f", currentTime.timeIntervalSince(shared.lastSpaceTime!)))s)")
                        shared.lastSpaceTime = nil // 立即重置避免重复触发

                        // 更严格的验证：检查事件间隔是否有非空格非修饰键
                        let nonSpaceEvents = shared.keyEventsBetweenSpaces.filter { keyCode in
                            return keyCode != kVK_Space &&
                                   keyCode != kVK_Command &&
                                   keyCode != kVK_Shift &&
                                   keyCode != kVK_Option &&
                                   keyCode != kVK_Control &&
                                   keyCode != kVK_CapsLock &&
                                   keyCode != kVK_Function
                        }

                        if nonSpaceEvents.isEmpty {
                            // 验证通过，使用延迟验证机制处理翻译
                            DispatchQueue.main.async {
                                // 使用InputManager的延迟验证机制
                                InputManager.shared.handleDoubleSpaceWithValidation {
                                    // 300ms后没有新的键盘输入，执行翻译
                                    shared.handleDoubleSpaceKey()
                                }
                            }
                        } else {
                            Logger.debug("Double space validation failed: found \(nonSpaceEvents.count) non-space keys: \(nonSpaceEvents)")
                        }

                        shared.keyEventsBetweenSpaces.removeAll()
                        let finishTime = Date()
                        Logger.info("Double Space Time: \(finishTime.timeIntervalSince(currentTime))s")
                    } else {
                        // 第一次空格：重置状态，开始新的检测周期
                        shared.lastSpaceTime = currentTime
                        shared.keyEventsBetweenSpaces.removeAll()
                        
                        if shared.lastSpaceTime == nil {
                            Logger.debug("First space detected, waiting for second space")
                        }
                    }
                } else {
                    // 非空格键输入时，检查是否需要取消待处理的翻译
                    // 排除修饰键，只关注实际的字符输入
                    if keyCode != kVK_Command &&
                       keyCode != kVK_Shift &&
                       keyCode != kVK_Option &&
                       keyCode != kVK_Control &&
                       keyCode != kVK_CapsLock &&
                       keyCode != kVK_Function {
                        // 有实际的字符输入，取消待处理的翻译触发
                        InputManager.shared.handleKeyboardInputForTranslationValidation()
                    }
                }

                if keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter { // 回车键
                    // 快速检查，避免复杂逻辑
                    if shared.shouldInterceptEnter() {
                        // 立即提交处理任务
                        print(" ")
                        Logger.info("===========================================")
                        
                        DispatchQueue.main.async {
                            shared.handleInterceptedEnter()
                        }
                        
                        return nil // 阻止回车事件
                    }
                } else if keyCode == kVK_Tab { // Tab键
                    DispatchQueue.global(qos: .background).async {
                        DispatchQueue.main.async {
                            shared.handleTabKey()
                        }
                    }
                } else if keyCode == 0 && event.flags.contains(.maskCommand) && 
                           !event.flags.contains(.maskShift) && 
                           !event.flags.contains(.maskAlternate) && 
                           !event.flags.contains(.maskControl) { // Cmd+A 检测（排除 Shift+Cmd+A、Option+Cmd+A、Ctrl+Cmd+A）
                    Logger.debug("Pure Cmd+A detected (no additional modifiers)")
                    DispatchQueue.global(qos: .background).async {
                        DispatchQueue.main.async {
                            shared.handleCmdA()
                        }
                    }
                } else if keyCode == 0 && event.flags.contains(.maskCommand) {
                    // Log ignored Cmd+A with additional modifiers
                    var modifiers: [String] = []
                    if event.flags.contains(.maskShift) { modifiers.append("Shift") }
                    if event.flags.contains(.maskAlternate) { modifiers.append("Option") }
                    if event.flags.contains(.maskControl) { modifiers.append("Ctrl") }
                    Logger.debug("Cmd+A with additional modifiers ignored: \(modifiers.joined(separator: "+"))+Cmd+A")
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
    
    // 新的优化方法：处理已验证的双击空格
    func handleDoubleSpaceKey() {
        let bundleId = AppDetectionManager.shared.getBundleId()
        Logger.info("Processing validated double space for app: \(bundleId)")
        
        // Skip terminal apps
        if AppDetectionManager.shared.isTerminalApp() {
            Logger.info("Terminal app detected, ignoring space key trigger.")
            return
        }
        
        // 防止过于频繁的触发
        if let lastTime = lastTranslationTime, Date().timeIntervalSince(lastTime) < 1.0 {
            Logger.debug("Skipping double space - too soon after last translation")
            return
        }
        
        // Get focused element with fresh attempt (no caching issues)
        let focusedElement = AXController.shared.getFocusedElement()  
        DispatchQueue.global(qos: .userInitiated).async {
            if let result = AXController.shared.detectTriggerAndExtract(focusedElement: focusedElement) {
                // 成功检测到触发词，启动翻译
                DispatchQueue.main.async {
                    self.startTranslation(text: result.text, lang: result.lang, focusedElement: focusedElement)
                }
            } else {
                // 未检测到触发词（误触），发送右箭头键恢复
                Logger.info("Simulate keyboard app misfire detected. No trigger in clipboard. Recovering.")
                DispatchQueue.main.async {
                        AXController.shared.postRightArrowKey()
                }
            }
        }
        return // Simulate keyboard app 逻辑结束
        
    } 
  
    private func startTranslation(text: String, lang: String, focusedElement: AXUIElement? = nil) {
        // 记录翻译时间，用于健康检查的智能调整
        lastTranslationTime = Date()
        
        // 对于输入框翻译（空格键触发），需要在翻译开始前记录应用信息
        // 选中文本翻译已在 checkSelectedTextAndShowMenu 中记录了
        EnvironmentManager.shared.recordTriggerApp() 
        
        // 使用传入的焦点元素，如果没有传入则获取当前焦点元素
        let elementToUse = focusedElement ?? AXController.shared.getFocusedElement()
        
        // 获取当前焦点元素用于定位状态窗口
        let mouseLocation = NSEvent.mouseLocation
        // 显示翻译中状态
        TranslationStatusWindow.shared.showTranslating(near: elementToUse,mousePoint:mouseLocation)
        
        
        // Check login status before translation
        guard SessionManager.shared.isAuthenticated else {
            Logger.info("User not logged in for space key translation, showing login prompt")
            TranslationStatusWindow.shared.hideStatus()
            UserManager.shared.promptLogin(reason: "Please sign in to use Glotera.")
            EnvironmentManager.shared.clearTriggerAppInfo()
            return
        }
        
        // 开始翻译（不禁用输入，避免死锁）
        TranslatorClient.shared.translate(text: text, to: lang) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let translationResult):
                    Logger.debug("Translation result: \(translationResult.translated)")
                    
                    // 缓存翻译结果
                    self?.cacheTranslation(
                        original: text,
                        translated: translationResult.translated,
                        sourceLanguage: translationResult.fromLanguage,
                        targetLanguage: lang
                    )
                    
                    // 翻译成功后立即隐藏状态窗口，然后开始回填
                    TranslationStatusWindow.shared.hideStatus()
                  
                    // 回填翻译结果
                    AXController.shared.replaceInput(with: translationResult.translated) {
                        Logger.debug("Auto-translation replacement completed")
                        
                        
                        // 翻译完成后清除缓存的应用信息
                        EnvironmentManager.shared.clearTriggerAppInfo()
                    }
                case .failure(let error):
                    Logger.warn("Translation failed: \(error.localizedDescription)")
                    // If token expired, prompt for re-login
                    if error.localizedDescription.contains("token") || error.localizedDescription.contains("401") {
                        SessionManager.shared.clearSession()
                        UserManager.shared.promptLogin(reason: "Your session has expired. Please sign in again.")
                    } else {
                        // 显示失败状态
                        TranslationStatusWindow.shared.showFailure()
                    }
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
        // Tab键可能在某些应用自动读取上下文实现自动补全
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
        Logger.info("=== Auto-translate Enter Key Check ===")
        
        // 只在聊天软件中启用回车键拦截功能
        guard AppDetectionManager.shared.isChatApp() else {
            Logger.info("❌ Not a chat application: \(AppDetectionManager.shared.getBundleId())")
            return false
        }
        Logger.info("✅ Chat application detected: \(AppDetectionManager.shared.getBundleId())")
        
        // 防止拦截我们自己发送的Enter键
        if InputManager.shared.isSendingEnterKeyEvent() {
            Logger.info("❌ Currently sending Enter key - avoiding loop")
            return false
        }
        
        // 如果最近刚发送过Enter键，也忽略（防止时序问题）
        if let sentTime = InputManager.shared.getEnterKeySentTime(),
           Date().timeIntervalSince(sentTime) < 1.0 {
            Logger.info("❌ Recently sent Enter key - avoiding loop")
            return false
        }
          
        // 如果最近通过菜单进行了划词翻译，不拦截回车
        if let selectionTime = lastSelectionTranslationTime, Date().timeIntervalSince(selectionTime) < 2.0 {
            Logger.info("❌ Recent selection translation - avoiding conflict")
            return false
        }
        
        // 检查是否启用了Return键拦截功能（With Trigger 或 Without Trigger）
        let withTriggerEnabled = ConfigManager.shared.isReturnKeyWithTriggerEnabled()
        let withoutTriggerEnabled = ConfigManager.shared.isReturnKeyWithoutTriggerEnabled()
        
        Logger.info("Settings - With Trigger: \(withTriggerEnabled), Without Trigger: \(withoutTriggerEnabled)")
        
        if !withTriggerEnabled && !withoutTriggerEnabled {
            Logger.info("❌ Both Return key interception options are disabled in settings")
            return false
        }
        
        // 如果启用了Without Trigger，检查翻译窗口是否开启（仅限WhatsApp）
        if withoutTriggerEnabled {
            // 检查是否为WhatsApp
            let isWhatsApp = AppDetectionManager.shared.isWhatsAppApp()
            Logger.info("Is WhatsApp app: \(isWhatsApp)")
            
            if isWhatsApp {
                let translationWindowVisible = ChatTranslationManager.shared.getTranslationWindowVisible()
                Logger.info("Translation window visible: \(translationWindowVisible)")
                
                if translationWindowVisible {
                    Logger.info("✅ Return key interception enabled - WhatsApp app with translation window visible and without trigger enabled")
                    return true
                } else {
                    Logger.info("❌ Translation window is not visible - without trigger mode requires visible window")
                }
            } else {
                Logger.info("❌ Without trigger mode is only available for WhatsApp")
            }
        }
        
        // 如果启用了With Trigger，检查是否有触发词
        if withTriggerEnabled {
            Logger.info("✅ Return key with trigger is enabled")
            return true
        }
        
        Logger.info("❌ No conditions met for Enter key interception")
        return false
    }
    
    // 处理被拦截的回车键
    func handleInterceptedEnter() {
        Logger.info("Handling intercepted Enter key")
        
        // 获取当前焦点元素，避免重复调用
        let focusedElement = AXController.shared.getFocusedElement() 
        
        // 检查是否启用了Without Trigger模式且翻译窗口可见
        let withoutTriggerEnabled = ConfigManager.shared.isReturnKeyWithoutTriggerEnabled()
        let translationWindowVisible = ChatTranslationManager.shared.getTranslationWindowVisible()
        
        DispatchQueue.global(qos: .userInitiated).async {
            // 首先尝试检测触发词（With Trigger模式）
            if let result = AXController.shared.detectTriggerAndExtract(focusedElement: focusedElement) {
                // 成功检测到触发词，启动翻译
                Logger.info("Trigger detected via intercepted Enter: text=\(result.text), lang=\(result.lang)")
                DispatchQueue.main.async {
                    self.startTranslationWithAutoSend(text: result.text, lang: result.lang, focusedElement: focusedElement)
                }
            } else if withoutTriggerEnabled && translationWindowVisible {
                // 没有触发词，但启用了Without Trigger模式且翻译窗口可见
                // 检查是否为WhatsApp（Without Trigger模式仅限WhatsApp）
                let isWhatsApp = AppDetectionManager.shared.isWhatsAppApp()
                
                if isWhatsApp {
                    Logger.info("No trigger found, but without trigger mode is enabled for WhatsApp and translation window is visible")
                    
                    // 获取输入框中的文本
                    if let focusedElement = focusedElement,
                       let text = AXController.shared.getValue(of: focusedElement), 
                       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // 检测对方发送的语言，并翻译成对方的语言
                        DispatchQueue.main.async {
                            self.handleWithoutTriggerTranslation(text: text, focusedElement: focusedElement)
                        }
                    } else {
                        Logger.warn("No text found in input field, sending original Enter key")
                        DispatchQueue.main.async {
                            InputManager.shared.sendEnterKey()
                        }
                    }
                } else {
                    Logger.info("Without trigger mode is only available for WhatsApp, sending original Enter key")
                    DispatchQueue.main.async {
                        InputManager.shared.sendEnterKey()
                    }
                }
            } else {
                Logger.warn("No trigger found and without trigger mode not applicable, sending original Enter key")
                // 如果没有检测到触发器且不适用Without Trigger模式，发送原始回车键
                DispatchQueue.main.async {
                    InputManager.shared.sendEnterKey()
                }
            }
        }
    }
    
    // 处理Without Trigger模式的翻译
    private func handleWithoutTriggerTranslation(text: String, focusedElement: AXUIElement? = nil) {
        Logger.info("=== Without Trigger Translation ===")
        Logger.info("Input text: '\(text.prefix(50))...' (length: \(text.count))")
        
        // Early-bypass: If current input equals a recent translated text (<=60s),
        // directly send Enter and persist using cached original to keep UI/DB consistent
        if let cached = findCachedTranslation(byTranslatedText: text) {
            let age = Date().timeIntervalSince(cached.timestamp)
            if age < 60 {
                Logger.info("✅ Without-trigger early-bypass: matches cached translation (\(Int(age))s)")
                DispatchQueue.main.async {
                    InputManager.shared.sendEnterKey()
                }
                // Persist immediately so the chat window and DB have both original and translated
                checkAndSaveTranslationOnSend(sentText: text)
                EnvironmentManager.shared.clearTriggerAppInfo()
                return
            }
        }
        
        // 获取对方发送的语言
        let targetLanguage = getOpponentLanguage()
        Logger.info("Target language for translation: \(targetLanguage)")

        // 如果输入语言与对方语言相同，则不进行翻译，直接发送，并保存到数据库
        let sourceLanguage = ContentProcessor.detectLanguage(text)
        let normalize: (String) -> String = { code in
            let lower = code.lowercased()
            if lower.hasPrefix("zh") { return lower.contains("tw") || lower.contains("hant") || lower.contains("hk") ? "zh-tw" : "zh" }
            if let base = lower.split(separator: "-").first { return String(base) }
            return lower
        }
        if !sourceLanguage.isEmpty && normalize(sourceLanguage) == normalize(targetLanguage) {
            Logger.info("Source language (\(sourceLanguage)) equals opponent language (\(targetLanguage)). Skipping translation; will send original and persist record.")

            // 获取应用与会话信息用于持久化
            var appName = "Unknown"
            var sessionId = "Unknown"
            if let activeApp = NSWorkspace.shared.frontmostApplication, let bundleId = activeApp.bundleIdentifier {
                appName = AppDetectionManager.shared.getChatAppName(bundleId: bundleId)
                if AppDetectionManager.shared.isWhatsAppApp(bundleId: bundleId) {
                    if let whatsappSessionId = WhatsAppMessagesProcessor.getCurrentChatSessionId(activeApp: activeApp) {
                        sessionId = whatsappSessionId
                    }
                }
            }

            // 保存未翻译的直接发送记录
            self.saveDirectSendWithoutTranslation(
                appName: appName,
                sessionId: sessionId,
                originalText: text,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage
            )

            // 发送回车并清理环境
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                InputManager.shared.sendEnterKey()
                EnvironmentManager.shared.clearTriggerAppInfo()
            }
            return
        }
        
        // 对于输入框翻译（Without Trigger模式），需要在翻译开始前记录应用信息
        EnvironmentManager.shared.recordTriggerApp()
        
        // 使用传入的焦点元素，如果没有传入则获取当前焦点元素
        let elementToUse = focusedElement ?? AXController.shared.getFocusedElement()
        
        // 获取应用名称
        guard let activeApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = activeApp.bundleIdentifier else {
            Logger.debug("Unable to get active app for opponent language detection")
            return
        }

        let appName = AppDetectionManager.shared.getChatAppName(bundleId: bundleId)
        
        // 获取当前聊天会话ID
        var sessionId = "Unknown"
        if AppDetectionManager.shared.isWhatsAppApp(bundleId: bundleId) {
            if let whatsappSessionId = WhatsAppMessagesProcessor.getCurrentChatSessionId(activeApp: activeApp) {
                sessionId = whatsappSessionId
            }
        }

        // 获取当前焦点元素用于定位状态窗口
        let mouseLocation = NSEvent.mouseLocation
        // 显示翻译中状态
        TranslationStatusWindow.shared.showTranslating(near: elementToUse, mousePoint: mouseLocation)
        Logger.info("Translation status window shown")
        
        // Check login status before translation
        guard SessionManager.shared.isAuthenticated else {
            Logger.info("❌ User not logged in for without trigger translation, showing login prompt")
            TranslationStatusWindow.shared.hideStatus()
            UserManager.shared.promptLogin(reason: "Please sign in to use Glotera.")
            // Send Enter key to complete the action even without translation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                InputManager.shared.sendEnterKey()
                EnvironmentManager.shared.clearTriggerAppInfo()
            }
            return
        }
        Logger.info("✅ User authentication verified")
        
        // 开始翻译（不禁用输入，避免死锁）
        TranslatorClient.shared.translate(text: text, to: targetLanguage) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let translationResult):
                    Logger.info("Without trigger translation result: \(translationResult.translated)")
                    
                    // 对于回车自动翻译，不需要缓存（直接保存到数据库）
                    // self?.cacheTranslation(...) - 移除缓存逻辑
                    
                    // 翻译成功后立即隐藏状态窗口，然后开始回填
                    TranslationStatusWindow.shared.hideStatus()
                    // 回填翻译结果，完成后发送回车键
                    AXController.shared.replaceInput(with: translationResult.translated) {
                        Logger.info("Without trigger auto-translation with send completed")
                        
                        // 根据不同应用调整延迟时间
                        let isWeChat = AppDetectionManager.shared.isWeChatApp()
                        let delay = isWeChat ? 0.05 : 0.05  // 稍微延迟，确保内容完全更新
                        
                        Logger.info("Waiting \(delay)s before sending Enter key (WeChat: \(isWeChat))")
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            InputManager.shared.sendEnterKey()
                            
                            // 发送成功后直接保存翻译记录（回车自动翻译场景）
                            self?.saveAutoTranslationDirectly(
                                appName: appName,
                                sessionId: sessionId,
                                originalText: text,
                                translatedText: translationResult.translated,
                                sourceLanguage: translationResult.fromLanguage,
                                targetLanguage: targetLanguage
                            )
                            
                            // 翻译完成后清除缓存的应用信息
                            EnvironmentManager.shared.clearTriggerAppInfo()
                        }
                    }
                case .failure(let error):
                    Logger.warn("Without trigger translation failed: \(error.localizedDescription)")
                    // If token expired, prompt for re-login
                    if error.localizedDescription.contains("token") || error.localizedDescription.contains("401") {
                        SessionManager.shared.clearSession()
                        UserManager.shared.promptLogin(reason: "Your session has expired. Please sign in again.")
                    } else {
                        // 显示失败状态
                        TranslationStatusWindow.shared.showFailure()
                    }
                    // 翻译失败时发送原始内容
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        InputManager.shared.sendEnterKey()
                        // 翻译失败后也清除缓存的应用信息
                        EnvironmentManager.shared.clearTriggerAppInfo()
                    }
                }
            }
        }
    }
    
    // 获取对方发送的语言
    private func getOpponentLanguage() -> String {
        // 获取当前活跃应用
        guard let activeApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = activeApp.bundleIdentifier else {
            Logger.debug("Unable to get active app for opponent language detection")
            let preferredLanguage = ConfigManager.shared.getUserPreferredLanguage()
            Logger.info("No active app detected, using user's preferred language as fallback: \(preferredLanguage)")
            return preferredLanguage
        }
        
        // 检查是否是支持的聊天应用
        guard AppDetectionManager.shared.isChatApp(bundleId: bundleId) else {
            Logger.debug("Current app is not a chat app, using preferred language")
            let preferredLanguage = ConfigManager.shared.getUserPreferredLanguage()
            return preferredLanguage
        }
        
        // 获取应用名称和会话ID
        let appName = AppDetectionManager.shared.getChatAppName(bundleId: bundleId)
        var sessionId = "Unknown"
        
        if AppDetectionManager.shared.isWhatsAppApp(bundleId: bundleId) {
            if let whatsappSessionId = WhatsAppMessagesProcessor.getCurrentChatSessionId(activeApp: activeApp) {
                sessionId = whatsappSessionId
            }
        }
        // TODO: 后续可以添加其他聊天应用的会话ID获取逻辑
        
        // 从数据库获取最近收到的消息语言
        let dbManager = DatabaseManager.shared
        if let lastReceivedLanguage = dbManager.getLastReceivedMessageLanguage(forApp: appName, sessionId: sessionId),
           !lastReceivedLanguage.isEmpty {
            Logger.info("Using last received message language from database: \(lastReceivedLanguage) for session: \(sessionId)")
            return lastReceivedLanguage
        }
        
        // 如果没有检测到对方语言，使用用户的首选语言作为回退
        let preferredLanguage = ConfigManager.shared.getUserPreferredLanguage()
        Logger.info("No opponent language detected, using user's preferred language as fallback: \(preferredLanguage)")
        return preferredLanguage
    }
    
    // 在回车发送时检查是否需要保存翻译记录到数据库
    private func checkAndSaveTranslationOnSend(sentText: String) {
        // 获取当前活跃应用
        guard let activeApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = activeApp.bundleIdentifier else {
            Logger.debug("Unable to get active app for translation save check")
            return
        }
        
        // 第一个条件：检查是否是支持的聊天应用
        guard AppDetectionManager.shared.isChatApp(bundleId: bundleId) else {
            Logger.debug("Current app is not a chat app, skipping translation save check")
            return
        }
        
        // 第二个条件：检查发送的内容是否匹配最近的翻译缓存
        guard let cachedTranslation = findCachedTranslation(byTranslatedText: sentText) else {
            Logger.debug("No cached translation found for sent text: \(sentText.prefix(30))...")
            return
        }
        
        // 匹配成功，保存到数据库
        let appName = activeApp.localizedName ?? "Unknown"
        Logger.info("Found cached translation for sent text, saving to database for app: \(appName)")
        
        // 获取当前聊天会话ID
        var sessionId = "Unknown"
        if AppDetectionManager.shared.isWhatsAppApp(bundleId: bundleId) {
            if let whatsappSessionId = WhatsAppMessagesProcessor.getCurrentChatSessionId(activeApp: activeApp) {
                sessionId = whatsappSessionId
            }
        }
        // TODO: 后续可以添加其他聊天应用的会话ID获取逻辑
        
        // 计算内容哈希
        let dbManager = DatabaseManager.shared
        let contentHash = dbManager.calculateContentHash(cachedTranslation.originalText)
        
        // 创建消息记录
        let messageRecord = MessageRecord(
            sender: "You", // 用户发送的消息
            content: cachedTranslation.originalText, // 保存原文内容
            contentHash: contentHash,
            contentLanguage: cachedTranslation.sourceLanguage ?? "unknown", // 原文语言
            contentTranslation: sentText, // 保存翻译后的内容（这是实际发送的内容）
            contentTranslationLanguage: cachedTranslation.targetLanguage, // 翻译目标语言
            contentTimestamp: Date(), // 当前时间
            chatApp: appName,
            sessionId: sessionId
        )
        
        Logger.info("Saving user translation: '\(cachedTranslation.originalText)' -> '\(sentText)' (session: \(sessionId))")
        
        // 保存到数据库
        _ = dbManager.insertMessage(messageRecord)
        
        // 立即更新侧边翻译窗口（不等待定时器）
        if let chatWindow = ChatTranslationManager.shared.getChatTranslationWindow() {
            chatWindow.addUserMessage(
                originalText: cachedTranslation.originalText,
                translatedText: sentText,
                sourceLanguage: cachedTranslation.sourceLanguage,
                targetLanguage: cachedTranslation.targetLanguage,
                sessionId: sessionId
            )
            Logger.debug("Chat window updated immediately after user translation")
        }
        
        Logger.debug("User translation saved successfully")
    }
    
    // 翻译完成后自动发送
    private func startTranslationWithAutoSend(text: String, lang: String, focusedElement: AXUIElement? = nil) {
        // 对于输入框翻译（回车键触发），需要在翻译开始前记录应用信息
        // 选中文本翻译已在 checkSelectedTextAndShowMenu 中记录了
        EnvironmentManager.shared.recordTriggerApp() 
        
        // 使用传入的焦点元素，如果没有传入则获取当前焦点元素
        let elementToUse = focusedElement ?? AXController.shared.getFocusedElement()
        
        // 获取应用名称
        guard let activeApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = activeApp.bundleIdentifier else {
            Logger.debug("Unable to get active app for opponent language detection")
            return
        }

        let appName = AppDetectionManager.shared.getChatAppName(bundleId: bundleId)
        
        // 获取当前聊天会话ID
        var sessionId = "Unknown"
        if AppDetectionManager.shared.isWhatsAppApp(bundleId: bundleId) {
            if let whatsappSessionId = WhatsAppMessagesProcessor.getCurrentChatSessionId(activeApp: activeApp) {
                sessionId = whatsappSessionId
            }
        }

        // 获取当前焦点元素用于定位状态窗口
        let mouseLocation = NSEvent.mouseLocation
        // 显示翻译中状态
        TranslationStatusWindow.shared.showTranslating(near: elementToUse,mousePoint:mouseLocation)
        
        
        // Check login status before translation
        guard SessionManager.shared.isAuthenticated else {
            Logger.info("User not logged in for Enter key translation, showing login prompt")
            TranslationStatusWindow.shared.hideStatus()
            UserManager.shared.promptLogin(reason: "Please sign in to use Glotera.")
            // Send Enter key to complete the action even without translation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                InputManager.shared.sendEnterKey()
                EnvironmentManager.shared.clearTriggerAppInfo()
            }
            return
        }
        
        // 开始翻译（不禁用输入，避免死锁）
        TranslatorClient.shared.translate(text: text, to: lang) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let translationResult):
                    Logger.info("Translation result: \(translationResult.translated)")
                    
                    // 对于触发词自动翻译，不需要缓存（直接保存到数据库）
                    // self?.cacheTranslation(...) - 移除缓存逻辑
                    
                    // 翻译成功后立即隐藏状态窗口，然后开始回填
                    TranslationStatusWindow.shared.hideStatus() 
                    // 回填翻译结果，完成后发送回车键
                    AXController.shared.replaceInput(with: translationResult.translated) {
                        Logger.info("Auto-translation with send completed")
                        
                        // 根据不同应用调整延迟时间 - 使用缓存的检测结果
                        let isWeChat = AppDetectionManager.shared.isWeChatApp()
                        let delay = isWeChat ? 0.05 : 0.05  // 稍微延迟，确保内容完全更新
                        
                        Logger.info("Waiting \(delay)s before sending Enter key (WeChat: \(isWeChat))")
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            InputManager.shared.sendEnterKey()
                            
                            // 发送成功后直接保存翻译记录（触发词自动翻译场景）
                            self?.saveAutoTranslationDirectly(
                                appName: appName,
                                sessionId: sessionId,
                                originalText: text,
                                translatedText: translationResult.translated,
                                sourceLanguage: translationResult.fromLanguage,
                                targetLanguage: lang
                            )
                            
                            // 翻译完成后清除缓存的应用信息
                            EnvironmentManager.shared.clearTriggerAppInfo()
                        }
                        
                    }
                case .failure(let error):
                    Logger.warn("Translation failed: \(error.localizedDescription)")
                    // If token expired, prompt for re-login
                    if error.localizedDescription.contains("token") || error.localizedDescription.contains("401") {
                        SessionManager.shared.clearSession()
                        UserManager.shared.promptLogin(reason: "Your session has expired. Please sign in again.")
                    } else {
                        // 显示失败状态
                        TranslationStatusWindow.shared.showFailure()
                    }
                    // 翻译失败时发送原始内容
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        InputManager.shared.sendEnterKey()
                        // 翻译失败后也清除缓存的应用信息
                        EnvironmentManager.shared.clearTriggerAppInfo()
                    }
                }
            }
        }
    }
    
 
    
    // 取消选中状态（误触发后恢复）
    private func cancelSelectionAfterMisfire() {
        Logger.info("Canceling selection after misfire")
        
        // 检查是否为特殊应用，使用相应的取消选中方法
        if AppDetectionManager.shared.isAdsPowerApp() {
            // AdsPower 使用右箭头键取消选中
            AXController.shared.postRightArrowKey()
            return
        }
        
        if AppDetectionManager.shared.isMailApp() {
            // Apple Mail 使用右箭头键取消选中
            AXController.shared.postRightArrowKey()
            return
        }
        
        // 对于其他应用，使用通用的取消选中方法
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            AXController.shared.postRightArrowKey()
        }
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
    
    // 重置统计计数器
    func resetEventCounters() {
        spaceKeyEventCount = 0
        totalKeyEventCount = 0
        lastEventTime = Date()
        lastSpaceKeyTime = Date()
        lastSpaceTime = nil // Reset double-space tracking
        keyEventsBetweenSpaces.removeAll() // Clear event tracking
        // Clear app detection cache when resetting
        cachedAppInfo = nil
        Logger.info("Event counters, double-space tracking, and app cache reset")
    }
    
    // 清除应用检测缓存（当应用切换时手动调用）
    func clearAppDetectionCache() {
        cachedAppInfo = nil
        Logger.debug("App detection cache cleared")
    }
    
    // Application switching observer
    @objc private func applicationDidActivate(_ notification: Notification) {
        // Clear app detection cache when user switches applications
        clearAppDetectionCache()
        Logger.debug("Application switched - app detection cache cleared")
    }
    
    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    // 强制触发业务逻辑检查
    func forceBusinessLogicCheck() {
        Logger.info("Force business logic check requested")
        checkBusinessLogicHealth()
    }

    func handleCmdA() {
        if TranslationStatusWindow.shared.isStatusVisible() {
            Logger.info("Cmd+A event ignored - status window is showing")
            return
        }

        Logger.info("Handling Cmd+A event")
        // 延迟检查，让 Cmd+A 操作完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // 通知 AXController 检查文本选择
            SelectEventManager.shared.checkForTextSelectionAfterKeyboardSelection()
        }
    }  
    
    // MARK: - 翻译缓存管理
    
    /// 缓存翻译结果
    private func cacheTranslation(original: String, translated: String, sourceLanguage: String?, targetLanguage: String) {
        let item = TranslationCacheItem(
            originalText: original,
            translatedText: translated,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        )
        
        cacheQueue.async(flags: .barrier) {
            self.translationCache[item.translatedTextHash] = item
            Logger.debug("Cached translation: '\(original)' -> '\(translated)' (hash: \(item.translatedTextHash))")
        }
    }
    
    /// 根据翻译文本查找缓存项
    private func findCachedTranslation(byTranslatedText text: String) -> TranslationCacheItem? {
        let hash = TranslationCacheItem.calculateHash(text)
        
        return cacheQueue.sync {
            guard let item = translationCache[hash], !item.isExpired else {
                if translationCache[hash] != nil { // Check if it existed but expired
                    Logger.debug("Translation cache expired for text: \(text.prefix(30))...")
                    translationCache.removeValue(forKey: hash)
                }
                return nil
            }
            
            Logger.debug("Found cached translation for text: \(text.prefix(30))... -> original: \(item.originalText.prefix(30))...")
            return item
        }
    }
    
    /// 清理过期的缓存项
    private func cleanupExpiredCacheItems() {
        cacheQueue.async(flags: .barrier) {
            let expiredKeys = self.translationCache.compactMap { (key, item) in
                item.isExpired ? key : nil
            }
            
            for key in expiredKeys {
                self.translationCache.removeValue(forKey: key)
            }
            
            if !expiredKeys.isEmpty {
                Logger.debug("Cleaned up \(expiredKeys.count) expired translation cache items")
            }
        }
    }
    
    /// 启动定期清理任务（每分钟清理一次）
    private func startPeriodicCacheCleanup() {
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            self.cleanupExpiredCacheItems()
        }
    }
    
    /// 直接保存自动翻译记录到数据库（用于回车键自动翻译场景）
    private func saveAutoTranslationDirectly(appName: String, sessionId: String, originalText: String, translatedText: String, sourceLanguage: String?, targetLanguage: String)  { 
         
        Logger.info("Saving auto translation directly for app: \(appName)")
        
        // 计算内容哈希
        let dbManager = DatabaseManager.shared
        let contentHash = dbManager.calculateContentHash(originalText)
        
        // 创建消息记录
        let messageRecord = MessageRecord(
            sender: "You", // 用户发送的消息
            content: originalText, // 保存原文内容
            contentHash: contentHash,
            contentLanguage: sourceLanguage ?? "unknown", // 原文语言
            contentTranslation: translatedText, // 保存翻译后的内容（这是实际发送的内容）
            contentTranslationLanguage: targetLanguage, // 翻译目标语言
            contentTimestamp: Date(), // 当前时间
            chatApp: appName,
            sessionId: sessionId
        )
        
        Logger.info("Saving auto translation directly: '\(originalText)' -> '\(translatedText)' (session: \(sessionId))")
        
        // 保存到数据库
        _ = dbManager.insertMessage(messageRecord)
        
        // 立即更新侧边翻译窗口（不等待定时器）
        if let chatWindow = ChatTranslationManager.shared.getChatTranslationWindow() {
            chatWindow.addUserMessage(
                originalText: originalText,
                translatedText: translatedText,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                sessionId: sessionId
            )
            Logger.debug("Chat window updated immediately after auto translation")
        }
        
        Logger.debug("Auto translation saved successfully")
    }

    /// 保存未翻译的直接发送记录到数据库（用于 Without Trigger 且同语种跳过翻译场景）
    private func saveDirectSendWithoutTranslation(appName: String, sessionId: String, originalText: String, sourceLanguage: String?, targetLanguage: String) {
        Logger.info("Saving direct send without translation for app: \(appName)")

        // 计算内容哈希
        let dbManager = DatabaseManager.shared
        let contentHash = dbManager.calculateContentHash(originalText)

        // 创建消息记录（无翻译）
        let messageRecord = MessageRecord(
            sender: "You",
            content: originalText,
            contentHash: contentHash,
            contentLanguage: sourceLanguage ?? "unknown",
            contentTranslation: "",
            contentTranslationLanguage: "",
            contentTimestamp: Date(),
            chatApp: appName,
            sessionId: sessionId
        )

        _ = dbManager.insertMessage(messageRecord)

        // 立即更新侧边翻译窗口（显示仅原文气泡）
        if let chatWindow = ChatTranslationManager.shared.getChatTranslationWindow() {
            chatWindow.addUserMessage(
                originalText: originalText,
                translatedText: "",
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                sessionId: sessionId
            )
        }

        Logger.debug("Direct send (no translation) saved successfully")
    }
}

 
