import Cocoa

class AXController {
    static let shared = AXController()

    // 检测当前焦点输入框内容，提取触发标记和原文
    func detectTriggerAndExtract() -> (String, String)? {
        guard let focused = getFocusedElement(),
              let value = getValue(of: focused) else {
            print("[LOG] No focused element or value")
            return nil
        }
        
        print("[LOG] Input content: '\(value)'")
        
        // 匹配 @id/#id/@en/#en 等，改进的模式匹配
        // 这个模式匹配以空格结尾的触发器，并提取前面的所有文本
        let pattern = #"(.*?)[@#](id|en|zh|ja|jp|ko|fr|de|es|ru|th)\s*$"#
        let regex = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        
        if let match = regex.firstMatch(in: value, options: [], range: NSRange(location: 0, length: value.utf16.count)) {
            print("[LOG] Regex match found with \(match.numberOfRanges) ranges")
            
            if let textRange = Range(match.range(at: 1), in: value),
               let langRange = Range(match.range(at: 2), in: value) {
                var lang = String(value[langRange]).lowercased()
                if lang == "jp" { lang = "ja" }
                let text = String(value[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                print("[LOG] Extracted: '\(text)' -> '\(lang)'")
                return (text, lang)
            } else {
                print("[LOG] Could not extract ranges from match")
            }
        } else {
            print("[LOG] No trigger pattern matched for content: '\(value)'")
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

    // 替换输入框内容
    func replaceInput(with text: String) {
        print("[LOG] Replacing input with: \(text)")
        guard let focused = getFocusedElement() else {
            print("[LOG] No focused element to replace")
            return
        }
        
        // 设置新的文本内容
        AXUIElementSetAttributeValue(focused, kAXValueAttribute as CFString, text as CFTypeRef)
        
        // 将光标移动到文本末尾
        setCursorToEnd(element: focused, textLength: text.count)
    }
    
    // 将光标设置到文本末尾
    private func setCursorToEnd(element: AXUIElement, textLength: Int) {
        // 尝试设置选择范围到文本末尾
        var range = CFRangeMake(CFIndex(textLength), 0)
        let rangeValue = AXValueCreate(AXValueType.cfRange, &range)
        
        if let rangeValue = rangeValue {
            let result = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
            if result == .success {
                print("[LOG] Cursor moved to end of text")
            } else {
                print("[LOG] Failed to move cursor: \(result)")
                // 备用方法：尝试使用插入位置属性
                fallbackSetCursor(element: element, position: textLength)
            }
        }
    }
    
    // 备用光标设置方法
    private func fallbackSetCursor(element: AXUIElement, position: Int) {
        var range = CFRangeMake(CFIndex(position), 0)
        let positionValue = AXValueCreate(AXValueType.cfRange, &range)
        if let positionValue = positionValue {
            AXUIElementSetAttributeValue(element, kAXInsertionPointLineNumberAttribute as CFString, positionValue)
        }
    }
} 