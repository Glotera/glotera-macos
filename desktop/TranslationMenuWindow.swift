import Cocoa
import SwiftUI
import Carbon

class TranslationMenuWindow: NSWindow {
    static let shared = TranslationMenuWindow()
    
    private var selectedText: String = ""
    private var sourceElement: AXUIElement?
    private var hostingView: NSHostingView<TranslationMenuView>?
    private var onMenuClosed: (() -> Void)?
    
    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = NSColor.clear
        self.hasShadow = true
        self.isMovableByWindowBackground = false
        
        setupContent()
        // 不在初始化时设置事件监听器，而是在显示菜单时设置
    }
    
    deinit {
        // 确保在销毁时清理所有事件监听器
        if let monitor = mouseEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        
        // 清理通知观察者
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupContent() {
        let menuView = TranslationMenuView(
            onTranslate: { [weak self] language in
                self?.translateToLanguage(language)
            },
            onClose: { [weak self] in
                self?.hideMenu()
            }
        )
        
        hostingView = NSHostingView(rootView: menuView)
        self.contentView = hostingView
    }
    
    private var mouseEventMonitor: Any?
    private var keyEventMonitor: Any?
    
    private func setupEventHandlers() {
        // 先清理旧的事件监听器
        if let monitor = mouseEventMonitor {
            NSEvent.removeMonitor(monitor)
            mouseEventMonitor = nil
        }
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
        
        // 监听失去焦点事件（只需要添加一次）
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: self
        )
        
        // 监听鼠标点击外部区域
        mouseEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let window = self, window.isVisible {
                let clickLocation = NSEvent.mouseLocation
                let windowFrame = window.frame
                
                // 如果点击在窗口外部，隐藏菜单
                if !windowFrame.contains(clickLocation) {
                    window.hideMenu()
                }
            }
        }
        
        // 监听键盘事件，在用户按键时隐藏菜单
        keyEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if let window = self, window.isVisible {
                // 在任何键盘输入时隐藏菜单
                print("[LOG] Key pressed while menu visible, hiding menu")
                window.hideMenu()
            }
        }
    }
    
    @objc private func windowDidResignKey() {
        // 延迟隐藏，给用户时间点击菜单
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if !self.isKeyWindow {
                self.hideMenu()
            }
        }
    }
    
    func showMenu(at point: NSPoint, with text: String, sourceElement: AXUIElement?, onMenuClosed: @escaping () -> Void) {
        self.selectedText = text
        self.sourceElement = sourceElement
        self.onMenuClosed = onMenuClosed
        
        // 重新设置事件监听器（确保每次显示菜单时都有新的监听器）
        setupEventHandlers()
        
        // 调整窗口位置，确保不超出屏幕边界
        var menuPoint = point
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
        
        // 水平位置调整
        if menuPoint.x + self.frame.width > screenFrame.maxX {
            menuPoint.x = screenFrame.maxX - self.frame.width - 10
        }
        if menuPoint.x < screenFrame.minX {
            menuPoint.x = screenFrame.minX + 10
        }
        
        // 垂直位置调整 - 显示在选中文本上方
        menuPoint.y += 30
        if menuPoint.y + self.frame.height > screenFrame.maxY {
            menuPoint.y = point.y - self.frame.height - 10
        }
        
        self.setFrameTopLeftPoint(menuPoint)
        self.orderFront(nil)
        // 不要调用 makeKey()，避免抢夺焦点影响选中状态
        
        NSLog("[LOG] Translation menu shown at \(menuPoint) for text: '\(text)'")
    }
    
    func hideMenu() {
        self.orderOut(nil)
        onMenuClosed?()
        onMenuClosed = nil
        
        // 清理事件监听器
        if let monitor = mouseEventMonitor {
            NSEvent.removeMonitor(monitor)
            mouseEventMonitor = nil
        }
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
        
        NSLog("[LOG] Translation menu hidden")
    }
    
    // 重写方法以控制窗口焦点行为
    override var canBecomeKey: Bool {
        return true  // 允许菜单接收点击事件
    }
    
    override var canBecomeMain: Bool {
        return false
    }
    
    private func translateToLanguage(_ language: String) {
        NSLog("[LOG] Translating to language: \(language)")
        
        guard !selectedText.isEmpty else {
            NSLog("[LOG] No text selected for translation")
            hideMenu()
            return
        }
        
        // 检查源元素是否可编辑
        let isEditable = sourceElement != nil ? AXController.shared.isElementEditable(sourceElement!) : false
        NSLog("[LOG] Source element editable: \(isEditable)")
        NSLog("[LOG] Source element: \(sourceElement != nil ? "exists" : "nil")")
        
        // 隐藏菜单，显示翻译状态
        hideMenu()
        TranslationStatusWindow.shared.showTranslating(near: sourceElement)
        
        // 开始翻译
        TranslatorClient.shared.translate(text: selectedText, to: language) { [weak self] translated in
            DispatchQueue.main.async {
                if let translated = translated, !translated.isEmpty {
                    NSLog("[LOG] Translation result: \(translated)")
                    // 翻译成功后立即隐藏状态窗口，然后开始回填
                    TranslationStatusWindow.shared.hideStatus()
                    NSLog("[LOG] Status window hidden before text replacement")
                    
                    if isEditable {
                        // 可编辑元素：替换选中的文本
                        NSLog("[LOG] Replacing text in editable element")
                        if let element = self?.sourceElement {
                            self?.replaceSelectedText(in: element, with: translated) {
                                NSLog("[LOG] Text replacement completed")
                            }
                        } else {
                            NSLog("[LOG] No source element available for text replacement")
                        }
                    } else {
                        // 不可编辑元素：显示翻译结果浮窗
                        NSLog("[LOG] Showing translation result in popup")
                        self?.showTranslationResult(original: self?.selectedText ?? "", translated: translated)
                    }
                } else {
                    NSLog("[LOG] Translation failed or empty result")
                    TranslationStatusWindow.shared.showFailure()
                }
            }
        }
    }
    
    private func replaceSelectedText(in element: AXUIElement, with text: String, completion: @escaping () -> Void) {
        NSLog("[LOG] Attempting to replace selected text with: '\(text)'")
        NSLog("[LOG] Original selected text was: '\(selectedText)'")
        
        // 暂时禁用选中文本监听，防止我们的操作触发新的菜单
        AXController.shared.pauseSelectionMonitoring()
        
        // 尝试直接使用 AX API 设置文本
        if tryDirectTextReplacement(in: element, with: text) {
            NSLog("[LOG] Successfully replaced text using AX API")
            // 重新启用选中文本监听
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                AXController.shared.resumeSelectionMonitoring()
                completion() // 调用完成回调
            }
        } else {
            NSLog("[LOG] AX API failed, falling back to clipboard method")
            // 使用剪贴板方法作为后备
            replaceTextViaSimpleClipboard(with: text, completion: completion)
        }
    }
    
    // 尝试直接使用 AX API 替换文本
    private func tryDirectTextReplacement(in element: AXUIElement, with text: String) -> Bool {
        NSLog("[LOG] Trying AX API text replacement")
        
        // 方法1: 尝试直接设置选中文本
        let setSelectedResult = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
        if setSelectedResult == .success {
            NSLog("[LOG] AX API reported success, but let's verify...")
            
            // 验证文本是否真的被设置了
            var currentSelectedText: CFTypeRef?
            let getResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &currentSelectedText)
            
            if getResult == .success, 
               let currentText = currentSelectedText as? String,
               currentText == text {
                NSLog("[LOG] Text replacement verified successful: '\(currentText)'")
                // 设置光标到文本末尾
                setCursorToEndOfText(in: element, textLength: text.count)
                return true
            } else {
                NSLog("[LOG] Text replacement verification failed. Current text: '\(currentSelectedText as? String ?? "nil")'")
            }
        } else {
            NSLog("[LOG] Failed to set selected text using AX API: \(setSelectedResult)")
        }
        
        // 方法2: 尝试使用 kAXValueAttribute
        let setValueResult = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFString)
        if setValueResult == .success {
            NSLog("[LOG] Successfully set value using AX API")
            
            // 验证值是否真的被设置了
            var currentValue: CFTypeRef?
            let getValueResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentValue)
            
            if getValueResult == .success,
               let currentText = currentValue as? String,
               currentText.contains(text) {
                NSLog("[LOG] Value replacement verified successful")
                // 设置光标到文本末尾
                setCursorToEndOfText(in: element, textLength: currentText.count)
                return true
            } else {
                NSLog("[LOG] Value replacement verification failed")
            }
        } else {
            NSLog("[LOG] Failed to set value using AX API: \(setValueResult)")
        }
        
        NSLog("[LOG] All AX API methods failed, falling back to clipboard")
        return false
    }
    
    // 设置光标到文本末尾
    private func setCursorToEndOfText(in element: AXUIElement, textLength: Int) {
        NSLog("[LOG] Setting cursor to end of text (length: \(textLength))")
        
        // 方法1: 尝试设置选中范围到文本末尾（选中长度为0，即光标位置）
        let endPosition = textLength
        var selectionRange = CFRangeMake(endPosition, 0)
        
        // 创建 AXValue 来表示选中范围
        let rangeValue = AXValueCreate(AXValueType.cfRange, &selectionRange)
        if let rangeValue = rangeValue {
            let setRangeResult = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
            if setRangeResult == .success {
                NSLog("[LOG] Successfully set cursor to end using selection range")
                return
            } else {
                NSLog("[LOG] Failed to set cursor using selection range: \(setRangeResult)")
            }
        }
        
        // 方法2: 尝试设置插入点位置
        let insertionPointValue = AXValueCreate(AXValueType.cfRange, &selectionRange)
        if let insertionPointValue = insertionPointValue {
            let setInsertionResult = AXUIElementSetAttributeValue(element, kAXInsertionPointLineNumberAttribute as CFString, insertionPointValue)
            if setInsertionResult == .success {
                NSLog("[LOG] Successfully set cursor using insertion point")
                return
            } else {
                NSLog("[LOG] Failed to set cursor using insertion point: \(setInsertionResult)")
            }
        }
        
        // 方法3: 使用键盘快捷键移动光标到末尾
        NSLog("[LOG] Using keyboard shortcut to move cursor to end")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // 发送 Cmd+Right 或 End 键来移动光标到行尾
            self.sendEndKeyCommand()
        }
    }
    
    // 发送 End 键命令
    private func sendEndKeyCommand() {
        let source = CGEventSource(stateID: .hidSystemState)
        
        // 尝试 Cmd+Right Arrow (在 macOS 中通常用于移动到行尾)
        let cmdRightDown = CGEvent(keyboardEventSource: source, virtualKey: 0x7C, keyDown: true) // Right Arrow
        cmdRightDown?.flags = .maskCommand
        cmdRightDown?.post(tap: .cghidEventTap)
        
        let cmdRightUp = CGEvent(keyboardEventSource: source, virtualKey: 0x7C, keyDown: false)
        cmdRightUp?.flags = .maskCommand
        cmdRightUp?.post(tap: .cghidEventTap)
        
        NSLog("[LOG] Sent Cmd+Right to move cursor to end")
    }
    
    // 最简化的剪贴板替换方法
    private func replaceTextViaSimpleClipboard(with text: String, completion: @escaping () -> Void) {
        NSLog("[LOG] Using simple clipboard replacement method")
        
        // 保存当前剪贴板内容
        let pasteboard = NSPasteboard.general
        let originalClipboard = pasteboard.string(forType: .string)
        NSLog("[LOG] Saved original clipboard: '\(originalClipboard ?? "nil")'")
        
        // 将新文本放入剪贴板
        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)
        
        if !success {
            NSLog("[LOG] Failed to set clipboard content")
            completion() // 即使失败也调用完成回调
            return
        }
        
        // 验证剪贴板内容是否正确设置
        let verifyContent = pasteboard.string(forType: .string)
        NSLog("[LOG] Set clipboard to: '\(text)', verified: '\(verifyContent ?? "nil")'")
        
        if verifyContent != text {
            NSLog("[LOG] ERROR: Clipboard content verification failed!")
            completion()
            return
        }
        
        // 直接粘贴，不要点击元素（避免取消选中状态）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // 在粘贴前再次验证剪贴板内容
            let prepasteContent = pasteboard.string(forType: .string)
            NSLog("[LOG] Pre-paste clipboard content: '\(prepasteContent ?? "nil")'")
            
            if prepasteContent != text {
                NSLog("[LOG] ERROR: Clipboard content changed before paste! Re-setting...")
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                
                // 再次验证
                let reVerifyContent = pasteboard.string(forType: .string)
                NSLog("[LOG] Re-verified clipboard content: '\(reVerifyContent ?? "nil")'")
            }
            
            self.sendPasteCommand()
            
            // 粘贴完成后，将光标移动到文本末尾
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.sendEndKeyCommand()
                
                // 调用完成回调
                completion()
                
                // 延迟恢复剪贴板
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    self.restoreClipboard(originalClipboard)
                }
            }
        }
    }
    
    // 激活原应用并粘贴
    private func activateOriginalAppAndPaste(originalClipboard: String?) {
        // 获取当前前台应用并激活
        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            print("[LOG] Current frontmost app: \(frontmostApp.localizedName ?? "Unknown")")
        }
        
        // 尝试点击原来的元素来重新获得焦点
        if let element = sourceElement {
            // 获取元素的位置并点击
            var position: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position)
            
            if result == .success, 
               let positionValue = position,
               let point = getPointFromAXValue(positionValue) {
                
                print("[LOG] Clicking at element position: \(point)")
                
                // 模拟鼠标点击以重新获得焦点
                let clickEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
                clickEvent?.post(tap: .cghidEventTap)
                
                let releaseEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
                releaseEvent?.post(tap: .cghidEventTap)
                
                // 等待点击完成，然后重新选中原始文本并粘贴
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.reselectOriginalTextAndPaste(originalClipboard: originalClipboard)
                }
            } else {
                print("[LOG] Failed to get element position, trying direct reselect and paste")
                self.reselectOriginalTextAndPaste(originalClipboard: originalClipboard)
            }
        } else {
            print("[LOG] No source element, trying direct paste")
            self.sendPasteCommand()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.restoreClipboard(originalClipboard)
            }
        }
    }
    
    // 重新选中原始文本并粘贴
    private func reselectOriginalTextAndPaste(originalClipboard: String?) {
        print("[LOG] Attempting to reselect original text: '\(selectedText)'")
        
        // 检查是否在微信等特殊应用中
        if let frontmostApp = NSWorkspace.shared.frontmostApplication,
           let bundleId = frontmostApp.bundleIdentifier {
            
            if bundleId.contains("wechat") || bundleId.contains("WeChat") {
                print("[LOG] Detected WeChat, using special replacement method")
                self.replaceTextInWeChat(originalClipboard: originalClipboard)
                return
            }
        }
        
        // 对于其他应用，尝试重新选中原始文本
        if tryReselectOriginalText() {
            print("[LOG] Successfully reselected original text, now pasting")
            // 等待选择完成后粘贴
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.sendPasteCommand()
                
                // 延迟恢复剪贴板
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.restoreClipboard(originalClipboard)
                }
            }
        } else {
            print("[LOG] Failed to reselect original text, using fallback method")
            // 如果无法重新选中，使用全选+粘贴的方法
            self.sendSelectAllCommand()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.sendPasteCommand()
                
                // 延迟恢复剪贴板
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.restoreClipboard(originalClipboard)
                }
            }
        }
    }
    
    // 尝试重新选中原始文本
    private func tryReselectOriginalText() -> Bool {
        guard sourceElement != nil else { return false }
        
        // 检查是否在微信等特殊应用中
        if let frontmostApp = NSWorkspace.shared.frontmostApplication,
           let bundleId = frontmostApp.bundleIdentifier {
            
            if bundleId.contains("wechat") || bundleId.contains("WeChat") {
                print("[LOG] Detected WeChat, using special text selection method")
                return reselectTextInWeChat()
            }
        }
        
        // 对于其他应用，尝试通过查找文本来重新选中
        return reselectTextBySearching()
    }
    
    // 在微信中重新选中文本的特殊方法
    private func reselectTextInWeChat() -> Bool {
        // 在微信中，我们使用 Cmd+A 全选，然后通过查找来定位文本
        // 但由于微信的特殊性，我们直接使用全选方法
        sendSelectAllCommand()
        return true
    }
    
    // 通过搜索来重新选中文本
    private func reselectTextBySearching() -> Bool {
        // 使用 Cmd+F 打开查找，然后搜索原始文本
        print("[LOG] Trying to reselect text by searching")
        
        // 发送 Cmd+F 打开查找
        sendFindCommand()
        
        // 等待查找框打开
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // 输入要查找的文本
            self.typeText(self.selectedText)
            
            // 等待输入完成后按回车
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.sendEnterCommand()
                
                // 关闭查找框
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.sendEscapeCommand()
                }
            }
        }
        
        return true
    }
    
    // 从AXValue中提取CGPoint
    private func getPointFromAXValue(_ axValue: CFTypeRef) -> CGPoint? {
        var point = CGPoint.zero
        let success = AXValueGetValue(axValue as! AXValue, .cgPoint, &point)
        return success ? point : nil
    }
    
    // 发送Cmd+V粘贴命令
    private func sendPasteCommand() {
        // 添加延迟，确保InputMonitor完成当前事件处理
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let source = CGEventSource(stateID: .hidSystemState)
            
            // 创建Cmd+V事件
            guard let cmdVDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
                  let cmdVUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
                print("[LOG] Failed to create Cmd+V events")
                return
            }
            
            // 设置Command键标志
            cmdVDown.flags = CGEventFlags.maskCommand
            cmdVUp.flags = CGEventFlags.maskCommand
            
            // 恢复使用原始tap位置，但通过时序避免冲突
            cmdVDown.post(tap: CGEventTapLocation.cghidEventTap)
            usleep(50000) // 50ms delay
            cmdVUp.post(tap: CGEventTapLocation.cghidEventTap)
            
            print("[LOG] Sent Cmd+V paste command (with timing separation)")
        }
    }
    
    // 显示翻译结果浮窗
    private func showTranslationResult(original: String, translated: String) {
        print("[LOG] Creating translation result popup")
        
        // 创建翻译结果窗口
        let resultWindow = TranslationResultWindow(original: original, translated: translated)
        
        // 获取当前鼠标位置
        let mouseLocation = NSEvent.mouseLocation
        
        // 显示窗口在鼠标附近
        resultWindow.showAt(point: mouseLocation)
        
        // 不再自动隐藏，改为手动关闭
    }

    // 恢复剪贴板内容
    private func restoreClipboard(_ originalClipboard: String?) {
        let pasteboard = NSPasteboard.general
        if let original = originalClipboard {
            pasteboard.clearContents()
            pasteboard.setString(original, forType: .string)
            print("[LOG] Restored original clipboard content")
        } else {
            pasteboard.clearContents()
            print("[LOG] Cleared clipboard as no original content")
        }
        
        // 重新启用选中文本监听
        AXController.shared.resumeSelectionMonitoring()
        print("[LOG] Resumed selection monitoring")
    }
    
    // 微信特殊文本替换方法
    private func replaceTextInWeChat(originalClipboard: String?) {
        print("[LOG] Using WeChat-specific text replacement")
        // 在微信中，直接粘贴通常会正确替换选中的文本
        sendPasteCommand()
        
        // 延迟恢复剪贴板
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.restoreClipboard(originalClipboard)
        }
    }
    
    // 发送Cmd+A全选命令
    private func sendSelectAllCommand() {
        let source = CGEventSource(stateID: .hidSystemState)
        
        guard let cmdADown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_A), keyDown: true),
              let cmdAUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_A), keyDown: false) else {
            print("[LOG] Failed to create Cmd+A events")
            return
        }
        
        cmdADown.flags = CGEventFlags.maskCommand
        cmdAUp.flags = CGEventFlags.maskCommand
        
        cmdADown.post(tap: .cghidEventTap)
        usleep(50000)
        cmdAUp.post(tap: .cghidEventTap)
        
        print("[LOG] Sent Cmd+A select all command")
    }
    
    // 发送Cmd+F查找命令
    private func sendFindCommand() {
        let source = CGEventSource(stateID: .hidSystemState)
        
        guard let cmdFDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_F), keyDown: true),
              let cmdFUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_F), keyDown: false) else {
            print("[LOG] Failed to create Cmd+F events")
            return
        }
        
        cmdFDown.flags = CGEventFlags.maskCommand
        cmdFUp.flags = CGEventFlags.maskCommand
        
        cmdFDown.post(tap: .cghidEventTap)
        usleep(50000)
        cmdFUp.post(tap: .cghidEventTap)
        
        print("[LOG] Sent Cmd+F find command")
    }
    
    // 输入文本
    private func typeText(_ text: String) {
        for char in text {
            if let keyCode = getKeyCodeForCharacter(char) {
                let source = CGEventSource(stateID: .hidSystemState)
                
                if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
                   let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
                    
                    keyDown.post(tap: .cghidEventTap)
                    usleep(30000) // 30ms delay between keys
                    keyUp.post(tap: .cghidEventTap)
                }
            }
        }
        print("[LOG] Typed text: '\(text)'")
    }
    
    // 获取字符对应的键码
    private func getKeyCodeForCharacter(_ char: Character) -> CGKeyCode? {
        // 简化版本，只处理基本字符
        switch char {
        case "a": return CGKeyCode(kVK_ANSI_A)
        case "b": return CGKeyCode(kVK_ANSI_B)
        case "c": return CGKeyCode(kVK_ANSI_C)
        // ... 可以扩展更多字符
        default: return nil
        }
    }
    
    // 发送回车命令
    private func sendEnterCommand() {
        let source = CGEventSource(stateID: .hidSystemState)
        
        guard let enterDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: true),
              let enterUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: false) else {
            print("[LOG] Failed to create Enter events")
            return
        }
        
        enterDown.post(tap: .cghidEventTap)
        usleep(50000)
        enterUp.post(tap: .cghidEventTap)
        
        print("[LOG] Sent Enter command")
    }
    
    // 发送Escape命令
    private func sendEscapeCommand() {
        let source = CGEventSource(stateID: .hidSystemState)
        
        guard let escDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Escape), keyDown: true),
              let escUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Escape), keyDown: false) else {
            print("[LOG] Failed to create Escape events")
            return
        }
        
        escDown.post(tap: .cghidEventTap)
        usleep(50000)
        escUp.post(tap: .cghidEventTap)
        
        print("[LOG] Sent Escape command")
    }
}

struct TranslationMenuView: View {
    let onTranslate: (String) -> Void
    let onClose: () -> Void
    
    @State private var selectedLanguage: String = "en"
    @State private var isDropdownOpen: Bool = false
    
    private let languages = [
        ("en", "English"),
        ("zh", "中文"),
        ("ja", "日本語"),
        ("ko", "한국어"),
        ("fr", "Français"),
        ("de", "Deutsch"),
        ("es", "Español"),
        ("ru", "Русский"),
        ("th", "ไทย"),
        ("id", "Bahasa")
    ]
    
    var body: some View {
        HStack(spacing: 8) {
            // "Translate to" 标签 - 可点击
            Button(action: {
                // 直接使用当前选中的语言进行翻译
                onTranslate(selectedLanguage)
            }) {
                Text("Translate To")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { isHovered in
                if isHovered {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            
            // 语言选择下拉菜单
            Menu {
                ForEach(languages, id: \.0) { code, name in
                    Button(action: {
                        selectedLanguage = code
                        // 延迟执行翻译，确保菜单有时间关闭
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            onTranslate(code)
                        }
                    }) {
                        HStack {
                            Text(name)
                            if code == selectedLanguage {
                                Spacer()
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            } label: {
                Text(languages.first { $0.0 == selectedLanguage }?.1 ?? "English")
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                            )
                    )
            }
            .menuStyle(BorderlessButtonMenuStyle())
            .fixedSize()
            
            // 关闭按钮
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { isHovered in
                if isHovered {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }
} 