import Cocoa
import ApplicationServices

class AXController {
    static let shared = AXController()
    private var isInputDisabled = false
    private var originalValue: String?
    private var disabledElement: AXUIElement?

    // 支持的浏览器应用bundle标识符
    private let browserBundleIds = [
        "com.google.Chrome",
        "com.apple.Safari", 
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "com.operasoftware.Opera",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi"
    ]
    
    // 检查当前活跃应用是否为浏览器
    private func getCurrentBrowserInfo() -> (bundleId: String, appName: String)? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return nil
        }
        
        if browserBundleIds.contains(bundleId) {
            return (bundleId: bundleId, appName: frontmostApp.localizedName ?? "Browser")
        }
        
        return nil
    }
    
    // 检查是否在Web环境中
    private func isWebEnvironment() -> Bool {
        return getCurrentBrowserInfo() != nil
    }

    // 检测当前焦点输入框内容，提取触发标记和原文
    func detectTriggerAndExtract() -> (text: String, lang: String)? {
        print("[LOG] Starting trigger detection")
        
        guard let focused = getFocusedElement() else {
            print("[LOG] No focused element found")
            return nil
        }
        
        // 检查是否在浏览器环境中
        let isWeb = isWebEnvironment()
        if let browserInfo = getCurrentBrowserInfo() {
            print("[LOG] Detected browser environment: \(browserInfo.appName) (\(browserInfo.bundleId))")
        }
        
        // 获取输入框内容，使用Web环境特殊处理
        guard let value = getValueWithWebSupport(of: focused, isWeb: isWeb) else {
            print("[LOG] No value found in focused element")
            return nil
        }
        
        print("[LOG] Current input content: '\(value)'")
        print("[LOG] Content length: \(value.count) characters")
        
        // 显示换行符位置以便调试
        let lineBreaks = value.enumerated().compactMap { $0.element == "\n" ? $0.offset : nil }
        if !lineBreaks.isEmpty {
            print("[LOG] Newlines found at positions: \(lineBreaks)")
        }
        
        // 检查多种触发模式，支持多行文本
        let patterns = [
            #"^(.*?)[@#](id|en|zh|ja|jp|ko|fr|de|es|ru|th)\s*$"#,  // 标准模式
            #"(.*?)[@#](id|en|zh|ja|jp|ko|fr|de|es|ru|th)$"#,      // 无空格结尾
            #"(.*?)\s+[@#](id|en|zh|ja|jp|ko|fr|de|es|ru|th)\s*$"#, // 空格分隔
            #"(?s)(.*?)[@#](id|en|zh|ja|jp|ko|fr|de|es|ru|th)\s*$"# // 使用内联修饰符支持多行
        ]
        
        for (index, pattern) in patterns.enumerated() {
            // 添加 dotMatchesLineSeparators 选项以支持多行文本
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let nsValue = value as NSString
                let results = regex.matches(in: value, options: [], range: NSRange(location: 0, length: nsValue.length))
                
                if let match = results.first, match.numberOfRanges >= 3 {
                    let textRange = match.range(at: 1)
                    let langRange = match.range(at: 2)
                    
                    if textRange.location != NSNotFound && langRange.location != NSNotFound {
                        let text = nsValue.substring(with: textRange).trimmingCharacters(in: .whitespacesAndNewlines)
                        var lang = nsValue.substring(with: langRange).lowercased()
                        
                        // 转换 jp 为 ja
                        if lang == "jp" { lang = "ja" }
                        
                        if !text.isEmpty {
                            print("[LOG] Trigger found using pattern \(index + 1): text='\(text)', lang='\(lang)'")
                            print("[LOG] Full text content (with potential newlines): '\(text)'")
                            return (text: text, lang: lang)
                        }
                    }
                }
            }
        }
        
        print("[LOG] No trigger pattern matched")
        return nil
    }
    
    // 获取输入框内容，支持Web环境
    private func getValueWithWebSupport(of element: AXUIElement, isWeb: Bool) -> String? {
        var standardContent: String?
        var webContent: String?
        
        // 首先尝试标准方法
        if let value = getValue(of: element) {
            standardContent = value
            print("[LOG] Got content via standard method: \(value.count) chars")
        }
        
        // 如果在Web环境中，同时尝试Web方法
        if isWeb {
            // 优先尝试AppleScript方法
            if let content = getWebContentViaAppleScript() {
                webContent = content
                print("[LOG] Got content via AppleScript: \(content.count) chars")
            } else {
                // 如果AppleScript失败，尝试其他Web方法
                if let content = getWebInputValue(of: element) {
                    webContent = content
                    print("[LOG] Got content via Web input value: \(content.count) chars")
                }
            }
        }
        
        // 选择最佳结果
        if let web = webContent, let standard = standardContent {
            // 如果两种方法都有结果，选择更长的或者非空的
            if web.count > standard.count {
                print("[LOG] Using web content (longer): \(web.count) chars vs \(standard.count) chars")
                return web
            } else {
                print("[LOG] Using standard content: \(standard.count) chars vs \(web.count) chars")
                return standard
            }
        } else if let web = webContent {
            print("[LOG] Using web content (only available): \(web.count) chars")
            return web
        } else if let standard = standardContent {
            print("[LOG] Using standard content (only available): \(standard.count) chars")
            return standard
        }
        
        print("[LOG] No content available from any method")
        return nil
    }
    
    // Web输入框内容获取的特殊方法
    private func getWebInputValue(of element: AXUIElement) -> String? {
        print("[LOG] Attempting Web input value extraction via AX attributes")
        
        // 方法1: 尝试获取选中文本（在Web输入框中很常见）
        if let selectedText = getSelectedTextAttribute(of: element), !selectedText.isEmpty {
            print("[LOG] Got selected text: \(selectedText)")
            return selectedText
        }
        
        // 方法2: 尝试不同的AX属性
        let valueAttributes = [
            kAXValueAttribute,
            kAXDescriptionAttribute,
            kAXTitleAttribute,
            kAXHelpAttribute
        ]
        
        for attribute in valueAttributes {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
            if result == .success, let stringValue = value as? String, !stringValue.isEmpty {
                print("[LOG] Got value from \(attribute): \(stringValue)")
                return stringValue
            }
        }
        
        print("[LOG] No content found via AX attributes")
        return nil
    }
    
    // 使用AppleScript获取Web内容
    private func getWebContentViaAppleScript() -> String? {
        print("[LOG] Attempting AppleScript Web content extraction")
        
        guard let browserInfo = getCurrentBrowserInfo() else { return nil }
        
        var script = ""
        
        switch browserInfo.bundleId {
        case "com.google.Chrome":
            script = """
                tell application "Google Chrome"
                    try
                        tell active tab of front window
                            set jsResult to execute javascript "
                                var activeElement = document.activeElement;
                                if (activeElement) {
                                    var content = '';
                                    if (activeElement.tagName === 'INPUT' || activeElement.tagName === 'TEXTAREA') {
                                        // 对于表单元素，获取完整的value
                                        content = activeElement.value || '';
                                    } else if (activeElement.contentEditable === 'true') {
                                        // 对于contenteditable元素，优先获取textContent保持换行
                                        content = activeElement.textContent || activeElement.innerText || '';
                                    }
                                    // 确保保留换行符
                                    return content;
                                } else {
                                    return '';
                                }
                            "
                            return jsResult
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
                            set jsResult to do JavaScript "
                                var activeElement = document.activeElement;
                                if (activeElement) {
                                    var content = '';
                                    if (activeElement.tagName === 'INPUT' || activeElement.tagName === 'TEXTAREA') {
                                        // 对于表单元素，获取完整的value
                                        content = activeElement.value || '';
                                    } else if (activeElement.contentEditable === 'true') {
                                        // 对于contenteditable元素，优先获取textContent保持换行
                                        content = activeElement.textContent || activeElement.innerText || '';
                                    }
                                    // 确保保留换行符
                                    return content;
                                } else {
                                    return '';
                                }
                            "
                            return jsResult
                        end tell
                    on error
                        return ""
                    end try
                end tell
            """
        default:
            return nil
        }
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)
            
            if let error = error {
                print("[LOG] AppleScript error: \(error)")
                return nil
            }
            
            let content = result.stringValue ?? ""
            if !content.isEmpty {
                print("[LOG] AppleScript got content: \(content)")
                return content
            }
        }
        
        return nil
    }

    // 获取当前焦点输入框
    func getFocusedElement() -> AXUIElement? {
        let sysWide = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        AXUIElementCopyAttributeValue(sysWide, kAXFocusedApplicationAttribute as CFString, &focusedApp)
        guard let app = focusedApp else {
            print("[LOG] No focused app found")
            return nil
        }
        var focusedElem: CFTypeRef?
        AXUIElementCopyAttributeValue(app as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElem)
        if let elem = focusedElem {
            print("[LOG] Focused element found")
            return (elem as! AXUIElement)
        }
        print("[LOG] No focused element found")
        return nil
    }

    // 获取输入框内容
    func getValue(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        return value as? String
    }
    
    // 禁用输入
    func disableInput() {
        guard let focused = getFocusedElement() else {
            print("[LOG] No focused element to disable")
            return
        }
        
        isInputDisabled = true
        disabledElement = focused
        originalValue = getValue(of: focused)
        
        // 尝试设置为禁用状态（不是所有元素都支持）
        AXUIElementSetAttributeValue(focused, kAXEnabledAttribute as CFString, false as CFTypeRef)
        
        print("[LOG] Input disabled")
    }
    
    // 启用输入
    func enableInput() {
        guard isInputDisabled, let element = disabledElement else {
            print("[LOG] No disabled input to enable")
            return
        }
        
        // 恢复输入状态
        AXUIElementSetAttributeValue(element, kAXEnabledAttribute as CFString, true as CFTypeRef)
        
        isInputDisabled = false
        disabledElement = nil
        originalValue = nil
        
        print("[LOG] Input enabled")
    }

    // 替换输入框内容
    func replaceInput(with text: String) {
        print("[LOG] Replacing input with: \(text)")
        guard let focused = getFocusedElement() else {
            print("[LOG] No focused element to replace")
            return
        }
        
        // 检查是否在浏览器环境中
        let isWeb = isWebEnvironment()
        if let browserInfo = getCurrentBrowserInfo() {
            print("[LOG] Replacing content in browser: \(browserInfo.appName)")
        }
        
        if isWeb {
            // 使用Web专用的替换方法
            replaceWebInputContent(element: focused, text: text)
        } else {
            // 使用原有的桌面应用替换方法
            forceReplaceWithClipboard(element: focused, text: text)
        }
    }
    
    // Web输入框内容替换的专用方法
    private func replaceWebInputContent(element: AXUIElement, text: String) {
        print("[LOG] Using Web input replacement method")
        
        // 方法1: 尝试AppleScript + JavaScript进行精确替换
        if replaceViaAppleScriptJS(text: text) {
            print("[LOG] Successfully replaced via AppleScript + JavaScript")
            return
        }
        
        // 方法2: 回退到剪贴板方法，但增加额外的验证和重试
        replaceWebViaClipboardWithRetry(element: element, text: text)
    }
    
    // 使用AppleScript + JavaScript进行Web内容替换
    private func replaceViaAppleScriptJS(text: String) -> Bool {
        print("[LOG] Attempting AppleScript + JavaScript replacement")
        
        guard let browserInfo = getCurrentBrowserInfo() else { return false }
        
        // 转义JavaScript字符串中的特殊字符
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        
        var script = ""
        
        switch browserInfo.bundleId {
        case "com.google.Chrome":
            script = """
                tell application "Google Chrome"
                    try
                        tell active tab of front window
                            set jsResult to execute javascript "
                                var activeElement = document.activeElement;
                                if (activeElement && (activeElement.tagName === 'INPUT' || activeElement.tagName === 'TEXTAREA')) {
                                    // 对于标准输入框
                                    activeElement.value = '\(escapedText)';
                                    activeElement.focus();
                                    
                                    // 触发输入事件，确保React等框架能检测到变化
                                    var inputEvent = new Event('input', { bubbles: true });
                                    activeElement.dispatchEvent(inputEvent);
                                    
                                    var changeEvent = new Event('change', { bubbles: true });
                                    activeElement.dispatchEvent(changeEvent);
                                    
                                    // 设置光标到末尾
                                    activeElement.setSelectionRange(activeElement.value.length, activeElement.value.length);
                                    
                                    'success';
                                } else if (activeElement && activeElement.contentEditable === 'true') {
                                    // 对于contenteditable元素
                                    activeElement.innerHTML = '';
                                    activeElement.textContent = '\(escapedText)';
                                    activeElement.focus();
                                    
                                    // 移动光标到末尾
                                    var selection = window.getSelection();
                                    var range = document.createRange();
                                    range.selectNodeContents(activeElement);
                                    range.collapse(false);
                                    selection.removeAllRanges();
                                    selection.addRange(range);
                                    
                                    // 触发输入事件
                                    var inputEvent = new Event('input', { bubbles: true });
                                    activeElement.dispatchEvent(inputEvent);
                                    
                                    'success';
                                } else {
                                    'no_active_input';
                                }
                            "
                            return jsResult
                        end tell
                    on error errMsg
                        return "error: " & errMsg
                    end try
                end tell
            """
        case "com.apple.Safari":
            script = """
                tell application "Safari"
                    try
                        tell front document
                            set jsResult to do JavaScript "
                                var activeElement = document.activeElement;
                                if (activeElement && (activeElement.tagName === 'INPUT' || activeElement.tagName === 'TEXTAREA')) {
                                    activeElement.value = '\(escapedText)';
                                    activeElement.focus();
                                    
                                    var inputEvent = new Event('input', { bubbles: true });
                                    activeElement.dispatchEvent(inputEvent);
                                    
                                    var changeEvent = new Event('change', { bubbles: true });
                                    activeElement.dispatchEvent(changeEvent);
                                    
                                    activeElement.setSelectionRange(activeElement.value.length, activeElement.value.length);
                                    'success';
                                } else if (activeElement && activeElement.contentEditable === 'true') {
                                    activeElement.innerHTML = '';
                                    activeElement.textContent = '\(escapedText)';
                                    activeElement.focus();
                                    
                                    var selection = window.getSelection();
                                    var range = document.createRange();
                                    range.selectNodeContents(activeElement);
                                    range.collapse(false);
                                    selection.removeAllRanges();
                                    selection.addRange(range);
                                    
                                    var inputEvent = new Event('input', { bubbles: true });
                                    activeElement.dispatchEvent(inputEvent);
                                    'success';
                                } else {
                                    'no_active_input';
                                }
                            "
                            return jsResult
                        end tell
                    on error errMsg
                        return "error: " & errMsg
                    end try
                end tell
            """
        default:
            return false
        }
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)
            
            if let error = error {
                print("[LOG] AppleScript replacement error: \(error)")
                return false
            }
            
            let resultString = result.stringValue ?? ""
            print("[LOG] AppleScript replacement result: \(resultString)")
            
            return resultString == "success"
        }
        
        return false
    }
    
    // Web环境下的剪贴板替换，带重试机制
    private func replaceWebViaClipboardWithRetry(element: AXUIElement, text: String) {
        print("[LOG] Using Web clipboard replacement with retry")
        
        // 保存原始剪贴板内容
        let pasteboard = NSPasteboard.general
        let originalContent = pasteboard.string(forType: .string)
        
        // 设置新文本到剪贴板
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // 尝试多种选择和粘贴策略
        attemptWebReplace(attempt: 1) { [weak self] success in
            if !success {
                // 如果第一次失败，等待后重试
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self?.attemptWebReplace(attempt: 2) { _ in
                        // 无论成功失败，都恢复剪贴板
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            pasteboard.clearContents()
                            if let original = originalContent {
                                pasteboard.setString(original, forType: .string)
                            }
                            print("[LOG] Clipboard content restored")
                        }
                    }
                }
            } else {
                // 成功时立即恢复剪贴板
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    pasteboard.clearContents()
                    if let original = originalContent {
                        pasteboard.setString(original, forType: .string)
                    }
                    print("[LOG] Clipboard content restored")
                }
            }
        }
    }
    
    // 尝试Web替换的具体实现
    private func attemptWebReplace(attempt: Int, completion: @escaping (Bool) -> Void) {
        print("[LOG] Web replace attempt \(attempt)")
        
        // 策略1: 全选 + 粘贴
        simulateSelectAll()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.simulatePaste()
            
            // 策略2: 如果是第二次尝试，添加额外的焦点确认
            if attempt == 2 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // 额外的Tab+Shift+Tab来确保焦点
                    self.simulateTabFocus()
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.simulateSelectAll()
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.simulatePaste()
                            completion(true)
                        }
                    }
                }
            } else {
                completion(true)
            }
        }
    }
    
    // 模拟Tab焦点切换来确保输入框活跃
    private func simulateTabFocus() {
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Tab键
        if let tabDown = CGEvent(keyboardEventSource: source, virtualKey: 48, keyDown: true),
           let tabUp = CGEvent(keyboardEventSource: source, virtualKey: 48, keyDown: false) {
            
            tabDown.post(tap: .cghidEventTap)
            tabUp.post(tap: .cghidEventTap)
            
            // Shift+Tab返回
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let shiftTabDown = CGEvent(keyboardEventSource: source, virtualKey: 48, keyDown: true),
                   let shiftTabUp = CGEvent(keyboardEventSource: source, virtualKey: 48, keyDown: false) {
                    
                    shiftTabDown.flags = .maskShift
                    shiftTabUp.flags = .maskShift
                    
                    shiftTabDown.post(tap: .cghidEventTap)
                    shiftTabUp.post(tap: .cghidEventTap)
                }
            }
        }
    }
    
    // 获取选中文本属性
    private func getSelectedTextAttribute(of element: AXUIElement) -> String? {
        var selectedTextValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextValue)
        
        if result == .success, let text = selectedTextValue as? String {
            return text
        }
        
        return nil
    }
    
    // 使用剪贴板强力替换内容
    private func forceReplaceWithClipboard(element: AXUIElement, text: String) {
        print("[LOG] Using clipboard force replace method")
        
        // 保存当前剪贴板内容
        let pasteboard = NSPasteboard.general
        let originalContent = pasteboard.string(forType: .string)
        
        // 将新文本放入剪贴板
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // 选择全部内容 (Cmd+A)
        simulateSelectAll()
        
        // 等待一小段时间确保选择完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // 粘贴新内容 (Cmd+V)
            self.simulatePaste()
            
            // 恢复原始剪贴板内容
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                pasteboard.clearContents()
                if let original = originalContent {
                    pasteboard.setString(original, forType: .string)
                }
                print("[LOG] Clipboard content restored")
            }
        }
    }
    
    // 模拟 Cmd+A 全选
    private func simulateSelectAll() {
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
            
            cmdDown.post(tap: .cghidEventTap)
            aDown.post(tap: .cghidEventTap)
            aUp.post(tap: .cghidEventTap)
            cmdUp.post(tap: .cghidEventTap)
            
            print("[LOG] Simulated Cmd+A select all")
        }
    }
    
    // 模拟 Cmd+V 粘贴
    private func simulatePaste() {
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
            
            cmdDown.post(tap: .cghidEventTap)
            vDown.post(tap: .cghidEventTap)
            vUp.post(tap: .cghidEventTap)
            cmdUp.post(tap: .cghidEventTap)
            
            print("[LOG] Simulated Cmd+V paste")
        }
    }
} 