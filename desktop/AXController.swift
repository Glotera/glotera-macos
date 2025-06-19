import Cocoa
import ApplicationServices
import CoreFoundation

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
            print("[LOG] Failed to get PID for element")
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
            
            // 尝试备用方法获取内容
            print("[LOG] Trying alternative content retrieval methods...")
            if let alternativeValue = getAlternativeValue(of: focused) {
                print("[LOG] Got content via alternative method: '\(alternativeValue)'")
                return processContentForTrigger(alternativeValue)
            }
            
            return nil
        }
        
        return processContentForTrigger(value)
    }
    
    // 处理内容以检测触发器
    private func processContentForTrigger(_ value: String) -> (text: String, lang: String)? {
        //print("[LOG] Current input content: '\(value)'")
        //print("[LOG] Content length: \(value.count) characters")
        
        // 显示换行符位置以便调试
        let lineBreaks = value.enumerated().compactMap { $0.element == "\n" ? $0.offset : nil }
        if !lineBreaks.isEmpty {
            print("[LOG] Newlines found at positions: \(lineBreaks)")
        }
        
        // 预处理内容：清理可能的干扰文本
        let cleanedValue = preprocessContent(value)
        if cleanedValue != value {
            // print("[LOG] Content after preprocessing: '\(cleanedValue)'")
            // print("[LOG] Cleaned content length: \(cleanedValue.count) characters")
        }
        
        // 使用配置管理器获取所有触发器
        let allTriggers = getAllConfiguredTriggers()
        if allTriggers.isEmpty {
            print("[LOG] No configured triggers found, falling back to default patterns")
            return processContentWithDefaultTriggers(cleanedValue)
        }
        
        // 动态生成正则表达式模式
        // let patterns = generateTriggerPatterns(triggers: allTriggers)
        
        // 检查每个触发器
        for trigger in allTriggers {
            if let result = checkForTrigger(trigger, in: cleanedValue) {
                print("[LOG] Trigger found: '\(trigger)' -> text='\(result.text)', lang='\(result.lang)'")
                return result
            }
        }
        
        print("[LOG] No trigger pattern matched")
        
        // 添加详细的调试信息
        print("[LOG] Debug - checking for configured triggers in content:")
        for trigger in allTriggers {
            if cleanedValue.lowercased().contains(trigger.lowercased()) {
                print("[LOG] Debug - Found '\(trigger)' in content but pattern didn't match")
                print("[LOG] Debug - Content around trigger: '\(getContextAroundTrigger(cleanedValue, trigger: trigger))'")
            }
        }
        
        return nil
    }
    
    // 获取所有配置的触发器
    private func getAllConfiguredTriggers() -> [String] {
        let configs = LanguageConfigManager.shared.loadLanguageConfigs()
        var allTriggers: [String] = []
        
        for config in configs {
            allTriggers.append(contentsOf: config.triggers)
        }
        
        print("[LOG] Loaded \(allTriggers.count) configured triggers from \(configs.count) languages")
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
        
        print("[LOG] Generated \(patterns.count) JavaScript patterns for \(triggers.count) triggers")
        
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
        
        print("[LOG] Generated JavaScript patterns for \(allLanguageCodes.count) languages")
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
            print("[LOG] Extracted \(languageCodes.count) language codes from configured triggers")
            return Array(languageCodes).sorted()
        }
        
        print("[LOG] No configured triggers found, using fallback language list")
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
        
        print("[LOG] Safe JS pattern code length: \(safeJsPatternCode.count)")
        print("[LOG] Safe escaped text: '\(safeEscapedText)'")
        
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
        print("[LOG] Using fallback default trigger processing")
        
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
                            print("[LOG] Default trigger found using pattern \(index + 1): text='\(text)', lang='\(lang)'")
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
        print("[LOG] Trying alternative value retrieval methods")
        
        // 方法1: 尝试获取选中文本
        if let selectedText = getSelectedTextAttribute(of: element), !selectedText.isEmpty {
            print("[LOG] Got content via selected text: \(selectedText)")
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
                print("[LOG] Got content via \(attribute): \(stringValue)")
                return stringValue
            }
        }
        
        // 方法3: 如果在Web环境，强制重试AppleScript
        if isWebEnvironment() {
            print("[LOG] Forcing AppleScript retry for web content")
            // 等待一小段时间后重试
            Thread.sleep(forTimeInterval: 0.1)
            if let webContent = getWebContentViaAppleScript() {
                print("[LOG] Got content via forced AppleScript retry: \(webContent)")
                return webContent
            }
        }
        
        print("[LOG] All alternative methods failed")
        return nil
    }
    
    // 预处理内容：清理可能的干扰文本
    private func preprocessContent(_ content: String) -> String {
        var cleaned = content
        
        // 检查当前应用是否为Discord或其他聊天应用
        let isDiscordOrChat = isDiscordOrChatApp()
        
        // 对于Discord等聊天应用，使用更保守的清理策略
        if isDiscordOrChat {
            print("[LOG] Detected Discord/Chat app - using conservative preprocessing")
            // 只进行基本的空格合并，不移除任何文本内容
            cleaned = cleaned.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned
        }
        
        // 对于其他应用（如Notion），使用更激进的清理策略
        // 移除常见的Notion界面元素文本
        let notionInterferencePatterns = [
            "Add cover",
            "Add icon",
            "Add comment",
            "Untitled",
            "Type '/' for commands",
            "Press Enter to continue writing or type '/' for commands",
            "Empty page",
            "Start writing...",
            "Click to edit",
            "Add a page inside",
            "New page",
            "Template",
            "Import",
            "Database",
            "Gallery",
            "Board",
            "Timeline",
            "Calendar",
            "List"
        ]
        
        // 移除这些干扰文本（不区分大小写）
        for pattern in notionInterferencePatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .caseInsensitive)
        }
        
        // 移除表格相关的干扰内容
        // 匹配类似 "Column 1Column 2Column 3" 这样的表格标题
        cleaned = cleaned.replacingOccurrences(of: #"Column\s*\d+"#, with: "", options: .regularExpression)
        
        // 只合并连续的空格和制表符，保留换行符
        cleaned = cleaned.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        
        // 移除行首行尾的空白，但保留换行符
        let lines = cleaned.components(separatedBy: .newlines)
        let trimmedLines = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        cleaned = trimmedLines.joined(separator: "\n")
        
        // 最终去掉首尾空白
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 如果清理后的内容太短或为空，返回原内容
        if cleaned.isEmpty || cleaned.count < 3 {
            return content
        }
        
        return cleaned
    }
    
    // 检查当前应用是否为Discord或其他聊天应用
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
        
        let result = chatAppBundleIds.contains(bundleId)
        if result {
            print("[LOG] Detected chat app: \(frontmostApp.localizedName ?? "Unknown") (\(bundleId))")
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
            // print("[LOG] No focused app found")
            return nil
        }
        var focusedElem: CFTypeRef?
        AXUIElementCopyAttributeValue(app as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElem)
        if let elem = focusedElem {
            // print("[LOG] Focused element found")
            return (elem as! AXUIElement)
        }
        // print("[LOG] No focused element found")
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
    func replaceInput(with text: String, completion: (() -> Void)? = nil) {
        print("[LOG] Replacing input with translation result")
        guard let focused = getFocusedElement() else {
            print("[LOG] No focused element to replace")
            completion?()
            return
        }
        
        // 暂停选中文本监听，防止自动翻译回填时触发翻译菜单
        pauseSelectionMonitoring()
        // print("[LOG] Paused selection monitoring for auto-translation")
        
        // 检查是否在浏览器环境中
        let isWeb = isWebEnvironment()
        if let browserInfo = getCurrentBrowserInfo() {
            print("[LOG] Replacing content in browser: \(browserInfo.appName)")
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
                print("[LOG] Using WeChat-specific replacement method")
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
            print("[LOG] Resumed selection monitoring after auto-translation")
        }
    }
    
    // Web输入框内容替换的专用方法
    private func replaceWebInputContent(element: AXUIElement, text: String, completion: @escaping () -> Void) {
        print("[LOG] Using Web input replacement method")
        
        // 方法1: 尝试AppleScript + JavaScript进行精确替换
        // print("[LOG] Attempting AppleScript + JavaScript replacement first")
       if replaceViaAppleScriptJS(text: text) {
           print("[LOG] Successfully replaced via AppleScript + JavaScript")
           completion()
           return
       }
        
        print("[LOG] AppleScript + JavaScript failed, falling back to clipboard method")
        // 方法2: 回退到剪贴板方法，但增加额外的验证和重试
        replaceWebViaClipboardWithRetry(element: element, text: text, completion: completion)
    }
    
    // 使用AppleScript + JavaScript进行Web内容替换
    private func replaceViaAppleScriptJS(text: String) -> Bool {
        print("[LOG] Attempting AppleScript + JavaScript replacement")
        
        guard let browserInfo = getCurrentBrowserInfo() else { 
            print("[LOG] No browser info available")
            return false 
        }
        
        print("[LOG] Browser detected: \(browserInfo.appName) (\(browserInfo.bundleId))")
        
        // 转义JavaScript字符串中的特殊字符
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        
        print("[LOG] Escaped text for JavaScript: '\(escapedText)'")
        
        // 获取所有配置的触发器并生成JavaScript模式
        let allTriggers = getAllConfiguredTriggers()
        let jsPatternCode = generateJavaScriptPatternCode(for: allTriggers)
        // print("[LOG] Generated JavaScript pattern code for \(allTriggers.count) triggers")
        // print("[LOG] All triggers: \(allTriggers)")
        // print("[LOG] JS Pattern Code: \(jsPatternCode)")
        
        var script = ""
        
        switch browserInfo.bundleId {
        case "com.google.Chrome":
            script = generateChromeScript(escapedText: escapedText, jsPatternCode: jsPatternCode)
        case "com.apple.Safari":
            script = generateSafariScript(escapedText: escapedText, jsPatternCode: jsPatternCode)
        default:
            print("[LOG] Unsupported browser: \(browserInfo.bundleId)")
            return false
        }
        
        print("[LOG] Executing AppleScript...")
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)
            
            if let error = error {
                print("[LOG] AppleScript replacement error: \(error)")
                return false
            }
            
            let resultString = result.stringValue ?? ""
            print("[LOG] AppleScript replacement result: '\(resultString)'")
            
            if resultString == "success" {
                print("[LOG] AppleScript replacement successful")
                return true
            } else {
                print("[LOG] AppleScript replacement failed with result: \(resultString)")
                return false
            }
        } else {
            print("[LOG] Failed to create AppleScript object")
            return false
        }
    }
    
    // Web环境下的剪贴板替换，带重试机制
    private func replaceWebViaClipboardWithRetry(element: AXUIElement, text: String, completion: @escaping () -> Void) {
        print("[LOG] Using Web clipboard replacement with retry")
        
        // 首先尝试获取当前内容，确定需要替换的部分
        guard let currentValue = getValue(of: element) else {
            print("[LOG] Cannot get current value for precise replacement")
            completion()
            return
        }
        
        // print("[LOG] Current input value: '\(currentValue)'")
        
        // 使用动态生成的触发器模式检查
//        let allTriggers = getAllConfiguredTriggers()
//        let patterns = generateSwiftPatterns(for: allTriggers)
//        
//        var triggerFound = false
//        for pattern in patterns {
//            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
//                let nsValue = currentValue as NSString
//                let results = regex.matches(in: currentValue, options: [], range: NSRange(location: 0, length: nsValue.length))
//                
//                if let match = results.first, match.numberOfRanges >= 3 {
//                    triggerFound = true
//                    print("[LOG] Trigger pattern found, proceeding with precise replacement")
//                    break
//                }
//            }
//        }
//        
//        if !triggerFound {
//            print("[LOG] No trigger pattern found, skipping replacement")
//            completion()
//            return
//        }
        
        // 保存原始剪贴板内容
        let pasteboard = NSPasteboard.general
        let originalContent = pasteboard.string(forType: .string)
        print("[LOG] Saved original clipboard: '\(originalContent ?? "nil")'")
        
        // 设置新文本到剪贴板
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("[LOG] Set clipboard to translation text: '\(text)'")
        
        // 验证剪贴板设置成功
        let verifyContent = pasteboard.string(forType: .string)
        if verifyContent != text {
            print("[LOG] ERROR: Failed to set clipboard content correctly")
            completion()
            return
        }
        
        // 使用精确选择和替换策略
        attemptPreciseWebReplace(element: element, originalValue: currentValue, translatedText: text, attempt: 1) { [weak self] success in
            if !success {
                // 如果第一次失败，等待后重试
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    // 重新设置剪贴板内容（可能被其他操作改变）
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                    print("[LOG] Re-set clipboard for retry")
                    
                    self?.attemptPreciseWebReplace(element: element, originalValue: currentValue, translatedText: text, attempt: 2) { _ in
                        // 延长恢复时间，确保Chrome完全处理完粘贴操作
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self?.restoreClipboardSafely(originalContent: originalContent)
                            completion()
                        }
                    }
                }
            } else {
                // 成功时也要延长恢复时间
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self?.restoreClipboardSafely(originalContent: originalContent)
                    completion()
                }
            }
        }
    }
    
    // 精确的Web替换尝试
    private func attemptPreciseWebReplace(element: AXUIElement, originalValue: String, translatedText: String, attempt: Int, completion: @escaping (Bool) -> Void) {
        print("[LOG] Precise Web replace attempt \(attempt)")
        
        // 策略：使用JavaScript选择触发器部分，然后粘贴
        if selectTriggerTextViaJS(originalValue: originalValue) {
            print("[LOG] Successfully selected trigger text via JavaScript")
            
            // 等待选择完成，然后粘贴
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.simulatePaste()
                completion(true)
            }
        } else {
            print("[LOG] JavaScript selection failed, falling back to traditional method")
            
            // 回退到传统的全选+粘贴方法
            simulateSelectAll()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.simulatePaste()
                completion(true)
            }
        }
    }
    
    // 使用JavaScript精确选择触发器文本
    private func selectTriggerTextViaJS(originalValue: String) -> Bool {
        guard let browserInfo = getCurrentBrowserInfo() else { 
            print("[LOG] No browser info for JS selection")
            return false 
        }
        
        // 获取所有配置的触发器并生成JavaScript模式
        let allTriggers = getAllConfiguredTriggers()
        let jsPatternCode = generateJavaScriptPatternCode(for: allTriggers)
        // print("[LOG] Generated JS pattern code for selection: \(jsPatternCode)")
        
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
            print("[LOG] Unsupported browser for JS selection: \(browserInfo.bundleId)")
            return false
        }
        
        print("[LOG] Executing selection AppleScript...")
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)
            
            if let error = error {
                print("[LOG] AppleScript selection error: \(error)")
                return false
            }
            
            let resultString = result.stringValue ?? ""
            print("[LOG] AppleScript selection result: '\(resultString)'")
            
            return resultString == "success"
        } else {
            print("[LOG] Failed to create selection AppleScript object")
            return false
        }
    }
    
    // 安全地恢复剪贴板内容
    private func restoreClipboardSafely(originalContent: String?) {
        let pasteboard = NSPasteboard.general
        
        // 检查当前剪贴板内容
        let currentContent = pasteboard.string(forType: .string)
        print("[LOG] Current clipboard before restore: '\(currentContent ?? "nil")'")
        
        // 恢复原始剪贴板内容
        pasteboard.clearContents()
        if let original = originalContent {
            pasteboard.setString(original, forType: .string)
            print("[LOG] Restored original clipboard content: '\(original)'")
        } else {
            print("[LOG] Cleared clipboard as no original content")
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
                "AXSecureTextField",    // 密码输入框
                "AXSearchField",        // 搜索框
                "AXStaticText"          // 静态文本（某些情况下可编辑）
            ]
            
            NSLog("[LOG] Element role: \(roleString), isWeChat: \(isWeChat)")
            
            // 如果是明确的可编辑控件
            if editableRoles.prefix(5).contains(roleString) {
                return true
            }
            
            // 对于微信，特殊处理
            if isWeChat {
                // 微信中的文本通常都可以被替换，即使是StaticText
                if roleString == "AXStaticText" || roleString == "AXTextArea" || roleString == "AXTextField" {
                    NSLog("[LOG] WeChat element detected as editable")
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
        print("[LOG] Using enhanced WeChat-specific text replacement")
        
        let pasteboard = NSPasteboard.general
        let originalClipboard = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            print("[LOG] WeChat: Failed to set clipboard")
            restoreClipboardContent(originalClipboard)
            completion()
            return
        }

        // 核心流程：激活微信 -> 全选 -> 粘贴
        ensureWeChatAppFocus { focused in
            guard focused else {
                print("[LOG] WeChat: Failed to focus app.")
                self.restoreClipboardContent(originalClipboard)
                completion()
                return
            }
            
            // 等待焦点稳定
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                print("[LOG] WeChat: Sending Cmd+A to select text.")
                self.sendWeChatSelectAllCommand()
                
                // 等待全选完成
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    print("[LOG] WeChat: Sending paste command.")
                    self.sendWeChatPasteCommand()
                    
                    // 延迟恢复剪贴板，确保粘贴完成
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.restoreClipboardContent(originalClipboard)
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
            print("[LOG] WeChat: Not currently focused")
            completion(false)
            return
        }
        
        // 微信已经是前台应用
        print("[LOG] WeChat: App is already focused")
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
        
        print("[LOG] WeChat: Sent Cmd+A select all command")
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
        
        print("[LOG] WeChat: Sent Cmd+V paste command")
    }
    
    // 恢复剪贴板内容
    private func restoreClipboardContent(_ originalClipboard: String?) {
        let pasteboard = NSPasteboard.general
        if let original = originalClipboard {
            pasteboard.clearContents()
            pasteboard.setString(original, forType: .string)
            print("[LOG] WeChat: Restored original clipboard content: '\(original)'")
        } else {
            pasteboard.clearContents()
            print("[LOG] WeChat: Cleared clipboard as there was no original content.")
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
                print("[LOG] AppleScript error checking editability: \(error)")
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
            print("[LOG] Got selected text via AX: '\(selectedText)'")
            return (text: selectedText, element: focused)
        }
        
        // 如果在浏览器环境中，尝试通过JavaScript获取选中文本
        if isWebEnvironment() {
            if let selectedText = getWebSelectedText(), !selectedText.isEmpty {
                print("[LOG] Got selected text via Web: '\(selectedText)'")
                return (text: selectedText, element: focused)
            }
        }
        
        // print("[LOG] No text selected")
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
                print("[LOG] AppleScript error getting selection: \(error)")
                return nil
            }
            
            let selectedText = result.stringValue ?? ""
            return selectedText.isEmpty ? nil : selectedText
        }
        
        return nil
    }
    
    // 开始监听选中文本变化
    func startSelectionMonitoring() {
        print("[LOG] Starting selection monitoring (keyboard-event-safe)")
        
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
        
        // 监听键盘事件，检测 Ctrl+A
        keyboardEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            DispatchQueue.main.async {
                self?.handleKeyboardEvent(event)
            }
        }
        
        print("[LOG] Mouse and keyboard event monitoring started")
    }
    
    private func handleMouseEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            // 检测双击
            let now = Date()
            let timeSinceLastClick = now.timeIntervalSince(lastDoubleClickTime)
            
            if timeSinceLastClick < 0.5 && timeSinceLastClick > 0.1 {
                // 双击检测
                print("[LOG] Double click detected")
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
    
    // 处理键盘事件
    private func handleKeyboardEvent(_ event: NSEvent) {
        // 检测 Ctrl+A (Cmd+A on Mac)
        if event.modifierFlags.contains(.command) && event.keyCode == 0 { // keyCode 0 is 'A'
            print("[LOG] Cmd+A detected")
            lastCtrlATime = Date()
            // 延迟检查 Cmd+A 选择的文本
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.checkForTextSelectionAfterCtrlA()
            }
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
        print("[LOG] Checking text selection after mouse up")
        
        // 等待一个更长的延迟，确保选择完全稳定
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // 只有在鼠标拖拽选择后才显示菜单
            self.checkSelectedTextAndShowMenuAfterMouseSelection()
        }
    }
    
    // 双击后的文本选择检查
    private func checkForTextSelectionAfterDoubleClick() {
        print("[LOG] Checking text selection after double click")
        
        // 等待延迟，确保双击选择完全稳定
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.checkSelectedTextAndShowMenuAfterMouseSelection()
        }
    }
    
    // Cmd+A 后的文本选择检查
    private func checkForTextSelectionAfterCtrlA() {
        print("[LOG] Checking text selection after Cmd+A")
        
        // 等待延迟，确保全选完全稳定
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.checkSelectedTextAndShowMenuAfterKeyboardSelection()
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
            print("[LOG] Detected potential translation result within 5s of auto-translation")
            return true
        }
        
        return false
    }

    // 只隐藏菜单，不显示菜单的逻辑
    private func hideMenuIfNoSelection() {
        guard let selection = getSelectedText() else {
            // 如果没有选中文本，隐藏菜单并重置状态
            if !lastSelectedText.isEmpty {
                TranslationMenuWindow.shared.hide()
                lastSelectedText = ""
                isMenuShowing = false
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
    }
    
    // 鼠标选择后的菜单显示逻辑
    private func checkSelectedTextAndShowMenuAfterMouseSelection() {
        checkSelectedTextAndShowMenu(selectionType: "mouse")
    }
    
    // 键盘选择后的菜单显示逻辑
    private func checkSelectedTextAndShowMenuAfterKeyboardSelection() {
        checkSelectedTextAndShowMenu(selectionType: "keyboard")
    }
    
    // 统一的菜单显示逻辑
    private func checkSelectedTextAndShowMenu(selectionType: String) {
        // 如果选中文本监听被暂停，不执行任何操作
        if isSelectionMonitoringPaused {
            return
        }
        
        guard let selection = getSelectedText() else {
            // 如果没有选中文本，隐藏菜单并重置状态
            if !lastSelectedText.isEmpty {
                TranslationMenuWindow.shared.hide()
                lastSelectedText = ""
                isMenuShowing = false
            }
            return
        }
        
        // 检查是否是刚刚完成的自动翻译结果，避免对翻译结果再次触发菜单
        if isLikelyTranslationResult(selection.text) {
            print("[LOG] Skipping menu for likely translation result: '\(selection.text)'")
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
            
            print("[LOG] Selected text after \(selectionType) selection: '\(originalText)' (length: \(originalText.count))")
            print("[LOG] Trimmed for check: '\(trimmedForCheck)' (length: \(trimmedForCheck.count))")
            
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
                print("[LOG] Menu closed callback triggered")
                }
        }
    }
    
    // 使用剪贴板强力替换内容
    private func forceReplaceWithClipboard(element: AXUIElement, text: String, completion: @escaping () -> Void) {
        print("[LOG] Using clipboard force replace method")
        
        // 保存当前剪贴板内容
        let pasteboard = NSPasteboard.general
        let originalContent = pasteboard.string(forType: .string)
        print("[LOG] Original clipboard content: '\(originalContent ?? "nil")'")
        
        // 将新文本放入剪贴板
        pasteboard.clearContents()
        let setSuccess = pasteboard.setString(text, forType: .string)
        print("[LOG] Set clipboard success: \(setSuccess), content: '\(text)'")
        
        // 验证剪贴板内容是否正确设置
        let verifyContent = pasteboard.string(forType: .string)
        print("[LOG] Verified clipboard content: '\(verifyContent ?? "nil")'")
        
        if verifyContent != text {
            print("[LOG] ERROR: Clipboard content verification failed!")
            completion()
            return
        }
        
        // 选择全部内容 (Cmd+A)
        simulateSelectAll()
        
        // 等待一小段时间确保选择完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // 在粘贴前再次验证剪贴板内容
            let prepasteContent = pasteboard.string(forType: .string)
            print("[LOG] Pre-paste clipboard content: '\(prepasteContent ?? "nil")'")
            
            if prepasteContent != text {
                print("[LOG] ERROR: Clipboard content changed before paste! Re-setting...")
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                
                // 再次验证
                let reVerifyContent = pasteboard.string(forType: .string)
                print("[LOG] Re-verified clipboard content: '\(reVerifyContent ?? "nil")'")
            }
            
            // 粘贴新内容 (Cmd+V)
            self.simulatePaste()
            
            // 恢复原始剪贴板内容并调用完成回调
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                pasteboard.clearContents()
                if let original = originalContent {
                    pasteboard.setString(original, forType: .string)
                }
                print("[LOG] Clipboard content restored to: '\(originalContent ?? "nil")'")
                completion()
            }
        }
    }
    
    // 模拟 Cmd+A 全选
    private func simulateSelectAll() {
        // 添加延迟，确保与InputMonitor的事件处理分离
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            print("[LOG] Simulating Cmd+A select all")
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
                
                print("[LOG] Simulated Cmd+A select all (with timing separation)")
            } else {
                print("[LOG] Failed to create Cmd+A events")
            }
        }
    }
    
    // 模拟 Cmd+V 粘贴
    private func simulatePaste() {
        // 添加延迟，确保与InputMonitor的事件处理分离
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            print("[LOG] Simulating Cmd+V paste")
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
                
                print("[LOG] Simulated Cmd+V paste (with timing separation)")
            } else {
                print("[LOG] Failed to create Cmd+V events")
            }
        }
    }
    
    // 添加一个新的方法来重新选中文本，用于替换时保持选中状态
    func reselectText(in element: AXUIElement, with text: String) -> Bool {
        print("[LOG] Attempting to reselect text for replacement")
        
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
                print("[LOG] AppleScript error reselecting text: \(error)")
                return false
            }
            
            let resultString = result.stringValue ?? ""
            print("[LOG] Reselect text result: \(resultString)")
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
                    print("[LOG] Successfully reselected text at range: \(startIndex)-\(startIndex + length)")
                    return true
                } else {
                    print("[LOG] Failed to reselect text via AX API: \(result.rawValue)")
                }
            } else {
                print("[LOG] Failed to create AXValue for range")
            }
        }
        
        return false
    }
    
    deinit {
        stopSelectionMonitoring()
    }
    
    func stopSelectionMonitoring() {
        if let monitor = mouseEventMonitor {
            NSEvent.removeMonitor(monitor)
            mouseEventMonitor = nil
            print("[LOG] Mouse event monitor removed")
        }
        
        if let monitor = keyboardEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardEventMonitor = nil
            print("[LOG] Keyboard event monitor removed")
        }
    }
    
    // 暂停选中文本监听
    func pauseSelectionMonitoring() {
        isSelectionMonitoringPaused = true
        print("[LOG] Selection monitoring paused")
    }
    
    // 恢复选中文本监听
    func resumeSelectionMonitoring() {
        isSelectionMonitoringPaused = false
        print("[LOG] Selection monitoring resumed")
    }
    
    // 检查Chrome的AppleScript JavaScript权限
    private func checkChromeJavaScriptPermission() -> Bool {
        let scriptSource = """
        tell application "System Events"
            tell process "Google Chrome"
                if exists (menu item "允许来自 Apple 事件的 JavaScript" of menu "开发者" of menu item "开发者" of menu "查看" of menu bar 1) then
                    return true
                else
                    return false
                end if
            end tell
        end tell
        """
        
        if let script = NSAppleScript(source: scriptSource) {
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            if error == nil {
                return result.booleanValue
            } else {
                print("[LOG] Error checking Chrome permissions: \(error!)")
            }
        }
        return false
    }
} 
