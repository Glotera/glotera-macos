import Cocoa
import Carbon
import CoreFoundation
import ApplicationServices

struct AppInfo {
    let bundleId: String
    let appName: String
    let isBrowser: Bool
    let isWeChat: Bool
    let isChrome: Bool
    var javaScriptPermissionsEnabled: Bool
}

class AXController {
    static let shared = AXController()
    private var isInputDisabled = false
    private var originalValue: String?
    private var disabledElement: AXUIElement?
    private var lastManuallyFocusedElement: AXUIElement?
    
    // 选中文本监听相关变量
    private var isSelectionMonitoringPaused = false

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
    
    // MARK: - Public Info Getters
    
    // 检查当前活跃应用是否为浏览器
    func getCurrentBrowserInfo() -> (bundleId: String, appName: String)? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return nil
        }
        
        if browserBundleIds.contains(bundleId) {
            return (bundleId: bundleId, appName: frontmostApp.localizedName ?? "Browser")
        }
        
        return nil
    }
    
    // 获取指定元素的应用信息
    func getAppInfo(for element: AXUIElement) -> AppInfo {
        let pid = getPid(for: element)
        var appName = "Unknown"
        var bundleId = ""
        
        if let app = NSRunningApplication(processIdentifier: pid) {
            appName = app.localizedName ?? "Unknown"
            bundleId = app.bundleIdentifier ?? ""
        }
        
        let isBrowser = browserBundleIds.contains(bundleId)
        let isWeChat = bundleId.contains("wechat") || bundleId.contains("WeChat")
        let isChrome = bundleId == "com.google.Chrome"
        
        // 检查Chrome的JavaScript权限
        var jsEnabled = false
        if isChrome {
            jsEnabled = checkChromeJavaScriptPermission()
        }
        
        return AppInfo(
            bundleId: bundleId,
            appName: appName,
            isBrowser: isBrowser,
            isWeChat: isWeChat,
            isChrome: isChrome,
            javaScriptPermissionsEnabled: jsEnabled
        )
    }
    
    // 获取元素的PID
    func getPid(for element: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        let result = AXUIElementGetPid(element, &pid)
        if result != .success {
            Logger.error("Failed to get PID for element")
        }
        return pid
    }
    
    // 检查是否在Web环境中
    func isWebEnvironment() -> Bool {
        return getCurrentBrowserInfo() != nil
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
        
        // 检查是否在浏览器环境中
        let isWeb = isWebEnvironment()
        if let browserInfo = getCurrentBrowserInfo() {
            Logger.info("Detected browser environment: \(browserInfo.appName) (\(browserInfo.bundleId))")
        }
        
        // 获取输入框内容，使用Web环境特殊处理
        guard let value = getValueWithWebSupport(of: focused, isWeb: isWeb) else {
            Logger.warn("No value found in focused element")
            
            // 尝试备用方法获取内容
            Logger.info("Trying alternative content retrieval methods...")
            if let alternativeValue = getAlternativeValue(of: focused) {
                Logger.info("Got content via alternative method: '\(alternativeValue)'")    
                return processContentForTrigger(alternativeValue)
            }
            
            return nil
        }
        
        return processContentForTrigger(value)
    }
    
    // 处理内容以检测触发器
    private func processContentForTrigger(_ value: String) -> (text: String, lang: String)? {
         
        // 显示换行符位置以便调试
        let lineBreaks = value.enumerated().compactMap { $0.element == "\n" ? $0.offset : nil }
        if !lineBreaks.isEmpty {
            Logger.info("Newlines found at positions: \(lineBreaks)")
            Logger.info("Value: \(value)")
        }
        
        // 预处理内容：清理可能的干扰文本
        let cleanedValue = preprocessContent(value) 
        Logger.info("xxx1")
        // 使用配置管理器获取所有触发器
        let allTriggers = getAllConfiguredTriggers()
        if allTriggers.isEmpty {
            Logger.warn("No configured triggers found, falling back to default patterns")
            return processContentWithDefaultTriggers(cleanedValue)
        }
        Logger.info("xxx2")
        // 动态生成正则表达式模式
        // let patterns = generateTriggerPatterns(triggers: allTriggers)
        
        // 检查每个触发器
        for trigger in allTriggers {
            if let result = checkForTrigger(trigger, in: cleanedValue) {
                Logger.info("Trigger found: '\(trigger)' -> text='\(result.text)', lang='\(result.lang)'")
                return result
            }
        } 
        Logger.info("xxx3")
        return nil
    }
    
    // 获取所有配置的触发器
    private func getAllConfiguredTriggers() -> [String] {
        let configs = LanguageConfigManager.shared.loadLanguageConfigs()
        var allTriggers: [String] = []
        
        for config in configs {
            allTriggers.append(contentsOf: config.triggers)
        }
         
        return allTriggers
    }
    
    // 检查特定触发器是否匹配
    private func checkForTrigger(_ trigger: String, in content: String) -> (text: String, lang: String)? {
        // 转义特殊字符
        let escapedTrigger = NSRegularExpression.escapedPattern(for: trigger)
        
        // 生成多种匹配模式
        let patterns = [
            #"(.*?)"# + escapedTrigger + #"\s*$"#,      // 标准模式
            #"^(.*?)"# + escapedTrigger + #"\s*$"#,     // 严格开头模式
            #"(.*?)\s+"# + escapedTrigger + #"\s*$"#,   // 空格分隔
            #"(?s)(.*?)"# + escapedTrigger + #"\s*$"#   // 多行支持
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let nsContent = content as NSString
                let results = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length))
                
                if let match = results.first, match.numberOfRanges >= 2 {
                    let textRange = match.range(at: 1)
                    
                    if textRange.location != NSNotFound {
                        let rawText = nsContent.substring(with: textRange)
                        let text = rawText.trimmingCharacters(in: .whitespaces)
                        
                        if !text.isEmpty {
                            // 根据触发器查找对应的语言代码
                            if let languageCode = LanguageConfigManager.shared.findLanguageCode(for: trigger) {
                                return (text: text, lang: languageCode)
                            }
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    // 生成触发器模式（保留用于兼容性，但现在不使用）
    private func generateTriggerPatterns(triggers: [String]) -> [String] {
        // 这个方法现在不再使用，但保留以防需要
        return []
    }
    
    // 为JavaScript生成触发器模式
    private func generateJavaScriptPatterns(for triggers: [String]) -> [String] {
        guard !triggers.isEmpty else {
            // 如果没有配置的触发器，返回默认模式（简化版本）
            return [
                "(.*?)[@#](id|en|zh|ja|jp|ko|fr|de|es|ru|th)\\s*$"
            ]
        }
        
        var patterns: [String] = []
        
        // 为每个触发器生成模式
        for trigger in triggers {
            // 简化转义：只转义真正需要的字符
            let escapedTrigger = trigger
                .replacingOccurrences(of: "\\", with: "\\\\")   // 反斜杠
                .replacingOccurrences(of: ".", with: "\\.")     // 点号
                .replacingOccurrences(of: "*", with: "\\*")     // 星号
                .replacingOccurrences(of: "+", with: "\\+")     // 加号
                .replacingOccurrences(of: "?", with: "\\?")     // 问号
                .replacingOccurrences(of: "^", with: "\\^")     // 脱字符
                .replacingOccurrences(of: "$", with: "\\$")     // 美元符
                .replacingOccurrences(of: "{", with: "\\{")     // 左大括号
                .replacingOccurrences(of: "}", with: "\\}")     // 右大括号
                .replacingOccurrences(of: "[", with: "\\[")     // 左方括号
                .replacingOccurrences(of: "]", with: "\\]")     // 右方括号
                .replacingOccurrences(of: "(", with: "\\(")     // 左圆括号
                .replacingOccurrences(of: ")", with: "\\)")     // 右圆括号
                .replacingOccurrences(of: "|", with: "\\|")     // 管道符
            
            // 只生成一个标准模式，减少复杂性
            patterns.append("(.*?)" + escapedTrigger + "\\s*$")
        }
        
        Logger.info("Generated \(patterns.count) JavaScript patterns for \(triggers.count) triggers")
        
        return patterns
    }
    
    // 生成JavaScript代码用于动态模式匹配
    private func generateJavaScriptPatternCode(for triggers: [String]) -> String {
        // 获取所有语言代码，避免硬编码
        let allLanguageCodes = getAllLanguageCodes()
        
        // 将语言代码转换为安全的 JavaScript 字符串
        let languageList = allLanguageCodes.map { "'\($0)'" }.joined(separator: ",")
        
        // 使用模板方式生成 JavaScript 代码，避免复杂的字符串转义
        let jsCode = """
            var languageCodes = [\(languageList)];
            var patterns = [
                new RegExp('(.*?)[@#](' + languageCodes.join('|') + ')\\\\s*$', 'i'),
                new RegExp('(.*?)\\\\s+[@#](' + languageCodes.join('|') + ')\\\\s*$', 'i')
            ];
        """
        
        Logger.info("Generated JavaScript patterns for \(allLanguageCodes.count) languages")
        return jsCode
    }
    
    // 获取所有支持的语言代码
    private func getAllLanguageCodes() -> [String] {
        // 直接调用当前类的方法获取所有触发器
        let allTriggers = getAllConfiguredTriggers()
        
        // 从触发器中提取语言代码（去掉 @ 和 # 前缀）
        let languageCodes = Set(allTriggers.compactMap { trigger in
            if trigger.hasPrefix("@") || trigger.hasPrefix("#") {
                return String(trigger.dropFirst())
            }
            return nil
        })
        
        if !languageCodes.isEmpty { 
            return Array(languageCodes).sorted()
        }
        
        Logger.warn("No configured triggers found, using fallback language list")
        // 如果无法从配置获取，使用备用的主要语言列表
        return [
            "af", "am", "ar", "az", "be", "bg", "bn", "bo", "bs", "ca", "ceb", "cs", "cy", "da", "de", "el", "en",
            "eo", "es", "et", "eu", "fa", "fi", "fil", "fr", "fy", "ga", "gd", "gl", "gu", "ha", "haw", "he", "hi",
            "hmn", "hr", "ht", "hu", "hy", "id", "ig", "is", "it", "ja", "jw", "ka", "kk", "km", "kn", "ko", "ku",
            "ky", "la", "lb", "lo", "lt", "lv", "mg", "mi", "mk", "ml", "mn", "mr", "ms", "mt", "my", "ne", "nl",
            "no", "ny", "or", "pa", "pl", "ps", "pt", "ro", "ru", "rw", "si", "sk", "sl", "sm", "sn", "so", "sq",
            "sr", "st", "su", "sv", "sw", "ta", "te", "tg", "th", "tk", "tl", "tr", "tt", "ug", "uk", "ur", "uz",
            "vi", "xh", "yi", "yo", "zh", "zu"
        ]
    }
    
    // 安全地转义 AppleScript 中的字符串内容
    private func escapeForAppleScript(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")    // 反斜杠
            .replacingOccurrences(of: "\"", with: "\\\"")    // 双引号
            .replacingOccurrences(of: "\n", with: "\\n")     // 换行符
            .replacingOccurrences(of: "\r", with: "\\r")     // 回车符
            .replacingOccurrences(of: "\t", with: "\\t")     // 制表符
    }
    
    // 生成Chrome浏览器的AppleScript
    private func generateChromeScript(escapedText: String, jsPatternCode: String) -> String {
        // 对 JavaScript 代码进行额外的 AppleScript 转义
        let safeJsPatternCode = escapeForAppleScript(jsPatternCode)
        let safeEscapedText = escapeForAppleScript(escapedText)
         
        Logger.info("Safe escaped text: '\(safeEscapedText)'")
        
        return """
            tell application "Google Chrome"
                try
                    tell active tab of front window
                        set jsResult to execute javascript "
                            console.log('Starting precise text replacement...');
                            var activeElement = document.activeElement;
                            console.log('Active element:', activeElement);
                            
                            if (activeElement && (activeElement.tagName === 'INPUT' || activeElement.tagName === 'TEXTAREA')) {
                                console.log('Found INPUT/TEXTAREA element');
                                var currentValue = activeElement.value;
                                console.log('Current value:', currentValue);
                                
                                \(safeJsPatternCode)
                                
                                var replaced = false;
                                for (var i = 0; i < patterns.length; i++) {
                                    var match = currentValue.match(patterns[i]);
                                    if (match) {
                                        console.log('Pattern matched:', match);
                                        var originalText = match[1].trim();
                                        console.log('Original text to replace:', originalText);
                                        console.log('Replacement text:', '\(safeEscapedText)');
                                        
                                        // 精确替换：只替换触发器部分
                                        var newValue = currentValue.replace(patterns[i], '\(safeEscapedText)');
                                        activeElement.value = newValue;
                                        
                                        // 设置光标位置到文本末尾
                                        var cursorPos = '\(safeEscapedText)'.length;
                                        activeElement.setSelectionRange(cursorPos, cursorPos);
                                        activeElement.focus();
                                        
                                        // 触发事件
                                        var inputEvent = new Event('input', { bubbles: true });
                                        activeElement.dispatchEvent(inputEvent);
                                        var changeEvent = new Event('change', { bubbles: true });
                                        activeElement.dispatchEvent(changeEvent);
                                        
                                        console.log('Text precisely replaced from:', currentValue, 'to:', newValue);
                                        replaced = true;
                                        break;
                                    }
                                }
                                
                                return replaced ? 'success' : 'no_pattern_match';
                                
                            } else if (activeElement && activeElement.contentEditable === 'true') {
                                console.log('Found contentEditable element');
                                var currentContent = activeElement.textContent || activeElement.innerText || '';
                                console.log('Current content:', currentContent);
                                
                                \(safeJsPatternCode)
                                
                                var replaced = false;
                                for (var i = 0; i < patterns.length; i++) {
                                    var match = currentContent.match(patterns[i]);
                                    if (match) {
                                        console.log('ContentEditable pattern matched:', match);
                                        
                                        // 清空内容并设置新内容
                                        activeElement.textContent = '\(safeEscapedText)';
                                        
                                        // 设置光标到末尾
                                        var range = document.createRange();
                                        var sel = window.getSelection();
                                        range.selectNodeContents(activeElement);
                                        range.collapse(false);
                                        sel.removeAllRanges();
                                        sel.addRange(range);
                                        
                                        activeElement.focus();
                                        
                                        // 触发事件
                                        var inputEvent = new Event('input', { bubbles: true });
                                        activeElement.dispatchEvent(inputEvent);
                                        
                                        console.log('ContentEditable text replaced to:', '\(safeEscapedText)');
                                        replaced = true;
                                        break;
                                    }
                                }
                                
                                return replaced ? 'success' : 'no_pattern_match';
                            } else {
                                console.log('No suitable active input element found');
                                return 'no_active_input';
                            }
                        "
                        return jsResult
                    end tell
                on error errMsg
                    return "error: " & errMsg
                end try
            end tell
        """
    }
    
    // 为Swift生成触发器模式
    private func generateSwiftPatterns(for triggers: [String]) -> [String] {
        guard !triggers.isEmpty else {
            // 如果没有配置的触发器，返回默认模式
            return [
                #"(.*?)[@#](id|en|zh|ja|jp|ko|fr|de|es|ru|th)\s*$"#,
                #"^(.*?)[@#](id|en|zh|ja|jp|ko|fr|de|es|ru|th)\s*$"#,
                #"(.*?)\s+[@#](id|en|zh|ja|jp|ko|fr|de|es|ru|th)\s*$"#
            ]
        }
        
        var patterns: [String] = []
        
        // 为每个触发器生成模式
        for trigger in triggers {
            // 转义Swift正则表达式中的特殊字符
            let escapedTrigger = NSRegularExpression.escapedPattern(for: trigger)
            
            // 生成不同的匹配模式
            patterns.append("(.*?)" + escapedTrigger + "\\s*$")      // 标准模式
            patterns.append("^(.*?)" + escapedTrigger + "\\s*$")     // 严格开头模式
            patterns.append("(.*?)\\s+" + escapedTrigger + "\\s*$")  // 空格分隔
        }
        
        return patterns
    }
    
    // 生成Safari浏览器的AppleScript
    private func generateSafariScript(escapedText: String, jsPatternCode: String) -> String {
        // 对 Safari 也使用相同的安全转义方式
        let safeJsPatternCode = escapeForAppleScript(jsPatternCode)
        let safeEscapedText = escapeForAppleScript(escapedText)
        
        return """
            tell application "Safari"
                try
                    tell front document
                        set jsResult to do JavaScript "
                            console.log('Starting precise text replacement...');
                            var activeElement = document.activeElement;
                            console.log('Active element:', activeElement);
                            
                            if (activeElement && (activeElement.tagName === 'INPUT' || activeElement.tagName === 'TEXTAREA')) {
                                console.log('Found INPUT/TEXTAREA element');
                                var currentValue = activeElement.value;
                                console.log('Current value:', currentValue);
                                
                                \(safeJsPatternCode)
                                
                                var replaced = false;
                                for (var i = 0; i < patterns.length; i++) {
                                    var match = currentValue.match(patterns[i]);
                                    if (match) {
                                        console.log('Pattern matched:', match);
                                        var originalText = match[1].trim();
                                        console.log('Original text to replace:', originalText);
                                        console.log('Replacement text:', '\(safeEscapedText)');
                                        
                                        // 精确替换：只替换触发器部分
                                        var newValue = currentValue.replace(patterns[i], '\(safeEscapedText)');
                                        activeElement.value = newValue;
                                        
                                        // 设置光标位置到文本末尾
                                        var cursorPos = '\(safeEscapedText)'.length;
                                        activeElement.setSelectionRange(cursorPos, cursorPos);
                                        activeElement.focus();
                                        
                                        // 触发事件
                                        var inputEvent = new Event('input', { bubbles: true });
                                        activeElement.dispatchEvent(inputEvent);
                                        var changeEvent = new Event('change', { bubbles: true });
                                        activeElement.dispatchEvent(changeEvent);
                                        
                                        console.log('Text precisely replaced from:', currentValue, 'to:', newValue);
                                        replaced = true;
                                        break;
                                    }
                                }
                                
                                return replaced ? 'success' : 'no_pattern_match';
                                
                            } else if (activeElement && activeElement.contentEditable === 'true') {
                                console.log('Found contentEditable element');
                                var currentContent = activeElement.textContent || activeElement.innerText || '';
                                console.log('Current content:', currentContent);
                                
                                \(safeJsPatternCode)
                                
                                var replaced = false;
                                for (var i = 0; i < patterns.length; i++) {
                                    var match = currentContent.match(patterns[i]);
                                    if (match) {
                                        console.log('ContentEditable pattern matched:', match);
                                        
                                        // 清空内容并设置新内容
                                        activeElement.textContent = '\(safeEscapedText)';
                                        
                                        // 设置光标到末尾
                                        var range = document.createRange();
                                        var sel = window.getSelection();
                                        range.selectNodeContents(activeElement);
                                        range.collapse(false);
                                        sel.removeAllRanges();
                                        sel.addRange(range);
                                        
                                        activeElement.focus();
                                        
                                        // 触发事件
                                        var inputEvent = new Event('input', { bubbles: true });
                                        activeElement.dispatchEvent(inputEvent);
                                        
                                        console.log('ContentEditable text replaced to:', '\(safeEscapedText)');
                                        replaced = true;
                                        break;
                                    }
                                }
                                
                                return replaced ? 'success' : 'no_pattern_match';
                            } else {
                                console.log('No suitable active input element found');
                                return 'no_active_input';
                            }
                        "
                        return jsResult
                    end tell
                on error errMsg
                    return "error: " & errMsg
                end try
            end tell
        """
    }
    
    // 使用默认触发器的后备方法
    private func processContentWithDefaultTriggers(_ content: String) -> (text: String, lang: String)? {
        Logger.info("Using fallback default trigger processing")
        
        // 默认触发器模式
        let patterns = [
            #"(.*?)[@#](id|en|zh|ja|jp|ko|fr|de|es|ru|th)\s*$"#,      // 标准模式
            #"^(.*?)[@#](id|en|zh|ja|jp|ko|fr|de|es|ru|th)\s*$"#,     // 严格开头模式
            #"(.*?)\s+[@#](id|en|zh|ja|jp|ko|fr|de|es|ru|th)\s*$"#,   // 空格分隔
            #"(?s)(.*?)[@#](id|en|zh|ja|jp|ko|fr|de|es|ru|th)\s*$"#   // 多行支持
        ]
        
        for (index, pattern) in patterns.enumerated() {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let nsValue = content as NSString
                let results = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsValue.length))
                
                if let match = results.first, match.numberOfRanges >= 3 {
                    let textRange = match.range(at: 1)
                    let langRange = match.range(at: 2)
                    
                    if textRange.location != NSNotFound && langRange.location != NSNotFound {
                        let rawText = nsValue.substring(with: textRange)
                        let text = rawText.trimmingCharacters(in: .whitespaces)
                        var lang = nsValue.substring(with: langRange).lowercased()
                        
                        // 转换 jp 为 ja
                        if lang == "jp" { lang = "ja" }
                        
                        if !text.isEmpty {
                            Logger.info("Default trigger found using pattern \(index + 1): text='\(text)', lang='\(lang)'")
                            return (text: text, lang: lang)
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    // 获取触发器周围的上下文
    private func getContextAroundTrigger(_ content: String, trigger: String) -> String {
        let lowercased = content.lowercased()
        if let range = lowercased.range(of: trigger) {
            let start = max(content.startIndex, content.index(range.lowerBound, offsetBy: -20, limitedBy: content.startIndex) ?? content.startIndex)
            let end = min(content.endIndex, content.index(range.upperBound, offsetBy: 20, limitedBy: content.endIndex) ?? content.endIndex)
            return String(content[start..<end])
        }
        return ""
    }
    
    // 备用内容获取方法
    private func getAlternativeValue(of element: AXUIElement) -> String? {
        Logger.info("Trying alternative value retrieval methods")
        
        // 方法1: 尝试获取选中文本
        if let selectedText = getSelectedTextAttribute(of: element), !selectedText.isEmpty {
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
        if isWebEnvironment() {
            Logger.info("Forcing AppleScript retry for web content")
            // 等待一小段时间后重试
            Thread.sleep(forTimeInterval: 0.1)
            if let webContent = getWebContentViaAppleScript() {
                Logger.info("Got content via forced AppleScript retry: \(webContent)")
                return webContent
            }
        }
        
        Logger.warn("All alternative methods failed")
        return nil
    }
    
    // 预处理内容：清理可能的干扰文本
    private func preprocessContent(_ content: String) -> String {
        // 首先，执行通用清理，移除零宽空格等不可见字符，这对于修复飞书等Electron应用至关重要
        var cleaned = content.replacingOccurrences(of: "\u{200B}", with: "")
        if cleaned.count != content.count {
            Logger.info("Pre-processed content: Removed invisible characters.")
        }
        
        // 检查当前应用是否为Discord或其他聊天应用
        let isDiscordOrChat = isDiscordOrChatApp()
        
        // 对于Discord等聊天应用，使用更保守的清理策略
        if isDiscordOrChat {
            Logger.info("Detected Discord/Chat app - using conservative preprocessing")
            // 只进行基本的空格合并，不移除任何文本内容
            cleaned = cleaned.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned
        }
        
        // 对于其他应用（如Notion），使用更激进的清理策略
        // 移除常见的Notion界面元素文本
        // let notionInterferencePatterns = [
        //     "Add cover",
        //     "Add icon",
        //     "Add comment",
        //     "Untitled",
        //     "Type '/' for commands",
        //     "Press Enter to continue writing or type '/' for commands",
        //     "Empty page",
        //     "Start writing...",
        //     "Click to edit",
        //     "Add a page inside",
        //     "New page",
        //     "Template",
        //     "Import",
        //     "Database",
        //     "Gallery",
        //     "Board",
        //     "Timeline",
        //     "Calendar",
        //     "List"
        // ]
        
        // // 移除这些干扰文本（不区分大小写）
        // for pattern in notionInterferencePatterns {
        //     cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .caseInsensitive)
        // }
        
        // 移除表格相关的干扰内容
        // 匹配类似 "Column 1Column 2Column 3" 这样的表格标题
        // cleaned = cleaned.replacingOccurrences(of: #"Column\s*\d+"#, with: "", options: .regularExpression)
        
        // // 只合并连续的空格和制表符，保留换行符
        // cleaned = cleaned.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        
        // // 移除行首行尾的空白，但保留换行符
        // let lines = cleaned.components(separatedBy: .newlines)
        // let trimmedLines = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        // cleaned = trimmedLines.joined(separator: "\n")
        
        // // 最终去掉首尾空白
        // cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 如果清理后的内容太短或为空，返回原内容
        if cleaned.isEmpty || cleaned.count < 3 {
            return content
        }
        
        return cleaned
    }
    
    // 检查当前应用是否为Discord、聊天或终端应用
    func isDiscordOrChatApp() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        }
        
        let chatAppBundleIds = [
            "com.hnc.Discord",
            "com.discord.Discord",
            "com.tencent.xinWeChat",
            "com.apple.iChat",
            "com.microsoft.teams",
            "us.zoom.xos",
            "com.skype.skype",
            "org.whispersystems.signal-desktop",
            "com.tdesktop.Telegram"
        ]
        
        if chatAppBundleIds.contains(bundleId) {
            Logger.info("Detected chat app: \(frontmostApp.localizedName ?? "Unknown") (\(bundleId))")
            return true
        }

        if isTerminalApp() {
            return true
        }
        
        return false
    }

    // 新增：检查当前应用是否为终端
    func isTerminalApp() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        }
        
        let terminalBundleIds = [
            "com.googlecode.iterm2",    // iTerm2
            "com.apple.Terminal",       // Terminal.app
            "co.zeit.hyper",            // Hyper
            "io.alacritty",             // Alacritty
            "net.kovidgoyal.kitty"      // Kitty
        ]
        
        let result = terminalBundleIds.contains(bundleId)
        if result {
            Logger.info("Detected terminal app: \(frontmostApp.localizedName ?? "Unknown") (\(bundleId))")
        }
        return result
    }
    
    // 获取输入框内容，支持Web环境
    private func getValueWithWebSupport(of element: AXUIElement, isWeb: Bool) -> String? {
        var standardContent: String?
        var webContent: String?
        
        // 首先尝试标准方法
        if let value = getValue(of: element) {
            standardContent = value
            Logger.info("Got content via standard method: \(value.count) chars")
        }
        
        // 如果在Web环境中，同时尝试Web方法
        if isWeb {
            // 优先尝试AppleScript方法
            if let content = getWebContentViaAppleScript() {
                webContent = content
                Logger.info("Got content via AppleScript: \(content.count) chars")
            } else {
                // 如果AppleScript失败，尝试其他Web方法
                if let content = getWebInputValue(of: element) {
                    webContent = content
                    Logger.info("Got content via Web input value: \(content.count) chars")
                }
            }
        }
        
        // 选择最佳结果
        if let web = webContent, let standard = standardContent {
            // 如果两种方法都有结果，选择更长的或者非空的
            if web.count > standard.count {
                Logger.info("Using web content (longer): \(web.count) chars vs \(standard.count) chars")
                return web
            } else {
                Logger.info("Using standard content: \(standard.count) chars vs \(web.count) chars")
                return standard
            }
        } else if let web = webContent {
            Logger.info("Using web content (only available): \(web.count) chars")
            return web
        } else if let standard = standardContent {
            Logger.info("Using standard content (only available): \(standard.count) chars")
            return standard
        }
        
        Logger.warn("No content available from any method")
        return nil
    }
    
    // Web输入框内容获取的特殊方法
    private func getWebInputValue(of element: AXUIElement) -> String? { 
        // 方法1: 尝试获取选中文本（在Web输入框中很常见）
        if let selectedText = getSelectedTextAttribute(of: element), !selectedText.isEmpty {
            Logger.info("Got selected text: \(selectedText)")
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
                Logger.info("Got value from \(attribute): \(stringValue)")
                return stringValue
            }
        }
        
        Logger.warn("No content found via AX attributes")
        return nil
    }
    
    // 使用AppleScript获取Web内容
    private func getWebContentViaAppleScript() -> String? { 
        
        guard let browserInfo = getCurrentBrowserInfo() else { return nil }
        
        // 使用简化的JavaScript代码，避免复杂逻辑导致死锁
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
                                    if (activeElement.tagName === 'INPUT' || activeElement.tagName === 'TEXTAREA') {
                                        return activeElement.value || '';
                                    } else if (activeElement.contentEditable === 'true') {
                                        return activeElement.textContent || activeElement.innerText || '';
                                    }
                                }
                                return '';
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
                                    if (activeElement.tagName === 'INPUT' || activeElement.tagName === 'TEXTAREA') {
                                        return activeElement.value || '';
                                    } else if (activeElement.contentEditable === 'true') {
                                        return activeElement.textContent || activeElement.innerText || '';
                                    }
                                }
                                return '';
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
        
        // 使用同步执行，但添加简单的错误处理
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)
            
            if let error = error {
                Logger.error("AppleScript error: \(error)")
                return nil
            }
            
            let content = result.stringValue ?? ""
            if !content.isEmpty {
                Logger.info("AppleScript got content: \(content)")
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
            return nil
        }

        var focusedElem: CFTypeRef?
        AXUIElementCopyAttributeValue(app as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElem)
        if let elem = focusedElem { 
            return (elem as! AXUIElement)
        } 

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
            Logger.warn("No focused element to disable")
            return
        }
        
        isInputDisabled = true
        disabledElement = focused
        originalValue = getValue(of: focused)
        
        // 尝试设置为禁用状态（不是所有元素都支持）
        AXUIElementSetAttributeValue(focused, kAXEnabledAttribute as CFString, false as CFTypeRef)
        
        Logger.info("Input disabled")
    }
    
    // 启用输入
    func enableInput() {
        guard isInputDisabled, let element = disabledElement else {
            Logger.warn("No disabled input to enable")
            return
        }
        
        // 恢复输入状态
        AXUIElementSetAttributeValue(element, kAXEnabledAttribute as CFString, true as CFTypeRef)
        
        isInputDisabled = false
        disabledElement = nil
        originalValue = nil
        
        Logger.info("Input enabled")
    }

    // 替换输入框内容
    func replaceInput(with text: String, completion: (() -> Void)? = nil) {
        Logger.info("Replacing input with translation result")

        // 新增：针对AdsPower的特殊回填逻辑
        if isAdsPowerApp() {
            Logger.info("AdsPower detected. Using dedicated clipboard paste for replacement.")
            replaceAdsPowerInput(with: text, completion: completion)
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
        pauseSelectionMonitoring()
        // print("[LOG] Paused selection monitoring for auto-translation")
        
        // 检查是否在浏览器环境中
        let isWeb = isWebEnvironment()
        if let browserInfo = getCurrentBrowserInfo() {
            Logger.info("Replacing content in browser: \(browserInfo.appName)")
        }
        
        if isWeb {
            // 使用Web专用的替换方法
            replaceWebInputContent(element: focused, text: text) {
                completion?()
            }
        } else {
            // 检查是否是微信应用
            let isWeChat = isWeChatApp()
            if isWeChat {
                // 使用微信专用的替换方法
                Logger.info("Using WeChat-specific replacement method")
                replaceTextInWeChat(with: text) {
                completion?()
            }
        } else {
            // 使用原有的桌面应用替换方法
            forceReplaceWithClipboard(element: focused, text: text) {
                completion?()
                }
            }
        }
        
        // 延迟恢复选中文本监听，给文本替换足够的时间
        // 使用更长的延迟，确保自动翻译完全完成且文本状态稳定
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.resumeSelectionMonitoring()
            Logger.info("Resumed selection monitoring after auto-translation")
        }
    }
    
    // Web输入框内容替换的专用方法
    private func replaceWebInputContent(element: AXUIElement, text: String, completion: @escaping () -> Void) { 
        // 方法1: 尝试AppleScript + JavaScript进行精确替换 
       if replaceViaAppleScriptJS(text: text) {
           Logger.info("Successfully replaced via AppleScript + JavaScript")
           completion()
           return
       }
        
        Logger.warn("AppleScript + JavaScript failed, falling back to clipboard method")
        // 方法2: 回退到剪贴板方法，但增加额外的验证和重试
        replaceWebViaClipboardWithRetry(element: element, text: text, completion: completion)
    }
    
    // 使用AppleScript + JavaScript进行Web内容替换
    private func replaceViaAppleScriptJS(text: String) -> Bool { 
        
        guard let browserInfo = getCurrentBrowserInfo() else { 
            Logger.warn("No browser info available")
            return false 
        }
          
        // 转义JavaScript字符串中的特殊字符
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
         
        // 获取所有配置的触发器并生成JavaScript模式
        let allTriggers = getAllConfiguredTriggers()
        let jsPatternCode = generateJavaScriptPatternCode(for: allTriggers)
         
        var script = ""
        
        switch browserInfo.bundleId {
        case "com.google.Chrome":
            script = generateChromeScript(escapedText: escapedText, jsPatternCode: jsPatternCode)
        case "com.apple.Safari":
            script = generateSafariScript(escapedText: escapedText, jsPatternCode: jsPatternCode)
        default:
            Logger.warn("Unsupported browser: \(browserInfo.bundleId)")
            return false
        }
        
        Logger.info("Executing AppleScript...")
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)
            
            if let error = error {
                Logger.error("AppleScript replacement error: \(error)")
                return false
            }
            
            let resultString = result.stringValue ?? "" 
            if resultString == "success" {
                Logger.info("AppleScript replacement successful")
                return true
            } else {
                Logger.warn("AppleScript replacement failed with result: \(resultString)")
                return false
            }
        } else {
            Logger.warn("Failed to create AppleScript object")
            return false
        }
    }
    
        // Web环境下的剪贴板替换，简化版本（不恢复原剪贴板）
    private func replaceWebViaClipboardWithRetry(element: AXUIElement, text: String, completion: @escaping () -> Void) {
        Logger.info("Using simplified Web clipboard replacement") 
        
        // 首先尝试获取当前内容，确定需要替换的部分
        guard let currentValue = getValue(of: element) else {
            Logger.warn("Cannot get current value for precise replacement")
            completion()
            return
        }
        
        // 直接设置翻译文本到剪贴板
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let setSuccess = pasteboard.setString(text, forType: .string) 
        
        // 验证剪贴板设置成功
        let verifyContent = pasteboard.string(forType: .string) 
        if verifyContent != text {
            Logger.error("Clipboard verification failed - expected: '\(text)', got: '\(verifyContent ?? "nil")'")
            completion()
            return
        }
        
        // 使用精确选择和替换策略
        attemptPreciseWebReplace(element: element, originalValue: currentValue, translatedText: text, attempt: 1) { [weak self] success in
            if !success {
                // 如果第一次失败，等待后重试
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { 
                    pasteboard.clearContents()
                    let retrySetSuccess = pasteboard.setString(text, forType: .string)
                    Logger.info("Retry clipboard set success: \(retrySetSuccess)")
                    
                    self?.attemptPreciseWebReplace(element: element, originalValue: currentValue, translatedText: text, attempt: 2) { _ in
                        Logger.info("Translation replacement completed (retry)")
                        // 翻译操作完成后检查 Event Tap 状态
                        self?.checkAndRecoverEventTapAfterTranslation()
                        completion()
                    }
                }
            } else {
                Logger.info("Translation replacement completed (success)")
                // 翻译操作完成后检查 Event Tap 状态
                self?.checkAndRecoverEventTapAfterTranslation()
                completion()
            }
        }
    }
    
    // 精确的Web替换尝试（简化版本）
    private func attemptPreciseWebReplace(element: AXUIElement, originalValue: String, translatedText: String, attempt: Int, completion: @escaping (Bool) -> Void) {
         
        if selectTriggerTextViaJS(originalValue: originalValue) {
            Logger.info("Successfully selected trigger text via JavaScript")
            
            // 等待选择完成，然后粘贴
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                Logger.info("Simulating Cmd+V paste")
                self.simulatePaste()
                completion(true)
            }
        } else {
            Logger.warn("JavaScript selection failed, falling back to traditional method")
            
            // 回退到传统的全选+粘贴方法
            Logger.info("Simulating Cmd+A select all")
            simulateSelectAll()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                Logger.info("Simulating Cmd+V paste") 
                self.simulatePaste()
                completion(true)
            }
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
    
    // 使用JavaScript精确选择触发器文本
    private func selectTriggerTextViaJS(originalValue: String) -> Bool {
        guard let browserInfo = getCurrentBrowserInfo() else { 
            Logger.warn("No browser info for JS selection")
            return false 
        }
        
        // 获取所有配置的触发器并生成JavaScript模式
        let allTriggers = getAllConfiguredTriggers()
        let jsPatternCode = generateJavaScriptPatternCode(for: allTriggers) 
        
        var script = ""
        
        switch browserInfo.bundleId {
        case "com.google.Chrome":
            script = """
                tell application "Google Chrome"
                    try
                        tell active tab of front window
                            set jsResult to execute javascript "
                                console.log('Selecting trigger text for precise replacement...');
                                var activeElement = document.activeElement;
                                
                                if (activeElement && (activeElement.tagName === 'INPUT' || activeElement.tagName === 'TEXTAREA')) {
                                    var currentValue = activeElement.value;
                                    console.log('Current value for selection:', currentValue);
                                    
                                    \(jsPatternCode)
                                    
                                    for (var i = 0; i < patterns.length; i++) {
                                        var match = currentValue.match(patterns[i]);
                                        if (match) {
                                            console.log('Pattern matched for selection:', match);
                                            
                                            // 计算选择范围：从触发器开始到结尾
                                            var fullMatch = match[0];
                                            var startPos = currentValue.indexOf(fullMatch);
                                            var endPos = startPos + fullMatch.length;
                                            
                                            console.log('Selection range:', startPos, 'to', endPos);
                                            
                                            // 选择触发器部分
                                            activeElement.setSelectionRange(startPos, endPos);
                                            activeElement.focus();
                                            
                                            console.log('Trigger text selected successfully');
                                            return 'success';
                                        }
                                    }
                                    
                                    console.log('No trigger pattern found for selection');
                                    return 'no_pattern';
                                } else {
                                    console.log('No suitable input element for selection');
                                    return 'no_input';
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
                                console.log('Selecting trigger text for precise replacement...');
                                var activeElement = document.activeElement;
                                
                                if (activeElement && (activeElement.tagName === 'INPUT' || activeElement.tagName === 'TEXTAREA')) {
                                    var currentValue = activeElement.value;
                                    console.log('Current value for selection:', currentValue);
                                    
                                    \(jsPatternCode)
                                    
                                    for (var i = 0; i < patterns.length; i++) {
                                        var match = currentValue.match(patterns[i]);
                                        if (match) {
                                            console.log('Pattern matched for selection:', match);
                                            
                                            // 计算选择范围：从触发器开始到结尾
                                            var fullMatch = match[0];
                                            var startPos = currentValue.indexOf(fullMatch);
                                            var endPos = startPos + fullMatch.length;
                                            
                                            console.log('Selection range:', startPos, 'to', endPos);
                                            
                                            // 选择触发器部分
                                            activeElement.setSelectionRange(startPos, endPos);
                                            activeElement.focus();
                                            
                                            console.log('Trigger text selected successfully');
                                            return 'success';
                                        }
                                    }
                                    
                                    console.log('No trigger pattern found for selection');
                                    return 'no_pattern';
                                } else {
                                    console.log('No suitable input element for selection');
                                    return 'no_input';
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
            Logger.warn("Unsupported browser for JS selection: \(browserInfo.bundleId)")
            return false
        }
        
        Logger.info("Executing selection AppleScript...")
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)
            
            if let error = error {
                Logger.error("AppleScript selection error: \(error)")
                return false
            }
            
            let resultString = result.stringValue ?? ""
            Logger.info("AppleScript selection result: '\(resultString)'")
            
            return resultString == "success"
        } else {
            Logger.warn("Failed to create selection AppleScript object")
            return false
        }
    }
    

    
    // 获取选中文本属性
    private func getSelectedTextAttribute(of element: AXUIElement) -> String? {
        let startTime = Date()
        
        var selectedTextValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextValue)
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        // 性能监控：如果处理时间过长，记录警告
        if processingTime > 0.2 {
            Logger.warn("AXUIElementCopyAttributeValue took \(String(format: "%.3f", processingTime))s - performance warning")
        }
        
        if result == .success, let text = selectedTextValue as? String {
            // 对于极大的选中文本，截断以避免后续处理问题
            if text.count > 10000 {
                Logger.warn("Selected text too large (\(text.count) chars), truncating to 10000 chars")
                let endIndex = text.index(text.startIndex, offsetBy: 10000)
                return String(text[..<endIndex])
            }
            return text
        }
        
        return nil
    }
    
    // 检查元素是否可编辑
    func isElementEditable(_ element: AXUIElement) -> Bool {
        // 检查当前应用是否是微信
        let isWeChat = isWeChatApp()
        
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
            
            Logger.info("Element role: \(roleString), isWeChat: \(isWeChat)")
            
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
            
            // 对于StaticText，需要进一步检查是否可编辑
            if roleString == "AXStaticText" {
                // 检查是否有编辑相关的属性
                var isEditable: CFTypeRef?
                let editableResult = AXUIElementCopyAttributeValue(element, "AXEnabled" as CFString, &isEditable)
                if editableResult == .success, let enabled = isEditable as? Bool {
                    return enabled
                }
                // StaticText通常不可编辑，除非特别标记
                return false
            }
        }
        
        // 在Web环境中，通过JavaScript检查
        if isWebEnvironment() {
            return isWebElementEditable()
        }
        
        // 默认假设不可编辑
        return false
    }
    
    // 检查当前应用是否是微信
    private func isWeChatApp() -> Bool {
        if let frontmostApp = NSWorkspace.shared.frontmostApplication,
           let bundleId = frontmostApp.bundleIdentifier {
            return bundleId.contains("wechat") || bundleId.contains("WeChat")
        }
        return false
    }
    
    // 微信特殊文本替换方法
    private func replaceTextInWeChat(with text: String, completion: @escaping () -> Void) { 
        
        let pasteboard = NSPasteboard.general
        let originalClipboard = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            Logger.warn("WeChat: Failed to set clipboard")
            restoreClipboardContent(originalClipboard)
            completion()
            return
        }

        // 核心流程：激活微信 -> 全选 -> 粘贴
        ensureWeChatAppFocus { focused in
            guard focused else {
                Logger.warn("WeChat: Failed to focus app.")
                self.restoreClipboardContent(originalClipboard)
                completion()
                return
            }
            
            // 等待焦点稳定
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                Logger.info("WeChat: Sending Cmd+A to select text.")
                self.sendWeChatSelectAllCommand()
                
                // 等待全选完成
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    Logger.info("WeChat: Sending paste command.")
                    self.sendWeChatPasteCommand()
                    
                    // 延迟恢复剪贴板，确保粘贴完成
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.restoreClipboardContent(originalClipboard)
                        // 翻译操作完成后检查 Event Tap 状态
                        self.checkAndRecoverEventTapAfterTranslation()
                        completion()
                    }
                }
            }
        }
    }
    
    // 确保微信应用获得焦点
    private func ensureWeChatAppFocus(completion: @escaping (Bool) -> Void) {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier,
              bundleId.contains("wechat") || bundleId.contains("WeChat") else {
            Logger.warn("WeChat: Not currently focused")
            completion(false)
            return
        }
         
        completion(true)
    }
    
    // 发送微信专用的Cmd+A命令
    private func sendWeChatSelectAllCommand() {
        let source = CGEventSource(stateID: .hidSystemState)
        let cmdADown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0), keyDown: true) // A key
        cmdADown?.flags = CGEventFlags.maskCommand
        cmdADown?.post(tap: CGEventTapLocation.cghidEventTap)
        
        let cmdAUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0), keyDown: false) // A key
        cmdAUp?.flags = CGEventFlags.maskCommand
        cmdAUp?.post(tap: CGEventTapLocation.cghidEventTap)
        
        Logger.info("WeChat: Sent Cmd+A select all command")
    }
    
    // 发送微信专用的粘贴命令
    private func sendWeChatPasteCommand() {
        let source = CGEventSource(stateID: .hidSystemState)
        let cmdVDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(9), keyDown: true) // V key
        cmdVDown?.flags = CGEventFlags.maskCommand
        cmdVDown?.post(tap: CGEventTapLocation.cghidEventTap)
        
        let cmdVUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(9), keyDown: false) // V key
        cmdVUp?.flags = CGEventFlags.maskCommand
        cmdVUp?.post(tap: CGEventTapLocation.cghidEventTap)
        
        Logger.info("WeChat: Sent Cmd+V paste command")
    }
    
    // 恢复剪贴板内容
    private func restoreClipboardContent(_ originalClipboard: String?) {
        let pasteboard = NSPasteboard.general
        if let original = originalClipboard {
            pasteboard.clearContents()
            pasteboard.setString(original, forType: .string)
            Logger.info("WeChat: Restored original clipboard content: '\(original)'")
        } else {
            pasteboard.clearContents()
            Logger.info("WeChat: Cleared clipboard as there was no original content.")
        }
    }
    
    // 检查Web元素是否可编辑
    private func isWebElementEditable() -> Bool {
        guard let browserInfo = getCurrentBrowserInfo() else { return false }
        
        var script = ""
        
        switch browserInfo.bundleId {
        case "com.google.Chrome":
            script = """
                tell application "Google Chrome"
                    try
                        tell active tab of front window
                            set jsResult to execute javascript "
                                var activeElement = document.activeElement;
                                if (!activeElement) return false;
                                
                                // 检查是否是可编辑的输入元素
                                var editableTypes = ['input', 'textarea'];
                                if (editableTypes.includes(activeElement.tagName.toLowerCase())) {
                                    var inputType = activeElement.type ? activeElement.type.toLowerCase() : '';
                                    var nonEditableTypes = ['button', 'submit', 'reset', 'image', 'file', 'radio', 'checkbox'];
                                    return !nonEditableTypes.includes(inputType);
                                }
                                
                                // 检查contentEditable属性
                                if (activeElement.contentEditable === 'true') return true;
                                if (activeElement.isContentEditable) return true;
                                
                                // 检查是否有designMode
                                if (document.designMode === 'on') return true;
                                
                                return false;
                            "
                            return jsResult as boolean
                        end tell
                    on error
                        return false
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
                                if (!activeElement) return false;
                                
                                var editableTypes = ['input', 'textarea'];
                                if (editableTypes.includes(activeElement.tagName.toLowerCase())) {
                                    var inputType = activeElement.type ? activeElement.type.toLowerCase() : '';
                                    var nonEditableTypes = ['button', 'submit', 'reset', 'image', 'file', 'radio', 'checkbox'];
                                    return !nonEditableTypes.includes(inputType);
                                }
                                
                                if (activeElement.contentEditable === 'true') return true;
                                if (activeElement.isContentEditable) return true;
                                if (document.designMode === 'on') return true;
                                
                                return false;
                            "
                            return jsResult
                        end tell
                    on error
                        return false
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
                Logger.error("AppleScript error checking editability: \(error)")
                return false
            }
            
            return result.booleanValue
        }
        
        return false
    }

    // 获取当前选中的文本
    func getSelectedText() -> (text: String, element: AXUIElement)? {
        guard let focused = getFocusedElement() else {
            // print("[LOG] No focused element for selection")
            return nil
        }
        
        // 首先尝试通过AX API获取选中文本
        if let selectedText = getSelectedTextAttribute(of: focused), !selectedText.isEmpty {
            // Logger.debug("[LOG] Got selected text via AX: '\(selectedText)'")
            return (text: selectedText, element: focused)
        }
        
        // 如果在浏览器环境中，尝试通过JavaScript获取选中文本
        if isWebEnvironment() {
            if let selectedText = getWebSelectedText(), !selectedText.isEmpty {
                Logger.info("Got selected text via Web: '\(selectedText)'")
                return (text: selectedText, element: focused)
            }
        }
         
        return nil
    }
    
    // 通过JavaScript获取Web环境中的选中文本
    private func getWebSelectedText() -> String? {
        guard let browserInfo = getCurrentBrowserInfo() else { return nil }
        
        var script = ""
        
        switch browserInfo.bundleId {
        case "com.google.Chrome":
            script = """
                tell application "Google Chrome"
                    try
                        tell active tab of front window
                            set jsResult to execute javascript "
                                var selection = window.getSelection();
                                if (selection.rangeCount > 0) {
                                    return selection.toString();
                                }
                                return '';
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
                                var selection = window.getSelection();
                                if (selection.rangeCount > 0) {
                                    return selection.toString();
                                }
                                return '';
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
                Logger.error("AppleScript error getting selection: \(error)")
                return nil
            }
            
            let selectedText = result.stringValue ?? ""
            return selectedText.isEmpty ? nil : selectedText
        }
        
        return nil
    }
    
    // 开始监听选中文本变化
    func startSelectionMonitoring() {
        Logger.info("Starting selection monitoring (keyboard-event-safe)")
        
        // 延迟启动鼠标监听，确保键盘监听优先建立
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.startMouseEventMonitoring()
        }
        
        // 使用较低频率的定时器进一步减少对系统的影响
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            self.checkForTextSelection()
        }
    }
    
    private var lastSelectedText: String = ""
    private var lastSelectionCheckTime: Date = Date()
    private var isMenuShowing: Bool = false
    private var isMouseDragging: Bool = false
    private var lastMouseUpTime: Date = Date.distantPast
    private var mouseEventMonitor: Any?
    private var keyboardEventMonitor: Any?
    private var lastDoubleClickTime: Date = Date.distantPast
    private var lastCtrlATime: Date = Date.distantPast
    
    // 监听鼠标事件
    private func startMouseEventMonitoring() {
        // 监听鼠标事件，包括双击
        mouseEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged]) { [weak self] event in
            DispatchQueue.main.async {
                self?.handleMouseEvent(event)
            }
        }
        
        // 移除键盘事件监听，避免与 InputMonitor 的 CGEvent 监听冲突
        // keyboardEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
        //     DispatchQueue.main.async {
        //         self?.handleKeyboardEvent(event)
        //     }
        // }
        
        Logger.info("Mouse event monitoring started (keyboard monitoring delegated to InputMonitor)")
    }
    
    private func handleMouseEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            // 检测双击
            let now = Date()
            let timeSinceLastClick = now.timeIntervalSince(lastDoubleClickTime)
            
            if timeSinceLastClick < 0.5 && timeSinceLastClick > 0.1 {
                // 双击检测
                Logger.info("Double click detected")
                lastDoubleClickTime = now
                // 延迟检查双击选择的文本
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.checkForTextSelectionAfterDoubleClick()
                }
            } else {
                lastDoubleClickTime = now
            }
            
            // 重置拖拽状态
            isMouseDragging = false
            
        case .leftMouseDragged:
            // 鼠标拖拽中，标记为拖拽状态
            if !isMouseDragging {
                isMouseDragging = true
            }
            
        case .leftMouseUp:
            // 鼠标释放
            if isMouseDragging {
                lastMouseUpTime = Date()
                // 延迟检查，给文本选择时间稳定
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.checkForTextSelectionAfterMouseUp()
                }
            }
            isMouseDragging = false
            
        default:
            break
        }
    }
    
    // 检查文本选中状态
    private func checkForTextSelection() {
        // 如果选中文本监听被暂停，不执行任何操作
        if isSelectionMonitoringPaused {
            return
        }
        
        // 如果菜单正在显示，不要重复检查
        if isMenuShowing {
            return
        }
        
        // 如果正在拖拽鼠标，不要检查（等待拖拽完成）
        if isMouseDragging {
            return
        }
        
        // 如果刚刚完成鼠标拖拽，等待特殊检查方法处理
        let timeSinceMouseUp = Date().timeIntervalSince(lastMouseUpTime)
        if timeSinceMouseUp < 1.0 && lastMouseUpTime != Date.distantPast {
            return
        }
        
        // 防抖：至少间隔0.3秒才检查
        let now = Date()
        if now.timeIntervalSince(lastSelectionCheckTime) < 0.3 {
            return
        }
        lastSelectionCheckTime = now
        
        // 只在定时器检查时隐藏菜单，不显示菜单
        // 菜单只能通过鼠标拖拽选择后显示
        hideMenuIfNoSelection()
    }
    
    // 鼠标释放后的专门检查
    private func checkForTextSelectionAfterMouseUp() {
        Logger.info("Checking text selection after mouse up")
        
        // 等待一个更长的延迟，确保选择完全稳定
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // 只有在鼠标拖拽选择后才显示菜单
            self.checkSelectedTextAndShowMenuAfterMouseSelection()
        }
    }
    
    // 双击后的文本选择检查
    private func checkForTextSelectionAfterDoubleClick() {
        Logger.info("Checking text selection after double click")
        
        // 等待延迟，确保双击选择完全稳定
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.checkSelectedTextAndShowMenuAfterMouseSelection()
        }
    }
    
    // Cmd+A 后的文本选择检查
    private func checkForTextSelectionAfterCtrlA() {
        Logger.info("Checking text selection after Cmd+A")
        
        // 等待延迟，确保全选完全稳定
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.checkForTextSelectionAfterKeyboardSelection()
        }
    }
    
    // 用于跟踪最近的自动翻译操作
    private var lastAutoTranslationTime: Date = Date.distantPast
    private var lastAutoTranslationText: String = ""
    
    // 标记自动翻译开始
    func markAutoTranslationStart(withText text: String) {
        lastAutoTranslationTime = Date()
        lastAutoTranslationText = text
        // print("[LOG] Marked auto-translation start for text: '\(text)'")
    }
    
    // 检查文本是否可能是刚完成的自动翻译结果
    private func isLikelyTranslationResult(_ text: String) -> Bool {
        let timeSinceLastTranslation = Date().timeIntervalSince(lastAutoTranslationTime)
        
        // 只在最近5秒内进行过自动翻译时才检查
        if timeSinceLastTranslation > 5.0 {
            return false
        }
        
        // 检查文本是否与原始翻译文本相似或相关
        // 这里使用更保守的检查，避免误判
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalText = lastAutoTranslationText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 如果选中的文本长度与原始文本相近，可能是翻译结果
        if abs(trimmedText.count - originalText.count) < originalText.count / 3 {
            Logger.info("Detected potential translation result within 5s of auto-translation")
            return true
        }
        
        return false
    }

    // 只隐藏菜单，不显示菜单的逻辑
    private func hideMenuIfNoSelection() {
        let startTime = Date()
        
        guard let selection = getSelectedText() else {
            // 如果没有选中文本，隐藏菜单并重置状态
            if !lastSelectedText.isEmpty {
                TranslationMenuWindow.shared.hide()
                lastSelectedText = ""
                isMenuShowing = false
            }
            
            let processingTime = Date().timeIntervalSince(startTime)
            if processingTime > 0.2 {
                Logger.warn("hideMenuIfNoSelection took \(String(format: "%.3f", processingTime))s - performance warning")
            }
            return
        }
        
        // 如果选中文本发生变化，也隐藏菜单
        let originalText = selection.text
        if originalText != lastSelectedText && !lastSelectedText.isEmpty {
            TranslationMenuWindow.shared.hide()
            lastSelectedText = ""
            isMenuShowing = false
        }
        
        let processingTime = Date().timeIntervalSince(startTime)
        if processingTime > 0.2 {
            Logger.warn("hideMenuIfNoSelection took \(String(format: "%.3f", processingTime))s - performance warning")
        }
    }
    
    // 鼠标选择后的菜单显示逻辑
    private func checkSelectedTextAndShowMenuAfterMouseSelection() {
        checkSelectedTextAndShowMenu(selectionType: "mouse")
    }
    
    // 键盘选择后的菜单显示逻辑 - 改为 public 以便 InputMonitor 调用
    func checkForTextSelectionAfterKeyboardSelection() {
        checkSelectedTextAndShowMenu(selectionType: "keyboard")
    }
    
    // 统一的菜单显示逻辑
    private func checkSelectedTextAndShowMenu(selectionType: String) {
        // 如果选中文本监听被暂停，不执行任何操作
        if isSelectionMonitoringPaused {
            return
        }
        
        let startTime = Date()
        
        guard let selection = getSelectedText() else {
            // 如果没有选中文本，隐藏菜单并重置状态
            if !lastSelectedText.isEmpty {
                TranslationMenuWindow.shared.hide()
                lastSelectedText = ""
                isMenuShowing = false
            }
            
            let processingTime = Date().timeIntervalSince(startTime)
            if processingTime > 0.2 {
                Logger.warn("checkSelectedTextAndShowMenu (\(selectionType)) took \(String(format: "%.3f", processingTime))s - performance warning")
            }
            return
        }
        
        let processingTime = Date().timeIntervalSince(startTime)
        if processingTime > 0.2 {
            Logger.warn("checkSelectedTextAndShowMenu (\(selectionType)) AX API took \(String(format: "%.3f", processingTime))s - performance warning")
        }
        
        // 检查是否是刚刚完成的自动翻译结果，避免对翻译结果再次触发菜单
        if isLikelyTranslationResult(selection.text) {
            Logger.info("Skipping menu for likely translation result: '\(selection.text)'")
            return
        }
        
        // 过滤掉太短的选中文本，但保留原始文本格式
        let originalText = selection.text
        let trimmedForCheck = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedForCheck.count < 3 {
            if !lastSelectedText.isEmpty {
                TranslationMenuWindow.shared.hide()
                lastSelectedText = ""
                isMenuShowing = false
            }
            return
        }
        
        // 使用原始文本（保留前后空白）进行比较和传递
        if originalText != lastSelectedText {
            lastSelectedText = originalText
            isMenuShowing = true
            
            Logger.info("Selected text after \(selectionType) selection: '\(originalText)' (length: \(originalText.count))") 
            
            // 标记选中文本翻译开始，通知 InputMonitor
            InputMonitor.shared.markSelectionTranslationStart()
            
            // 获取选中文本的位置和应用信息
            let mouseLocation = NSEvent.mouseLocation
            let appInfo = getAppInfo(for: selection.element)
            
            // 显示翻译菜单，传递所需信息
            TranslationMenuWindow.shared.show(
                for: originalText,
                from: selection.element,
                at: mouseLocation,
                browserInfo: appInfo.isBrowser ? appInfo : nil
            )
            
            // 设置关闭回调
            TranslationMenuWindow.shared.onMenuClosed = { [weak self] in
                    self?.isMenuShowing = false
                    self?.lastSelectedText = ""
                Logger.info("Menu closed callback triggered")
                }
        }
    }
    
    // 使用剪贴板强力替换内容
    private func forceReplaceWithClipboard(element: AXUIElement, text: String, completion: @escaping () -> Void) {
        Logger.info("Using robust clipboard force replace method for standard apps.")
        
        // 1. 保存原始剪贴板内容
        let pasteboard = NSPasteboard.general
        let originalContent = pasteboard.string(forType: .string)
        
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
                self.restorePasteboardContent(originalContent)
                completion()
                return
            }
            
            // 5. 立即执行粘贴
            self.simulatePaste()
            
            // 6. 安排恢复剪贴板的操作
            // simulatePaste() 内部有0.2秒延迟，我们等待0.4秒以确保粘贴完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.restorePasteboardContent(originalContent)
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
    
    // 添加一个新的方法来重新选中文本，用于替换时保持选中状态
    func reselectText(in element: AXUIElement, with text: String) -> Bool {
        Logger.info("Attempting to reselect text for replacement")
        
        // 如果在Web环境中，使用JavaScript重新选中
        if isWebEnvironment() {
            return reselectWebText(with: text)
        }
        
        // 对于标准应用，尝试通过AX API选中所有文本
        return reselectStandardText(in: element, with: text)
    }
    
    private func reselectWebText(with originalText: String) -> Bool {
        guard let browserInfo = getCurrentBrowserInfo() else { return false }
        
        // 转义JavaScript字符串
        let escapedText = originalText
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
                                try {
                                    // 查找并选中包含原始文本的节点
                                    function findAndSelectText(text) {
                                        var walker = document.createTreeWalker(
                                            document.body,
                                            NodeFilter.SHOW_TEXT,
                                            null,
                                            false
                                        );
                                        
                                        var node;
                                        while (node = walker.nextNode()) {
                                            if (node.textContent.includes(text)) {
                                                var range = document.createRange();
                                                var startIndex = node.textContent.indexOf(text);
                                                range.setStart(node, startIndex);
                                                range.setEnd(node, startIndex + text.length);
                                                
                                                var selection = window.getSelection();
                                                selection.removeAllRanges();
                                                selection.addRange(range);
                                                return true;
                                            }
                                        }
                                        return false;
                                    }
                                    
                                    return findAndSelectText('\(escapedText)') ? 'success' : 'not_found';
                                } catch (e) {
                                    return 'error: ' + e.message;
                                }
                            "
                            return jsResult
                        end tell
                    on error errMsg
                        return "applescript_error: " & errMsg
                    end try
                end tell
            """
        case "com.apple.Safari":
            script = """
                tell application "Safari"
                    try
                        tell front document
                            set jsResult to do JavaScript "
                                try {
                                    function findAndSelectText(text) {
                                        var walker = document.createTreeWalker(
                                            document.body,
                                            NodeFilter.SHOW_TEXT,
                                            null,
                                            false
                                        );
                                        
                                        var node;
                                        while (node = walker.nextNode()) {
                                            if (node.textContent.includes(text)) {
                                                var range = document.createRange();
                                                var startIndex = node.textContent.indexOf(text);
                                                range.setStart(node, startIndex);
                                                range.setEnd(node, startIndex + text.length);
                                                
                                                var selection = window.getSelection();
                                                selection.removeAllRanges();
                                                selection.addRange(range);
                                                return true;
                                            }
                                        }
                                        return false;
                                    }
                                    
                                    return findAndSelectText('\(escapedText)') ? 'success' : 'not_found';
                                } catch (e) {
                                    return 'error: ' + e.message;
                                }
                            "
                            return jsResult
                        end tell
                    on error errMsg
                        return "applescript_error: " & errMsg
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
                Logger.error("AppleScript error reselecting text: \(error)")
                return false
            }
            
            let resultString = result.stringValue ?? ""
            Logger.info("Reselect text result: \(resultString)")
            return resultString == "success"
        }
        
        return false
    }
    
    private func reselectStandardText(in element: AXUIElement, with originalText: String) -> Bool {
        // 对于标准应用，尝试通过文本查找来重新选中
        guard let fullText = getValue(of: element) else { return false }
        
        // 查找原始文本在完整文本中的位置
        if let range = fullText.range(of: originalText) {
            let startIndex = fullText.distance(from: fullText.startIndex, to: range.lowerBound)
            let length = originalText.count
            
            // 尝试设置选中范围
            var cfRange = CFRangeMake(startIndex, length)
            if let axValue = AXValueCreate(AXValueType.cfRange, &cfRange) {
                let result = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axValue)
            
                            if result == .success {
                    Logger.info("Successfully reselected text at range: \(startIndex)-\(startIndex + length)")
                    return true
                } else {
                    Logger.warn("Failed to reselect text via AX API: \(result.rawValue)")
                }
            } else {
                Logger.warn("Failed to create AXValue for range")
            }
        }
        
        return false
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
        stopSelectionMonitoring()
    }
    
    func stopSelectionMonitoring() {
        if let monitor = mouseEventMonitor {
            NSEvent.removeMonitor(monitor)
            mouseEventMonitor = nil
            Logger.info("Mouse event monitor removed")
        } 
    }
    
    // 暂停选中文本监听
    func pauseSelectionMonitoring() {
        isSelectionMonitoringPaused = true
        Logger.info("Selection monitoring paused")
    }
    
    // 恢复选中文本监听
    func resumeSelectionMonitoring() {
        isSelectionMonitoringPaused = false
        Logger.info("Selection monitoring resumed")
    }
    
    // 检查Chrome的AppleScript JavaScript权限
    private func checkChromeJavaScriptPermission() -> Bool {
        // 先检查自动化权限
        let bundleId = "com.google.Chrome"
        let appUrl = URL(fileURLWithPath: "/Applications/Google Chrome.app")
        
        // 检查应用是否安装
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil else {
            Logger.error("Chrome application not found")
            return false
        }
        
        // 检查自动化权限
        let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false]
        let isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !isTrusted {
            Logger.warn("App does not have automation permission for Chrome")
            return false
        }
        
        // 尝试执行简单的Chrome AppleScript命令来验证
        let scriptSource = """
        tell application "Google Chrome"
            try
                get name of first window
                return true
            on error
                return false
            end try
        end tell
        """
        
        if let script = NSAppleScript(source: scriptSource) {
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            if error == nil {
                return result.booleanValue
            } else {
                Logger.error("Error executing Chrome AppleScript: \(error!)")
            }
        }
        
        return false
    }
    
    // 处理选中文本并显示菜单（用于异步调用）
    private func processSelectedTextForMenu(_ selection: (text: String, element: AXUIElement), selectionType: String) {
        // 如果选中文本监听被暂停，不执行任何操作
        if isSelectionMonitoringPaused {
            return
        }
        
        // 检查是否是刚刚完成的自动翻译结果，避免对翻译结果再次触发菜单
        if isLikelyTranslationResult(selection.text) {
            Logger.info("Skipping menu for likely translation result: '\(selection.text)'")
            return
        }
        
        // 过滤掉太短或太长的选中文本，但保留原始文本格式
        let originalText = selection.text
        let trimmedForCheck = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 检查文本长度限制
        if trimmedForCheck.count < 3 {
            if !lastSelectedText.isEmpty {
                TranslationMenuWindow.shared.hide()
                lastSelectedText = ""
                isMenuShowing = false
            }
            return
        }
        
        // 防止选中文本过大导致性能问题
        let maxSelectionLength = 5000  // 限制选中文本最大长度
        if originalText.count > maxSelectionLength {
            Logger.warn("Selected text too large (\(originalText.count) chars), skipping menu display")
            if !lastSelectedText.isEmpty {
                TranslationMenuWindow.shared.hide()
                lastSelectedText = ""
                isMenuShowing = false
            }
            return
        }
        
        // 使用原始文本（保留前后空白）进行比较和传递
        if originalText != lastSelectedText {
            lastSelectedText = originalText
            isMenuShowing = true
            
            Logger.info("Selected text after \(selectionType) selection: '\(originalText)' (length: \(originalText.count))") 
            
            // 标记选中文本翻译开始，通知 InputMonitor
            InputMonitor.shared.markSelectionTranslationStart()
            
            // 获取选中文本的位置和应用信息
            let mouseLocation = NSEvent.mouseLocation
            let appInfo = getAppInfo(for: selection.element)
            
            // 显示翻译菜单，传递所需信息
            TranslationMenuWindow.shared.show(
                for: originalText,
                from: selection.element,
                at: mouseLocation,
                browserInfo: appInfo.isBrowser ? appInfo : nil
            )
            
            // 设置关闭回调
            TranslationMenuWindow.shared.onMenuClosed = { [weak self] in
                self?.isMenuShowing = false
                self?.lastSelectedText = ""
                Logger.info("Menu closed callback triggered")
            }
        }
    }

    // MARK: - Special App Support (AdsPower)

    // 检查当前是否为AdsPower应用
    func isAdsPowerApp() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        }
        
        // AdsPower的Bundle ID列表（不区分大小写）
        let adsPowerBundleIds = [
            "com.adspower.global",
            "com.adspower.sunbrowser"
        ]
        
        for id in adsPowerBundleIds {
            if bundleId.caseInsensitiveCompare(id) == .orderedSame {
                Logger.info("Detected AdsPower app: \(frontmostApp.localizedName ?? "Unknown") (\(bundleId))")
                return true
            }
        }
        
        return false
    }

    private func findTrigger(in content: String) -> (text: String, lang: String)? {
        Logger.info("AdsPower: Finding trigger in content from clipboard.")
        return processContentForTrigger(content)
    }

    // 通过剪贴板检测触发器（专为AdsPower设计）
    func detectTriggerViaClipboard() -> (text: String, lang: String)? {
        Logger.info("AdsPower: Starting system-wide clipboard-based trigger detection.")

        let pasteboard = NSPasteboard.general
        let originalContent = saveOriginalPasteboardContent()
        
        // Clear clipboard to ensure we detect the new content
        pasteboard.clearContents()
        
        // Send Cmd+A (Select All) globally
        postSelectAll()
        
        // Add a delay for the selection to register
        Thread.sleep(forTimeInterval: 0.2)
        
        var copiedText: String?
        
        // Try to copy twice to be robust
        for i in 1...2 {
            Logger.info("AdsPower: Attempting global copy, trial #\(i)")
            
            // Send Cmd+C (Copy) globally
            postCopy()
            
            // Add a longer delay for the copy action to complete
            Thread.sleep(forTimeInterval: 0.3)

            // Check clipboard
            copiedText = pasteboard.string(forType: .string)
            
            if let text = copiedText, !text.isEmpty {
                Logger.info("AdsPower: Found content in clipboard: '\(text)'")
                break
            } else {
                Logger.warn("AdsPower: Clipboard is empty after attempt #\(i).")
                if i < 2 {
                    Thread.sleep(forTimeInterval: 0.5) // Extra delay before retry
                }
            }
        }
        
        // Restore original clipboard content immediately
        restorePasteboardContent(originalContent)
        
        guard let text = copiedText, !text.isEmpty else {
            Logger.error("AdsPower: No content found in clipboard after all copy attempts.")
            return nil
        }
        
        // Check if the copied text contains our trigger
        return findTrigger(in: text)
    }

    private func postSelectAll() {
        let source = CGEventSource(stateID: .hidSystemState)
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: true)
        let aDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_A), keyDown: true)
        let aUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_A), keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: false)
        
        cmdDown?.flags = .maskCommand
        aDown?.flags = .maskCommand
        
        cmdDown?.post(tap: .cghidEventTap)
        aDown?.post(tap: .cghidEventTap)
        aUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
        
        Logger.info("AdsPower: Posted global Cmd+A")
    }
    
    private func postCopy() {
        let source = CGEventSource(stateID: .hidSystemState)
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: true)
        let cDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        let cUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: false)
        
        cmdDown?.flags = .maskCommand
        cDown?.flags = .maskCommand
        
        cmdDown?.post(tap: .cghidEventTap)
        cDown?.post(tap: .cghidEventTap)
        cUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
        
        Logger.info("AdsPower: Posted global Cmd+C")
    }

    func saveOriginalPasteboardContent() -> Any? {
        let pasteboard = NSPasteboard.general
        guard let pasteboardItem = pasteboard.pasteboardItems?.first else { return nil }

        // Store the original content (only handle string for now)
        if let text = pasteboardItem.string(forType: .string) {
            return text
        }
        
        // TODO: Handle other types like images if necessary
        return nil
    }

    func restorePasteboardContent(_ originalContent: Any?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        if let text = originalContent as? String {
            _ = pasteboard.setString(text, forType: .string)
        }
        // TODO: Handle other types
    }
    
    // 检查是否为终端应用
    func isTerminalApp_DUPLICATE() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        }
        
        let terminalBundleIds = [
            "com.googlecode.iterm2",    // iTerm2
            "com.apple.Terminal",       // Terminal.app
            "co.zeit.hyper",            // Hyper
            "io.alacritty",             // Alacritty
            "net.kovidgoyal.kitty"      // Kitty
        ]
        
        let result = terminalBundleIds.contains(bundleId)
        if result {
            Logger.info("Detected terminal app: \(frontmostApp.localizedName ?? "Unknown") (\(bundleId))")
        }
        return result
    }
    
    // 新增：获取当前输入框的值
    func getCurrentInputValue() -> String? {
        guard let focused = getFocusedElement() else {
            Logger.warn("No focused element found for getCurrentInputValue")
            return nil
        }
        let isWeb = isWebEnvironment()
        return getValueWithWebSupport(of: focused, isWeb: isWeb)
    }
    
    // 新增：发送右箭头键以取消全选
    func postRightArrowKey() {
        let source = CGEventSource(stateID: .hidSystemState)
        let rightArrowKeyCode = 124 as CGKeyCode // kVK_RightArrow
        
        let downEvent = CGEvent(keyboardEventSource: source, virtualKey: rightArrowKeyCode, keyDown: true)
        downEvent?.post(tap: .cghidEventTap)
        
        let upEvent = CGEvent(keyboardEventSource: source, virtualKey: rightArrowKeyCode, keyDown: false)
        upEvent?.post(tap: .cghidEventTap)
        
        Logger.info("AdsPower Recovery: Posted Right Arrow key to deselect text after misfire.")
    }
    
    // 新增：专为AdsPower设计的回填方法
    private func replaceAdsPowerInput(with text: String, completion: (() -> Void)?) {
        // AdsPower的回填非常直接：因为触发时已经全选了，现在只需要粘贴即可。
        
        // 1. 保存当前剪贴板
        let originalContent = saveOriginalPasteboardContent()

        // 2. 将翻译结果放入剪贴板
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            Logger.error("AdsPower Replace: Failed to set clipboard with translation result.")
            restorePasteboardContent(originalContent)
            completion?()
            return
        }

        // 3. 模拟粘贴
        simulatePaste()
        
        // 4. 延迟恢复剪贴板并调用完成回调
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.restorePasteboardContent(originalContent)
            Logger.info("AdsPower Replace: Clipboard restored.")
            completion?()
        }
    }
} 
