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
    private var lastSpaceKeyEventCount: Int = 0 // 记录第一次空格时的键盘事件计数
    private var keyEventsBetweenSpaces: [Int] = [] // 记录两次空格之间的键盘事件类型
    var spaceKeyEventCount = 0
    var totalKeyEventCount = 0
    private var lastTranslationTime: Date?
    private var lastSelectionTranslationTime: Date?
    
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
                
                // 记录空格之间的键盘事件
                if shared.lastSpaceTime != nil {
                    shared.keyEventsBetweenSpaces.append(Int(keyCode))
                }
                
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
        
        // 检查是否为双击空格 - 放宽验证条件，提高检测可靠性
        if let lastTime = lastSpaceTime, currentTime.timeIntervalSince(lastTime) < 0.4 {
            // 这是第二次点击，进行宽松的验证
            Logger.debug("Double space validation: checking keyboard events between spaces")
            
            // 验证1: 检查两次空格之间是否有其他键盘事件 
            // 分析键盘事件，过滤掉空格键本身和修饰键
            let nonSpaceEvents = keyEventsBetweenSpaces.filter { 
                $0 != kVK_Space && 
                $0 != kVK_Command && 
                $0 != kVK_Shift && 
                $0 != kVK_Option && 
                $0 != kVK_Control 
            } 
            
            if !nonSpaceEvents.isEmpty {
                Logger.debug("Double space validation failed: found \(nonSpaceEvents.count) non-space key events between spaces, ignoring as misfire")
                self.lastSpaceTime = nil
                self.lastSpaceKeyEventCount = 0
                self.keyEventsBetweenSpaces.removeAll()
                return
            }
            
            // 验证通过，重置状态
            self.lastSpaceTime = nil
            self.lastSpaceKeyEventCount = 0
            self.keyEventsBetweenSpaces.removeAll()
            
            Logger.info("Double space validation passed, proceeding with bundleId: \(AppDetectionManager.shared.getBundleId())")

            // 如果当前是终端应用，则直接忽略，暂不做处理
            if AppDetectionManager.shared.isTerminalApp() {
                Logger.info("Terminal app detected, ignoring space key trigger.")
                return
            }
             
            // 检查是否为Apple Mail等模拟键盘应用，如果是，则执行智能检测逻辑
            if AppDetectionManager.shared.isNeedSimulateKeyboardApp() {
                Logger.info("Simulate keyboard app detected, using smart clipboard-based detection.")
                DispatchQueue.global(qos: .userInitiated).async {
                    if let result = AXController.shared.detectTriggerViaClipboard() {
                        // 成功检测到触发词，启动翻译
                        DispatchQueue.main.async {
                            self.startTranslation(text: result.text, lang: result.lang)
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

            // --- 以下为标准应用的常规流程 ---
            Logger.info("Double space in standard app, checking for trigger characters.")   
            
            // 首先尝试标准检测 
            if let result = AXController.shared.detectTriggerAndExtract() { 
                Logger.info("Standard trigger detected: text='\(result.text)', lang='\(result.lang)'")
                startTranslation(text: result.text, lang: result.lang)
                return
            }
            
            Logger.warn("Standard detection failed, trying delayed detection...")
            // 如果标准检测失败，先尝试延迟检测，如果还是失败则取消选中
            // 如果标准检测失败，等待一小段时间后重试 (Discord需要更长的延迟)
            let delayTime = AppDetectionManager.shared.isDiscordApp() ? 0.2 : 0.05
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delayTime) {
                Logger.info("Attempting delayed trigger detection (delay: \(delayTime)s)")
                if let result = AXController.shared.detectTriggerAndExtract() {
                    Logger.info("Delayed trigger detected: text='\(result.text)', lang='\(result.lang)'")
                    self.startTranslation(text: result.text, lang: result.lang)
                } else {
                    Logger.info("No trigger detected after delay, canceling selection.")
                    // 没有检测到触发指令，立即取消选中状态
                    self.cancelSelectionAfterMisfire()
                }
            }
        } else {
            // 这是第一次点击，记录时间和键盘事件计数
            self.lastSpaceTime = currentTime
            self.lastSpaceKeyEventCount = totalKeyEventCount
            self.keyEventsBetweenSpaces.removeAll() // 清空之前的事件记录
            Logger.debug("Single space detected, waiting for second space. Key event count: \(totalKeyEventCount)")
        }
    }
 
  
    private func startTranslation(text: String, lang: String) {
        // 记录翻译时间，用于健康检查的智能调整
        lastTranslationTime = Date()
        
        // 对于输入框翻译（空格键触发），需要在翻译开始前记录应用信息
        // 选中文本翻译已在 checkSelectedTextAndShowMenu 中记录了
        EnvironmentManager.shared.recordTriggerApp() 
        
        // 获取当前焦点元素用于定位状态窗口
        let focusedElement = AXController.shared.getFocusedElement()
        
        // 获取当前焦点元素用于定位状态窗口
        let mouseLocation = NSEvent.mouseLocation
        // 显示翻译中状态
        TranslationStatusWindow.shared.showTranslating(near: focusedElement,mousePoint:mouseLocation)
        
        
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
        // 首先检查用户是否启用了Return键拦截功能
        guard ConfigManager.shared.isReturnKeyInterceptionEnabled() else {
            Logger.info("Return key interception is disabled in settings")
            return false
        }
        
        // 只在聊天软件中启用回车键拦截功能
        guard AppDetectionManager.shared.isChatApp() else {
            Logger.debug("Return key interception disabled - not a chat application: \(AppDetectionManager.shared.getBundleId())")
            return false
        }
        
        // 防止拦截我们自己发送的Enter键
        if InputManager.shared.isSendingEnterKeyEvent() {
            Logger.debug("Ignoring Enter key - we are currently sending one")
            return false
        }
        
        // 如果最近刚发送过Enter键，也忽略（防止时序问题）
        if let sentTime = InputManager.shared.getEnterKeySentTime(),
           Date().timeIntervalSince(sentTime) < 1.0 {
            Logger.debug("Ignoring Enter key - recently sent one")
            return false
        }
          
        // 如果最近通过菜单进行了划词翻译，不拦截回车
        if let selectionTime = lastSelectionTranslationTime, Date().timeIntervalSince(selectionTime) < 2.0 {
            return false
        } 

        // 快速检查当前输入框内容是否有触发词 @ # 等
        if let focused = AXController.shared.getFocusedElement(),
           let value = AXController.shared.getValue(of: focused) {
            // 简单检查是否包含语言代码的前缀字符
            
            let content = value.lowercased()
            if !content.isEmpty && (content.contains("@") || content.contains("#")) {
                return true
            }
            
            // // 检查常见的语言代码模式
            // let quickPatterns = ["@en", "#en", "@zh", "#zh", "@id", "#id", " en ", " zh ", " id "]
            // for pattern in quickPatterns {
            //     if content.contains(pattern) {
            //         return true
            //     }
            // } 
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
            InputManager.shared.sendEnterKey()
        }
    }
    
    // 翻译完成后自动发送
    private func startTranslationWithAutoSend(text: String, lang: String) {
        // 对于输入框翻译（回车键触发），需要在翻译开始前记录应用信息
        // 选中文本翻译已在 checkSelectedTextAndShowMenu 中记录了
        EnvironmentManager.shared.recordTriggerApp() 
        
        // 获取当前焦点元素用于定位状态窗口
        let focusedElement = AXController.shared.getFocusedElement()
        
        // 获取当前焦点元素用于定位状态窗口
        let mouseLocation = NSEvent.mouseLocation
        // 显示翻译中状态
        TranslationStatusWindow.shared.showTranslating(near: focusedElement,mousePoint:mouseLocation)
        
        
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
        // Clear app detection cache when resetting
        cachedAppInfo = nil
        Logger.info("Event counters and app cache reset")
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
} 
