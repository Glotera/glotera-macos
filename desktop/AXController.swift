import Cocoa
import Carbon
import CoreFoundation
import ApplicationServices

// MARK: - Trigger Management (now handled by TriggerManager)

class AXController {
    static let shared = AXController()
    private var isInputDisabled = false
    private var originalValue: String?
    private var disabledElement: AXUIElement?
    private var lastManuallyFocusedElement: AXUIElement? 

    
    // 获取当前焦点输入框 - 增强版本
    func getFocusedElement() -> AXUIElement? {
        return InputManager.shared.getFocusedElementWithRetry(maxRetries: 3)
    }

    // MARK: - Trigger Detection
    // 检测当前焦点输入框内容，提取触发标记和原文
    func detectTriggerAndExtract() -> (text: String, lang: String)? {
        Logger.info("Starting trigger detection")
        
        guard let focused = getFocusedElement() else {
            Logger.warn("No focused element found")
            return nil
        }
        
        // 存储当前获取到的焦点元素，用于后续回填
        self.lastManuallyFocusedElement = focused
        Logger.info("Stored focused element for potential replacement")
        
        let value = getInputValue(of: focused, focusedElement: focused)
        if value.isEmpty {
            Logger.warn("No value found in focused element")
            return nil
        }
        
        return processContentForTrigger(value, focusedElement: focused)
    }
    
    // 处理内容以检测触发器 - 简化优化版本
    private func processContentForTrigger(_ value: String, focusedElement: AXUIElement? = nil) -> (text: String, lang: String)? {
        
        // 根据内容长度选择检测策略
        let detectionContent = value.count > 200 ? 
            String(value.suffix(50)) : value
        
        Logger.info("Using detection content length: \(detectionContent.count)\n content: \(detectionContent)")
        
        // 预处理内容：清理可能的干扰文本
        let cleanedValue = ContentProcessor.shared.preprocessContent(detectionContent)
        
        // 使用高性能缓存触发器检测
        if let result = TriggerManager.shared.detectTrigger(in: cleanedValue) {
            Logger.info("Cached trigger detected: text='\(result.text)', lang='\(result.lang)'")
            // 移除触发指令，返回清理后的文本作为翻译内容
            let cleanedText = TriggerManager.shared.removeTriggerFromText(value, detectedText: result.text, lang: result.lang)
            Logger.info("Cleaned text for translation: '\(cleanedText)'")
            return (text: cleanedText, lang: result.lang)
        }
        
        // 如果缓存检测失败，检查是否有配置的触发器
        let allTriggers = TriggerManager.shared.getAllTriggers()
        if allTriggers.isEmpty {
            Logger.warn("No configured triggers found, falling back to default patterns")
            if let result = TriggerManager.shared.processContentWithDefaultTriggers(cleanedValue) {
                // 移除触发指令，返回清理后的文本作为翻译内容
                let cleanedText = TriggerManager.shared.removeTriggerFromText(value, detectedText: result.text, lang: result.lang)
                Logger.info("Cleaned text for translation: '\(cleanedText)'")
                return (text: cleanedText, lang: result.lang)
            }
        }
        
        Logger.debug("No trigger detected in content")
        
        // Periodically log cache performance metrics
        let metrics = TriggerManager.shared.getPerformanceMetrics()
        let triggerMetrics = metrics.triggerCache
        if (triggerMetrics.hits + triggerMetrics.misses) % 100 == 0 && triggerMetrics.hits + triggerMetrics.misses > 0 {
            Logger.info("TriggerCache metrics: \(triggerMetrics.hits) hits, \(triggerMetrics.misses) misses, \(String(format: "%.1f", triggerMetrics.hitRatio * 100))% hit ratio")
        }
        
        return nil
    }

    // 获取输入框内容，支持Web环境和桌面应用
    private func getInputValue(of element: AXUIElement, focusedElement: AXUIElement) -> String {
         // 检查是否在浏览器环境中
        let isWeb = AppDetectionManager.shared.isWebEnvironment()
        if let browserInfo = AppDetectionManager.shared.getCurrentBrowserInfo() {
            Logger.info("Detected browser environment: \(browserInfo.appName) (\(browserInfo.bundleId))")
        }
        
        // 获取输入框内容，使用Web环境特殊处理
        guard let value = getStandardValue(of: focusedElement, isWeb: isWeb) else {
            Logger.warn("No value found in focused element")
            
            // 尝试备用方法获取内容
            Logger.info("Trying alternative content retrieval methods...")
            if let alternativeValue = getAlternativeValue(of: focusedElement) {
                Logger.info("Got content via alternative method: '\(alternativeValue)'")    
                //return processContentForTrigger(alternativeValue, focusedElement: focusedElement)
                return alternativeValue
            } 
          return ""
        }

        return value
    }
     
    
    // 标准获取方法，支持Web环境和桌面应用
    private func getStandardValue(of element: AXUIElement, isWeb: Bool) -> String? {
        
        // 首先尝试标准方法，获取输入框内容 
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        if let value = value as? String {
            Logger.info("Got content via standard method: \(value.count) chars \n \(value) ")
            return value
        } 
        
        // 其次尝试Web方法，因为Web Mail中会使用模拟键盘选中复制的方式来获取内容
        if isWeb {
            // 优先尝试AppleScript方法
            if let content = AppleScriptManager.shared.getWebContentViaAppleScript() { 
                Logger.info("Got content via AppleScript: \(content.count) chars")
                return content
            } else {
                // 如果AppleScript失败，尝试其他Web方法
                if let content = getWebInputValue(of: element) { 
                    Logger.info("Got content via Web input value: \(content.count) chars")
                    return content
                }
            }
        } 
        
        Logger.warn("No content available from any method")
        return nil
    }
    
    // 备用内容获取方法
    private func getAlternativeValue(of element: AXUIElement) -> String? {
        Logger.info("Trying alternative value retrieval methods")
        
        // 方法1: 尝试获取选中文本
        if let selectedText = SelectEventManager.shared.getSelectedTextAttribute(of: element), !selectedText.isEmpty {
            Logger.info("Got content via selected text: \(selectedText)")
            return selectedText
        }
        
        // 方法2: 尝试不同的属性
        let attributes = [
            kAXDescriptionAttribute,
            kAXTitleAttribute,
            kAXHelpAttribute,
            kAXPlaceholderValueAttribute
        ]
        
        for attribute in attributes {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
            if result == .success, let stringValue = value as? String, !stringValue.isEmpty {
                Logger.info("Got content via \(attribute): \(stringValue)")
                return stringValue
            }
        }
        
        // 方法3: 如果在Web环境，强制重试AppleScript
        if AppDetectionManager.shared.isWebEnvironment(){
            Logger.info("Forcing AppleScript retry for web content")
            // 等待一小段时间后重试
            Thread.sleep(forTimeInterval: 0.1)
            if let webContent = AppleScriptManager.shared.getWebContentViaAppleScript() {
                Logger.info("Got content via forced AppleScript retry: \(webContent)")
                return webContent
            } else {
                // 如果AppleScript失败，尝试其他Web方法
                if let content = getWebInputValue(of: element) { 
                    Logger.info("Got content via Web input value: \(content.count) chars")
                    return content
                }
            }
        }
        
        Logger.warn("All alternative methods failed")
        return nil
    }
    
    // Web输入框内容获取的特殊方法
    private func getWebInputValue(of element: AXUIElement) -> String? { 
        // 方法1: 尝试获取选中文本（在Web输入框中很常见）
        if let selectedText = SelectEventManager.shared.getSelectedTextAttribute(of: element), !selectedText.isEmpty {
            Logger.info("Got selected text: \(selectedText)")
            return selectedText
        }
        
        // 方法2: 尝试不同的AX属性
        let valueAttributes: [CFString] = [
            kAXValueAttribute as CFString,
            kAXDescriptionAttribute as CFString,
            kAXTitleAttribute as CFString,
            kAXHelpAttribute as CFString
        ]
        
        for attribute in valueAttributes {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
            if result == .success, let stringValue = value as? String, !stringValue.isEmpty {
                Logger.info("Got value from \(attribute): \(stringValue)")
                return stringValue
            }
        }
        
        Logger.warn("No content found via AX attributes")
        return nil
    }
    

    // 获取输入框内容
    func getValue(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        return value as? String
    }
     

    // 替换输入框内容
    func replaceInput(with text: String, completion: (() -> Void)? = nil) {
        Logger.info("Replacing input with translation result")
        
        // 新增：针对文本编辑器等场景的特殊回填逻辑
        if  AppDetectionManager.shared.isNeedSimulateKeyboardApp() {
            Logger.info("Text editor detected. Using dedicated replacement method.")
            replaceTextEditorInput(with: text, completion: completion)
            return
        }
        
        // 优先使用手动触发时保存的焦点元素，如果不存在，再尝试获取当前焦点
        guard let focused = self.lastManuallyFocusedElement ?? getFocusedElement() else {
            Logger.warn("No focused element to replace")
            completion?()
            return
        }
        
        // 清理已保存的元素，避免影响后续非手动触发的操作
        self.lastManuallyFocusedElement = nil
        
        // 暂停选中文本监听，防止自动翻译回填时触发翻译菜单
        SelectEventManager.shared.pauseSelectionMonitoring() 

        // 使用原有的桌面应用替换方法
        replaceWithClipboard(element: focused, text: text) {
                completion?()
            
        }
         
        // 延迟恢复选中文本监听，给文本替换足够的时间
        // 使用更长的延迟，确保自动翻译完全完成且文本状态稳定
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            SelectEventManager.shared.resumeSelectionMonitoring()
            Logger.info("Resumed selection monitoring after auto-translation")
        }
    }
   
    // 翻译操作完成后检查和恢复 Event Tap
    private func checkAndRecoverEventTapAfterTranslation() {
        // 增加一个小的延迟，确保翻译操作（特别是粘贴）已经完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let appDelegate = NSApp.delegate as? AppDelegate {
                if !appDelegate.isEventTapValid() {
                    Logger.warn("Event tap is invalid after translation, attempting to restart monitoring.")
                    appDelegate.restartEventMonitoring()
                }
            }
        }
    } 
    
    // 检查元素是否可编辑
    func isElementEditable(_ element: AXUIElement) -> Bool {
        // 检查当前应用是否是微信
        let isWeChat = AppDetectionManager.shared.isWeChatApp()
        
        // 检查元素的角色（Role）
        var role: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        
        if roleResult == .success, let roleString = role as? String {
            let editableRoles = [
                "AXTextField",          // 文本输入框
                "AXTextArea",           // 文本区域
                "AXComboBox",           // 组合框
                //"AXSecureTextField",    // 密码输入框
                "AXSearchField",        // 搜索框
                "AXStaticText"          // 静态文本（某些情况下可编辑）
            ]
            
            Logger.info("Element role: \(roleString), isWeChat: \(isWeChat), isTRAE: \(AppDetectionManager.shared.isTRAEApp())")
              
            // 对于 AXTextArea，需要进一步检查是否真的可编辑
            //这里不能直接调用AppDetectionManager.shared.isDingTalkApp()，因为最上层的应用是Glotera的菜单，需要通过pid来判断
            var isDingTalk = false
            var bundleId = ""
            var pid: pid_t = 0
            let pidResult = AXUIElementGetPid(element, &pid)
            if pidResult == .success, let app = NSRunningApplication(processIdentifier: pid) {
                if let appBundleId = app.bundleIdentifier, appBundleId.contains("DingTalk") || appBundleId.contains("dingtalk") {
                    isDingTalk = true
                    bundleId = appBundleId
                    Logger.info("Element belongs to DingTalk app (bundleId: \(bundleId))")
                }
            } 
            
            if roleString == "AXTextArea" && isDingTalk {
                // 检查是否被禁用
                var isEnabled: CFTypeRef?
                let enabledResult = AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &isEnabled)
                if enabledResult == .success, let enabled = isEnabled as? Bool, !enabled {
                    Logger.info("AXTextArea is disabled, not editable")
                    return false
                }
                
                // 检查是否有 readonly 属性
                var isReadOnly: CFTypeRef?
                let readonlyResult = AXUIElementCopyAttributeValue(element, "AXReadOnly" as CFString, &isReadOnly)
                if readonlyResult == .success, let readonly = isReadOnly as? Bool, readonly {
                    Logger.info("AXTextArea is readonly, not editable")
                    return false
                }
                
                // 检查是否有 canEdit 属性
                var canEdit: CFTypeRef?
                let canEditResult = AXUIElementCopyAttributeValue(element, "AXCanEdit" as CFString, &canEdit)
                if canEditResult == .success, let canEditBool = canEdit as? Bool, !canEditBool {
                    Logger.info("AXTextArea cannot be edited")
                    return false
                }
                
                // 尝试写入原值看元素是否可编辑
                if isTrulyEditableAXTextArea(element){
                    Logger.info("AXTextArea is truly editable") 
                    InputManager.shared.restoreFocusAndSelectAll(for: element, appBundleId: bundleId)
                }else{
                    Logger.info("AXTextArea isn't truly editable")
                    return false
                }
                
                // 通过以上检查的 AXTextArea 才认为是可编辑的
                Logger.info("AXTextArea passed all checks, considered editable")
                return true
            }
            
            // 如果是明确的可编辑控件
            if editableRoles.prefix(5).contains(roleString) {
                return true
            }
            
            // 对于微信，特殊处理
            if isWeChat {
                // 微信中的文本通常都可以被替换，即使是StaticText
                if roleString == "AXStaticText" || roleString == "AXTextArea" || roleString == "AXTextField" {
                    Logger.info("WeChat element detected as editable")
                    return true
                }
            }
            
            // 对于 WhatsApp，需要区分消息历史和输入框
            var isWhatsApp = false
            if pidResult == .success, let app = NSRunningApplication(processIdentifier: pid) {
                if let appBundleId = app.bundleIdentifier, appBundleId.lowercased().contains("whatsapp") {
                    isWhatsApp = true
                    Logger.info("Element belongs to WhatsApp app (bundleId: \(appBundleId))")
                }
            }
            
            if isWhatsApp {
                // WhatsApp 消息历史元素（不可编辑，应显示浮动窗口）
                if roleString == "AXGenericElement" || roleString == "AXGroup" || roleString == "AXStaticText" {
                    Logger.info("WhatsApp message element detected as non-editable (showing floating window)")
                    return false
                }
                
                // WhatsApp 输入框元素（可编辑，应该粘贴翻译结果）
                if roleString == "AXTextField" || roleString == "AXTextArea" {
                    Logger.info("WhatsApp input element detected as editable")
                    return true
                }
                
                // 其他 WhatsApp 元素默认不可编辑
                return false
            }
            
            // 对于TRAE应用，特殊处理
            if AppDetectionManager.shared.isTRAEApp() {
                // TRAE应用中的AXTextArea和AXTextField都应该可编辑
                if roleString == "AXTextArea" || roleString == "AXTextField" || roleString == "AXStaticText" {
                    Logger.info("TRAE element detected as editable: \(roleString)")
                    return true
                }
            }
            
            // 对于StaticText，需要进一步检查是否可编辑
            if roleString == "AXStaticText" {
                // 检查是否有编辑相关的属性
                var isEditable: CFTypeRef?
                let editableResult = AXUIElementCopyAttributeValue(element, "AXEnabled" as CFString, &isEditable)
                if editableResult == .success, let enabled = isEditable as? Bool {
                    return enabled
                }
                
                // 检查是否有其他可编辑属性
                var canEdit: CFTypeRef?
                let canEditResult = AXUIElementCopyAttributeValue(element, "AXCanEdit" as CFString, &canEdit)
                if canEditResult == .success, let canEditBool = canEdit as? Bool {
                    return canEditBool
                }
                
                // StaticText通常不可编辑，除非特别标记
                return false
            }
        }
        
        // 在Web环境中，通过JavaScript检查 
        return AppleScriptManager.shared.isWebElementEditable()
        
    }
    
    private func isTrulyEditableAXTextArea(_ element: AXUIElement) -> Bool {
        // 1. 读取原始值
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let originalValue = valueRef as? String else {
            return false
        }

        // 2. 写入临时测试值
        let testValue = "__test__"
        guard AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, testValue as CFTypeRef) == .success else {
            return false
        }

        // 3. 再次读取
        var afterWriteRef: CFTypeRef?
        let reReadResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &afterWriteRef)

        // 4. 恢复原值及选中状态
        _ = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, originalValue as CFTypeRef) 

        // 5. 判断写入是否真的生效
        if reReadResult == .success, let newValue = afterWriteRef as? String {
            return newValue == testValue
        }

        return false
    }
    
    // 使用剪贴板强力替换内容
    private func replaceWithClipboard(element: AXUIElement, text: String, completion: @escaping () -> Void) {
        Logger.info("Using robust clipboard force replace method for standard apps.")
        
        // 1. 保存原始剪贴板内容
        let pasteboard = NSPasteboard.general
        // let originalContent = pasteboard.string(forType: .string)
        
        // 2. 首先执行全选。这可能会被某些应用（如飞书）拦截，它们会自动将被选中的文本复制到剪贴板
        simulateSelectAll()
        
        // 3. 等待全选操作完成，然后立即设置剪贴板并粘贴，以覆盖应用可能进行的自动复制
        // simulateSelectAll() 内部有0.2秒延迟，我们等待0.3秒以确保其完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            Logger.info("Setting clipboard content right before pasting to avoid app interference.")
            
            // 4. 在粘贴前一刻，才将翻译结果放入剪贴板
            pasteboard.clearContents()
            guard pasteboard.setString(text, forType: .string) else {
                Logger.error("Robust Replace: Failed to set clipboard with translation.")
//                self.restorePasteboardContent(originalContent)
                completion()
                return
            }
            
            // 5. 立即执行粘贴
            self.simulatePaste()
            
            // 6. 安排恢复剪贴板的操作
            // simulatePaste() 内部有0.2秒延迟，我们等待0.4秒以确保粘贴完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                // self.restorePasteboardContent(originalContent)
                self.checkAndRecoverEventTapAfterTranslation()
                completion()
            }
        }
    }
    
    // 模拟 Cmd+A 全选
    private func simulateSelectAll() {
        // 添加延迟，确保与InputMonitor的事件处理分离
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            Logger.info("Simulating Cmd+A select all")
            let source = CGEventSource(stateID: .hidSystemState)
            
            // Cmd+A
            let cmdKeyCode: CGKeyCode = 55  // Command key
            let aKeyCode: CGKeyCode = 0     // A key
            
            if let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: true),
               let aDown = CGEvent(keyboardEventSource: source, virtualKey: aKeyCode, keyDown: true),
               let aUp = CGEvent(keyboardEventSource: source, virtualKey: aKeyCode, keyDown: false),
               let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: false) {
                
                aDown.flags = .maskCommand
                aUp.flags = .maskCommand
                
                // 恢复使用原始tap位置，通过时序分离避免冲突
                cmdDown.post(tap: .cghidEventTap)
                aDown.post(tap: .cghidEventTap)
                aUp.post(tap: .cghidEventTap)
                cmdUp.post(tap: .cghidEventTap)
                
                Logger.info("Simulated Cmd+A select all (with timing separation)")
            } else {
                Logger.warn("Failed to create Cmd+A events")
            }
        }
    }
    
    // 模拟 Cmd+V 粘贴
    private func simulatePaste() {
        // 添加延迟，确保与InputMonitor的事件处理分离
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            Logger.info("Simulating Cmd+V paste")
            let source = CGEventSource(stateID: .hidSystemState)
            
            // Cmd+V
            let cmdKeyCode: CGKeyCode = 55  // Command key
            let vKeyCode: CGKeyCode = 9     // V key
            
            if let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: true),
               let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
               let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false),
               let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: false) {
                
                vDown.flags = .maskCommand
                vUp.flags = .maskCommand
                
                // 恢复使用原始tap位置，通过时序分离避免冲突
                cmdDown.post(tap: .cghidEventTap)
                vDown.post(tap: .cghidEventTap)
                vUp.post(tap: .cghidEventTap)
                cmdUp.post(tap: .cghidEventTap)
                
                Logger.info("Simulated Cmd+V paste (with timing separation)")
            } else {
                Logger.warn("Failed to create Cmd+V events")
            }
        }
    }
    
       // 专用于替换选中文本的粘贴方法（不执行全选）
    func replaceSelectionWithPaste(with text: String, for pid: pid_t, completion: @escaping () -> Void) {
        let pasteboard = NSPasteboard.general

        // 1. 设置剪贴板，不再恢复
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            Logger.warn("Failed to set clipboard for selection replacement.")
            completion()
            return
        }
        Logger.info("Clipboard set with text: '\(text)'. Original content will not be restored.")

        // 2. 尝试激活目标应用
        guard let targetApp = NSRunningApplication(processIdentifier: pid) else {
            Logger.warn("Failed to find running application with pid \(pid)")
            completion()
            return
        }
        targetApp.activate(options: [.activateIgnoringOtherApps])
        
        // 3. 轮询检查目标应用是否已激活，成功或超时后执行粘贴
        var attempts = 0
        let maxAttempts = 40 // 40 * 50ms = 2 seconds timeout
        
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            // 检查当前激活的应用
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
                timer.invalidate()
                Logger.info("Target app with pid \(pid) is now active. Pasting.")
                
                // 等待一小会儿，让剪贴板在系统级别同步
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.simulatePaste()
                    completion()
                }
            } else {
                attempts += 1
                if attempts >= maxAttempts {
                    timer.invalidate()
                    Logger.warn("Timeout waiting for app with pid \(pid) to activate. Pasting anyway as a fallback.")
                    
                    // 即使超时，也尝试粘贴
                    self.simulatePaste()
                    completion()
                }
            }
        }
    }
     
    deinit {
        SelectEventManager.shared.stopSelectionMonitoring()
    }

    // 通过剪贴板检测触发器（专为模拟键盘应用设计）
    func detectTriggerViaClipboard() -> (text: String, lang: String)? {
        Logger.info("Starting system-wide clipboard-based trigger detection.")

        let pasteboard = NSPasteboard.general
        // let originalContent = saveOriginalPasteboardContent()
        
        // Clear clipboard to ensure we detect the new content
        pasteboard.clearContents()
        
        // Send Shitf+cmd+left & shift+cmd+up
        InputManager.shared.postSmartSelection()
        
        // Add a delay for the selection to register
        Thread.sleep(forTimeInterval: 0.2)
        
        var copiedText: String?
        
        // Try to copy twice to be robust
        for i in 1...2 {
            Logger.info("Attempting global copy, trial #\(i)")
            
            // Send Cmd+C (Copy) globally
            InputManager.shared.postCopy()
            
            // Add a longer delay for the copy action to complete
            Thread.sleep(forTimeInterval: 0.3)

            // Check clipboard
            copiedText = pasteboard.string(forType: .string)
            
            if let text = copiedText, !text.isEmpty {
                Logger.info("Found content in clipboard: '\(text)'")
                break
            } else {
                Logger.warn("Clipboard is empty after attempt #\(i).")
                if i < 2 {
                    Thread.sleep(forTimeInterval: 0.5) // Extra delay before retry
                }
            }
        } 
        
        guard let text = copiedText, !text.isEmpty else {
            Logger.error("No content found in clipboard after all copy attempts.")
            return nil
        }
        
        // Check if the copied text contains our trigger
        return processContentForTrigger(text)
    }
 
 
    // 新增：发送右箭头键以取消全选
    func postRightArrowKey() {
        InputManager.shared.postRightArrowKey()
    } 
    
    // 专为文本编辑器设计的回填方法
    private func replaceTextEditorInput(with text: String, completion: (() -> Void)?) {
        Logger.info("Text Editor: Using optimized replacement method with translation: '\(text)'")
        
        // 简化的回填方法：直接设置翻译结果到剪贴板，然后粘贴
        let pasteboard = NSPasteboard.general
        
        // 清空剪贴板并设置翻译结果
        pasteboard.clearContents()
        
        // 设置翻译结果到剪贴板
        if pasteboard.setString(text, forType: .string) {
            Logger.info("Text Editor Replace: Successfully set translation result to clipboard")
        } else {
            Logger.error("Text Editor Replace: Failed to set clipboard with translation result")
            completion?()
            return
        }
        
        // 重新选择光标前的内容 
        InputManager.shared.postSmartSelection()
        
        // 减少粘贴前等待时间
        Thread.sleep(forTimeInterval: 0.2) 
        InputManager.shared.postPaste()
         
        completion?()
    }
    

} 
