import Foundation
import AppKit

// MARK: - AppleScript Manager

/// Compiled AppleScript template for performance optimization
struct CompiledAppleScript {
    let script: NSAppleScript
    let templateKey: String
    let browserType: String
    let createdAt: Date
    
    var isExpired: Bool {
        Date().timeIntervalSince(createdAt) > AppleScriptTemplateCache.cacheExpirationTime
    }
}

/// High-performance AppleScript template cache
class AppleScriptTemplateCache {
    static let shared = AppleScriptTemplateCache()
    static let cacheExpirationTime: TimeInterval = 300 // 5 minutes
    
    private var compiledScripts: [String: CompiledAppleScript] = [:]
    private let cacheQueue = DispatchQueue(label: "appleScriptCache", attributes: .concurrent)
    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0
    private var compilationTime: TimeInterval = 0
    
    private init() {}
    
    /// Get or create a compiled AppleScript from template
    func getCompiledScript(templateKey: String, browserType: String, generator: () -> String) -> NSAppleScript? {
        let timer = PerformanceTelemetry.shared.startTiming("applescript.cache_lookup")
        timer.addContext("template_key", templateKey)
        timer.addContext("browser_type", browserType)
        
        // Check cache first
        let result = cacheQueue.sync { () -> NSAppleScript? in
            let fullKey = "\(browserType)_\(templateKey)"
            
            if let cached = compiledScripts[fullKey], !cached.isExpired {
                cacheHits += 1
                recordPerformanceCounter("applescript.cache.hit")
                timer.addContext("cache_hit", true)
                return cached.script
            }
            
            // Cache miss - compile new script
            cacheMisses += 1
            recordPerformanceCounter("applescript.cache.miss")
            timer.addContext("cache_hit", false)
            
            let compileTimer = PerformanceTelemetry.shared.startTiming("applescript.compilation")
            let scriptSource = generator()
            
            guard let script = NSAppleScript(source: scriptSource) else {
                compileTimer.finish(success: false)
                return nil
            }
            
            let compilationDuration = compileTimer.finish(success: true).duration
            compilationTime = (compilationTime * 0.9) + (compilationDuration * 0.1)
            
            // Cache the compiled script
            let compiledScript = CompiledAppleScript(
                script: script,
                templateKey: templateKey,
                browserType: browserType,
                createdAt: Date()
            )
            
            compiledScripts[fullKey] = compiledScript
            
            // Periodically clean expired entries
            if compiledScripts.count > 20 {
                cleanExpiredScripts()
            }
            
            return script
        }
        
        timer.finish(success: result != nil)
        return result
    }
    
    /// Clear all cached scripts
    func clearCache() {
        cacheQueue.async(flags: .barrier) {
            self.compiledScripts.removeAll()
            Logger.info("AppleScript cache cleared")
        }
    }
    
    /// Get cache performance metrics
    func getPerformanceMetrics() -> (hits: Int, misses: Int, hitRatio: Double, avgCompilationTime: TimeInterval) {
        return cacheQueue.sync {
            let total = cacheHits + cacheMisses
            let hitRatio = total > 0 ? Double(cacheHits) / Double(total) : 0.0
            return (cacheHits, cacheMisses, hitRatio, compilationTime)
        }
    }
    
    private func cleanExpiredScripts() {
        let expired = compiledScripts.filter { $0.value.isExpired }
        for (key, _) in expired {
            compiledScripts.removeValue(forKey: key)
        }
        Logger.debug("Cleaned \(expired.count) expired AppleScript cache entries")
    }
}

/// AppleScript Manager - 统一管理所有AppleScript相关操作
class AppleScriptManager {
    static let shared = AppleScriptManager()
    
    private init() {}
    
    // MARK: - String Escaping
    
    /// 安全地转义 AppleScript 中的字符串内容
    func escapeForAppleScript(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")    // 反斜杠
            .replacingOccurrences(of: "\"", with: "\\\"")    // 双引号
            .replacingOccurrences(of: "\n", with: "\\n")     // 换行符
            .replacingOccurrences(of: "\r", with: "\\r")     // 回车符
            .replacingOccurrences(of: "\t", with: "\\t")     // 制表符
    }
    
    // MARK: - Script Generation
    
    /// 生成Chrome浏览器的AppleScript
    func generateChromeScript(escapedText: String, jsPatternCode: String) -> String {
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
    
    /// 生成Safari浏览器的AppleScript
    func generateSafariScript(escapedText: String, jsPatternCode: String) -> String {
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
    
    // MARK: - Web Content Retrieval
    
    /// 使用AppleScript获取Web内容
    func getWebContentViaAppleScript() -> String? { 
        
        guard let browserInfo = AppDetectionManager.shared.getCurrentBrowserInfo() else { return nil }
        
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
        
        // Use cached AppleScript compilation for better performance
        let templateKey = "get_web_content"
        if let appleScript = AppleScriptTemplateCache.shared.getCompiledScript(
            templateKey: templateKey,
            browserType: browserInfo.bundleId,
            generator: { script }
        ) {
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
    
    // MARK: - Web Content Replacement
    
    /// 使用AppleScript + JavaScript进行Web内容替换
    func replaceViaAppleScriptJS(text: String) -> Bool { 
        
        guard let browserInfo = AppDetectionManager.shared.getCurrentBrowserInfo() else { 
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
         
        // 获取JavaScript模式代码（使用缓存的懒加载版本）
        let jsPatternCode = JavaScriptPatternCache.shared.getJavaScriptPatternCode(for: browserInfo.bundleId)
         
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
        
        // Use cached AppleScript compilation for better performance
        let templateKey = "replace_text_\(escapedText)_\(jsPatternCode.hashValue)"
        if let appleScript = AppleScriptTemplateCache.shared.getCompiledScript(
            templateKey: templateKey,
            browserType: browserInfo.bundleId,
            generator: { script }
        ) {
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
    
    // MARK: - Text Selection
    
    /// 使用JavaScript精确选择触发器文本
    func selectTriggerTextViaJS(originalValue: String) -> Bool {
        guard let browserInfo = AppDetectionManager.shared.getCurrentBrowserInfo() else { 
            Logger.warn("No browser info for JS selection")
            return false 
        }
        
        // 获取JavaScript模式代码（使用缓存的懒加载版本）
        let jsPatternCode = JavaScriptPatternCache.shared.getJavaScriptPatternCode(for: browserInfo.bundleId) 
        
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
        
        // Use cached AppleScript compilation for better performance
        let templateKey = "select_trigger_text_\(originalValue.hashValue)"
        if let appleScript = AppleScriptTemplateCache.shared.getCompiledScript(
            templateKey: templateKey,
            browserType: browserInfo.bundleId,
            generator: { script }
        ) {
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
    
    // MARK: - Web Element Utilities
    
    /// 检查Web元素是否可编辑
    func isWebElementEditable() -> Bool {
        guard let browserInfo = AppDetectionManager.shared.getCurrentBrowserInfo() else { return false }
        
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
        
        // Use cached AppleScript compilation for better performance
        let templateKey = "check_editable"
        if let appleScript = AppleScriptTemplateCache.shared.getCompiledScript(
            templateKey: templateKey,
            browserType: browserInfo.bundleId,
            generator: { script }
        ) {
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
    
    /// 通过JavaScript获取Web环境中的选中文本
    func getWebSelectedText() -> String? {
        guard let browserInfo = AppDetectionManager.shared.getCurrentBrowserInfo() else { return nil }
        
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
        
        // Use cached AppleScript compilation for better performance
        let templateKey = "get_web_selection"
        if let appleScript = AppleScriptTemplateCache.shared.getCompiledScript(
            templateKey: templateKey,
            browserType: browserInfo.bundleId,
            generator: { script }
        ) {
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
    
    /// 重新选择Web文本
    func reselectWebText(with originalText: String) -> Bool {
        guard let browserInfo = AppDetectionManager.shared.getCurrentBrowserInfo() else { return false }
        
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
        
        // Use cached AppleScript compilation for better performance
        let templateKey = "reselect_web_text_\(escapedText.hashValue)"
        if let appleScript = AppleScriptTemplateCache.shared.getCompiledScript(
            templateKey: templateKey,
            browserType: browserInfo.bundleId,
            generator: { script }
        ) {
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
    
    // MARK: - Testing Methods
    
    /// 测试基本的AppleScript执行
    static func testBasicAppleScript() {
        Logger.info("=== Testing Basic AppleScript ===")
        
        let script = """
        tell application "System Events"
            return "Hello from AppleScript"
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)
            
            if let error = error {
                Logger.error("Basic AppleScript failed: \(error)")
            } else {
                Logger.info("Basic AppleScript success: \(result.stringValue ?? "nil")")
            }
        } else {
            Logger.error("Failed to create basic AppleScript")
        }
    }
    
    /// 测试Chrome AppleScript
    static func testChromeAppleScript() {
        Logger.info("=== Testing Chrome AppleScript ===")
        
        let script = """
        tell application "Google Chrome"
            try
                tell active tab of front window
                    set jsResult to execute javascript "
                        var activeElement = document.activeElement;
                        if (activeElement) {
                            if (activeElement.tagName === 'INPUT' || activeElement.tagName === 'TEXTAREA') {
                                return 'INPUT/TEXTAREA: ' + (activeElement.value || '');
                            } else if (activeElement.contentEditable === 'true') {
                                return 'CONTENTEDITABLE: ' + (activeElement.textContent || activeElement.innerText || '');
                            } else {
                                return 'OTHER: ' + activeElement.tagName;
                            }
                        }
                        return 'NO_ACTIVE_ELEMENT';
                    "
                    return jsResult
                end tell
            on error errMsg
                return "ERROR: " & errMsg
            end try
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)
            
            if let error = error {
                Logger.error("Chrome AppleScript failed: \(error)")
            } else {
                Logger.info("Chrome AppleScript result: \(result.stringValue ?? "nil")")
            }
        } else {
            Logger.error("Failed to create Chrome AppleScript")
        }
    }
    
    /// 测试Safari AppleScript
    static func testSafariAppleScript() {
        Logger.info("=== Testing Safari AppleScript ===")
        
        let script = """
        tell application "Safari"
            try
                tell front document
                    set jsResult to do JavaScript "
                        var activeElement = document.activeElement;
                        if (activeElement) {
                            if (activeElement.tagName === 'INPUT' || activeElement.tagName === 'TEXTAREA') {
                                return 'INPUT/TEXTAREA: ' + (activeElement.value || '');
                            } else if (activeElement.contentEditable === 'true') {
                                return 'CONTENTEDITABLE: ' + (activeElement.textContent || activeElement.innerText || '');
                            } else {
                                return 'OTHER: ' + activeElement.tagName;
                            }
                        }
                        return 'NO_ACTIVE_ELEMENT';
                    "
                    return jsResult
                end tell
            on error errMsg
                return "ERROR: " & errMsg
            end try
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)
            
            if let error = error {
                Logger.error("Safari AppleScript failed: \(error)")
            } else {
                Logger.info("Safari AppleScript result: \(result.stringValue ?? "nil")")
            }
        } else {
            Logger.error("Failed to create Safari AppleScript")
        }
    }
    
    /// 测试当前活跃应用的AppleScript权限
    static func testCurrentAppAppleScript() {
        Logger.info("=== Testing Current App AppleScript ===")
        
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            Logger.error("Cannot get frontmost application")
            return
        }
        
        Logger.info("Frontmost app: \(frontmostApp.localizedName) (\(frontmostApp.bundleIdentifier ?? "unknown"))")
        
        let script = """
        tell application "\(frontmostApp.localizedName)"
            try
                return "SUCCESS: Can access \(frontmostApp.localizedName)"
            on error errMsg
                return "ERROR: " & errMsg
            end try
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)
            
            if let error = error {
                Logger.error("Current app AppleScript failed: \(error)")
            } else {
                Logger.info("Current app AppleScript result: \(result.stringValue ?? "nil")")
            }
        } else {
            Logger.error("Failed to create current app AppleScript")
        }
    }
    
    /// 测试系统事件AppleScript权限
    static func testSystemEventsAppleScript() {
        Logger.info("=== Testing System Events AppleScript ===")
        
        let script = """
        tell application "System Events"
            try
                set frontApp to name of first application process whose frontmost is true
                return "SUCCESS: Frontmost app is " & frontApp
            on error errMsg
                return "ERROR: " & errMsg
            end try
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)
            
            if let error = error {
                Logger.error("System Events AppleScript failed: \(error)")
            } else {
                Logger.info("System Events AppleScript result: \(result.stringValue ?? "nil")")
            }
        } else {
            Logger.error("Failed to create System Events AppleScript")
        }
    }
    
    /// 运行所有AppleScript测试
    static func runAllAppleScriptTests() {
        Logger.info("Starting AppleScript tests...")
        
        testBasicAppleScript()
        Thread.sleep(forTimeInterval: 0.5)
        
        testSystemEventsAppleScript()
        Thread.sleep(forTimeInterval: 0.5)
        
        testCurrentAppAppleScript()
        Thread.sleep(forTimeInterval: 0.5)
        
        testChromeAppleScript()
        Thread.sleep(forTimeInterval: 0.5)
        
        testSafariAppleScript()
        
        Logger.info("AppleScript tests completed")
    }
    
    /// 测试特定应用的AppleScript
    static func testSpecificApp(_ appName: String) {
        Logger.info("=== Testing \(appName) AppleScript ===")
        
        let script = """
        tell application "\(appName)"
            try
                return "SUCCESS: Can access \(appName)"
            on error errMsg
                return "ERROR: " & errMsg
            end try
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)
            
            if let error = error {
                Logger.error("\(appName) AppleScript failed: \(error)")
            } else {
                Logger.info("\(appName) AppleScript result: \(result.stringValue ?? "nil")")
            }
        } else {
            Logger.error("Failed to create \(appName) AppleScript")
        }
    }
} 