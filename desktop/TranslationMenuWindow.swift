import Cocoa
import SwiftUI
import Carbon

class TranslationMenuWindow: NSWindow {
    static let shared = TranslationMenuWindow()
    
    private var selectedText: String = ""
    private var sourceElement: AXUIElement?
    private var hostingView: NSHostingView<TranslationMenuView>?
    var onMenuClosed: (() -> Void)?
    private var cachedBrowserInfo: AppInfo?
    private var lastMousePosition: NSPoint = .zero
    private var sourceElementPid: pid_t = 0
    
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
                self?.hide()
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
                    window.hide()
                }
            }
        }
        
        // 监听键盘事件，在用户按键时隐藏菜单
        keyEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if let window = self, window.isVisible {
                // 在任何键盘输入时隐藏菜单
                print("[LOG] Key pressed while menu visible, hiding menu")
                window.hide()
            }
        }
    }
    
    @objc private func windowDidResignKey() {
        // 延迟隐藏，给用户时间点击菜单
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if !self.isKeyWindow {
                self.hide()
            }
        }
    }
    
    func show(for text: String, from element: AXUIElement, at location: NSPoint, browserInfo: AppInfo?) {
        self.selectedText = text
        self.sourceElement = element
        self.lastMousePosition = location
        self.cachedBrowserInfo = browserInfo
        self.sourceElementPid = AXController.shared.getPid(for: element)
        
        setupEventHandlers()
        
        // 调整窗口位置
        var menuPoint = location
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
        menuPoint.y += 25 // 在光标上方显示
        
        if menuPoint.x + frame.width > screenFrame.maxX {
            menuPoint.x = screenFrame.maxX - frame.width - 5
        }
        if menuPoint.x < screenFrame.minX {
            menuPoint.x = screenFrame.minX + 5
        }
        if menuPoint.y + frame.height > screenFrame.maxY {
            menuPoint.y = location.y - frame.height - 5
        }
        
        self.setFrameTopLeftPoint(menuPoint)
        self.makeKeyAndOrderFront(nil)
        
        NSLog("[LOG] Translation menu shown at \(menuPoint) for text: '\(text)'")
    }
    
    func hide() {
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
            hide()
            return
        }
        
        // 检查源元素是否可编辑
        let isEditable = sourceElement != nil ? AXController.shared.isElementEditable(sourceElement!) : false
        NSLog("[LOG] Source element editable: \(isEditable)")
        NSLog("[LOG] Source element: \(sourceElement != nil ? "exists" : "nil")")
        
        // 隐藏菜单
        hide()
        
        if isEditable {
            // 可编辑元素：使用传统翻译 + 文本替换
            TranslationStatusWindow.shared.showTranslating(near: sourceElement)
            
            TranslatorClient.shared.translate(text: selectedText, to: language) { [weak self] translated in
                DispatchQueue.main.async {
                    if let translated = translated, !translated.isEmpty {
                        NSLog("[LOG] Translation result: \(translated)")
                        // 翻译成功后立即隐藏状态窗口，然后开始回填
                        TranslationStatusWindow.shared.hideStatus()
                        NSLog("[LOG] Status window hidden before text replacement")
                        
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
                        NSLog("[LOG] Translation failed or empty result")
                        TranslationStatusWindow.shared.showFailure()
                    }
                }
            }
        } else {
            // 不可编辑元素：使用流式翻译显示结果浮窗
            NSLog("[LOG] Using stream translation for non-editable element")
            showStreamTranslationResult(original: selectedText, targetLanguage: language)
        }
    }
    
    private func replaceSelectedText(in element: AXUIElement, with text: String, completion: @escaping () -> Void) {
        NSLog("[LOG] Attempting to replace selected text with: '\(text)'")
        NSLog("[LOG] Original selected text was: '\(selectedText)'")

        // 暂时禁用选中文本监听，防止我们的操作触发新的菜单
        AXController.shared.pauseSelectionMonitoring()

        let appInfo = AXController.shared.getAppInfo(for: element)
        let isBrowser = appInfo.isBrowser
        let isWeChat = appInfo.isWeChat
        
        var methodUsed: String?

        if isBrowser, appInfo.isChrome {
            // 对于Chrome浏览器，尝试使用JavaScript
            if replaceViaJavaScript(text: text) {
                methodUsed = "JavaScript"
            }
        }

        if methodUsed == nil {
             // 默认或后备方案：使用剪贴板
            replaceTextViaClipboard(with: text, isWeChat: isWeChat) {
                completion()
            }
            methodUsed = "Clipboard"
        } else {
            // 如果使用了其他方法，直接完成
            AXController.shared.resumeSelectionMonitoring()
            completion()
        }
        
        NSLog("[LOG] Text replacement method: \(methodUsed ?? "None")")
    }

    // 通过JavaScript替换文本（仅限Chrome）
    private func replaceViaJavaScript(text: String) -> Bool {
        guard let info = cachedBrowserInfo, info.isChrome, info.javaScriptPermissionsEnabled else {
            return false
        }
        
        // 使用Base64编码避免特殊字符问题
        let encodedText = encodeForJavaScript(text)
        
        let script = """
        try {
            var activeElement = document.activeElement;
            if (activeElement && (activeElement.isContentEditable || activeElement.tagName === 'INPUT' || activeElement.tagName === 'TEXTAREA')) {
                var start = activeElement.selectionStart;
                var end = activeElement.selectionEnd;
                var originalText = activeElement.value || activeElement.textContent;
                var newText = originalText.substring(0, start) + atob('\(encodedText)') + originalText.substring(end);
                activeElement.value = newText;
                activeElement.textContent = newText;

                // 触发输入事件，让框架（如React）能够识别变化
                var event = new Event('input', { bubbles: true, cancelable: true });
                activeElement.dispatchEvent(event);
            } else {
                // 如果没有活动元素，尝试在选区上操作
                var selection = window.getSelection();
                if (selection.rangeCount > 0) {
                    var range = selection.getRangeAt(0);
                    range.deleteContents();
                    range.insertNode(document.createTextNode(atob('\(encodedText)')));
                }
            }
        } catch(e) {
            // 错误处理
        }
        """
        
        let appleScript = """
        tell application "Google Chrome"
            execute javascript "\(script)" in active tab of first window
        end tell
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: appleScript) {
            if scriptObject.executeAndReturnError(&error).stringValue != nil {
                NSLog("[LOG] Successfully executed JavaScript replacement")
                return true
            } else if let errorInfo = error {
                NSLog("[LOG] AppleScript execution error: \(errorInfo)")
            }
        }
        return false
    }

    // 通过剪贴板替换文本
    private func replaceTextViaClipboard(with text: String, isWeChat: Bool, completion: @escaping () -> Void) {
        if isWeChat {
            // 微信有特殊处理
            replaceTextInWeChat(with: text, completion: completion)
        } else {
            // 通用方法
            replaceTextViaSimpleClipboard(with: text, completion: completion)
        }
    }
    
    // 最简化的剪贴板替换方法 - 已重构为更稳健的流程
    private func replaceTextViaSimpleClipboard(with text: String, completion: @escaping () -> Void) {
        NSLog("[LOG] Using enhanced clipboard replacement method for '\(text)'")
        
        let pasteboard = NSPasteboard.general
        let originalClipboard = pasteboard.string(forType: .string)
        
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            NSLog("[LOG] Failed to set clipboard content")
            restoreClipboard(originalClipboard)
            completion()
            return
        }
        
        guard pasteboard.string(forType: .string) == text else {
            NSLog("[LOG] ERROR: Clipboard content verification failed!")
            restoreClipboard(originalClipboard)
            completion()
            return
        }
        
        DispatchQueue.main.async {
            self.ensureOriginalAppFocus { focused in
                if focused {
                    self.ensureTextIsSelected(originalText: self.selectedText) { selected in
                        self.sendImmediatePasteCommand()
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.restoreClipboard(originalClipboard)
                            completion()
                        }
                    }
                } else {
                    NSLog("[LOG] Could not focus original app. Aborting replacement.")
                    self.restoreClipboard(originalClipboard)
                    completion()
                }
            }
        }
    }
    
    // 确保原应用获得焦点
    private func ensureOriginalAppFocus(completion: @escaping (Bool) -> Void) {
        if sourceElementPid != 0 {
             if let app = NSRunningApplication(processIdentifier: sourceElementPid) {
                app.activate(options: .activateIgnoringOtherApps)
                NSLog("[LOG] Activating app with pid: \(sourceElementPid)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { completion(true) }
                return
            }
        }

        guard let info = cachedBrowserInfo,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: info.bundleId).first else {
            NSLog("[LOG] Cannot get original app info to focus.")
            completion(false)
            return
        }
        
        app.activate(options: .activateIgnoringOtherApps)
        NSLog("[LOG] Activating app: \(info.appName)")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            completion(true)
        }
    }

    // 确保文本被选中
    private func ensureTextIsSelected(originalText: String, completion: @escaping (Bool) -> Void) {
        guard let element = sourceElement, let currentText = AXController.shared.getValue(of: element) else {
            completion(false)
            return
        }

        if currentText == originalText {
            NSLog("[LOG] Content matches original selected text. Using Cmd+A to select all.")
            sendSelectAllCommand()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { completion(true) }
            return
        }
        
        if originalText.count <= 50 {
             NSLog("[LOG] Short text detected. Attempting to double-click to re-select.")
            doubleClickToSelectText(at: lastMousePosition)
        } else {
            NSLog("[LOG] Long text detected. Using Cmd+A to select all.")
            sendSelectAllCommand()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            completion(true)
        }
    }

    // 在指定位置双击
    private func doubleClickToSelectText(at position: NSPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        let downEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: position, mouseButton: .left)
        let upEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: position, mouseButton: .left)
        
        downEvent?.setIntegerValueField(.mouseEventClickState, value: 2)
        upEvent?.setIntegerValueField(.mouseEventClickState, value: 2)

        downEvent?.post(tap: .cghidEventTap)
        upEvent?.post(tap: .cghidEventTap)
        NSLog("[LOG] Sent double-click event at \(position)")
    }
    
    // 立即发送粘贴命令（无延迟）
    private func sendImmediatePasteCommand() {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let cmdVDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let cmdVUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            NSLog("[LOG] Failed to create paste events")
            return
        }
        
        cmdVDown.flags = .maskCommand
        cmdVUp.flags = .maskCommand
        
        cmdVDown.post(tap: .cghidEventTap)
        usleep(50000) // 50ms
        cmdVUp.post(tap: .cghidEventTap)
        NSLog("[LOG] Sent immediate paste command.")
    }

    // 微信特殊文本替换方法
    private func replaceTextInWeChat(with text: String, completion: @escaping () -> Void) {
        NSLog("[LOG] Using enhanced WeChat-specific text replacement")
        
        let pasteboard = NSPasteboard.general
        let originalClipboard = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            NSLog("[LOG] WeChat: Failed to set clipboard")
            restoreClipboard(originalClipboard)
            completion()
            return
        }

        // 核心流程：激活微信 -> 全选 -> 粘贴
        ensureOriginalAppFocus { focused in
            guard focused else {
                NSLog("[LOG] WeChat: Failed to focus app.")
                self.restoreClipboard(originalClipboard)
                completion()
                return
            }
            
            // 等待焦点稳定
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSLog("[LOG] WeChat: Sending Cmd+A to select text.")
                self.sendSelectAllCommand()
                
                // 等待全选完成
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    NSLog("[LOG] WeChat: Sending paste command.")
                    self.sendImmediatePasteCommand()
                    
                    // 延迟恢复剪贴板，确保粘贴完成
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.restoreClipboard(originalClipboard)
                        completion()
                    }
                }
            }
        }
    }
    
    // 显示翻译结果浮窗 - 一次性翻译
    private func showTranslationResult(original: String, translated: String) {
        let resultWindow = TranslationResultWindow(original: original, translated: translated)
        resultWindow.showAt(point: lastMousePosition)
    }
    
    // 显示流式翻译结果浮窗 - 新增
    private func showStreamTranslationResult(original: String, targetLanguage: String) {
        let streamWindow = TranslationResultWindow(originalText: original, targetLanguage: targetLanguage)
        streamWindow.showAt(point: lastMousePosition)
    }

    // 恢复剪贴板内容
    private func restoreClipboard(_ originalClipboard: String?) {
        let pasteboard = NSPasteboard.general
        if let original = originalClipboard {
            pasteboard.clearContents()
            pasteboard.setString(original, forType: .string)
            NSLog("[LOG] Restored original clipboard content: '\(original)'")
        } else {
            pasteboard.clearContents()
            NSLog("[LOG] Cleared clipboard as there was no original content.")
        }
        
        AXController.shared.resumeSelectionMonitoring()
        NSLog("[LOG] Resumed selection monitoring")
    }
    
    // #@指令场景的剪贴板替换方法
    func replaceTextViaClipboardForTrigger(with text: String, completion: @escaping () -> Void) {
        NSLog("[LOG] Using clipboard replacement for #@ trigger")
        
        let pasteboard = NSPasteboard.general
        let originalClipboard = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            NSLog("[LOG] Failed to set clipboard for trigger")
            completion()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSLog("[LOG] Sending Cmd+A to select all content before paste")
            self.sendSelectAllCommand()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSLog("[LOG] Sending paste command to replace selected content")
                self.sendImmediatePasteCommand()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.restoreClipboard(originalClipboard)
                        completion()
                    }
                }
            }
        }
    }
    
    // 发送Cmd+A命令
    private func sendSelectAllCommand() {
        let source = CGEventSource(stateID: .hidSystemState)
        let cmdADown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_A), keyDown: true)
        cmdADown?.flags = .maskCommand
        cmdADown?.post(tap: .cghidEventTap)
        
        let cmdAUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_A), keyDown: false)
        cmdAUp?.flags = .maskCommand
        cmdAUp?.post(tap: .cghidEventTap)
        
        NSLog("[LOG] Sent Cmd+A select all command")
    }
    
    // 输入文本
    private func typeText(_ text: String) {
        for char in text.unicodeScalars {
            if let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) {
                var unichar = UniChar(char.value)
                event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
                event.post(tap: .cghidEventTap)
                
                if let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
                     keyUpEvent.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
                     keyUpEvent.post(tap: .cghidEventTap)
                }
            }
        }
        NSLog("[LOG] Typed text: '\(text)'")
    }
    
    // 使用Base64编码来安全传递文本到JavaScript，避免转义问题
    private func encodeForJavaScript(_ text: String) -> String {
        guard let data = text.data(using: .utf8) else {
            return ""
        }
        return data.base64EncodedString()
    }
    
    // 显示Chrome JavaScript权限设置提示
    private func showChromeJavaScriptPermissionAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Chrome JavaScript权限设置"
            alert.informativeText = """
            为了在浏览器中实现精确的文本替换，需要启用Chrome的JavaScript权限。
            
            请按以下步骤设置：
            1. 在Chrome浏览器中，点击菜单栏的"查看"
            2. 选择 "开发者" -> "允许来自Apple事件的JavaScript"
            
            如果找不到该选项，请确保Chrome已更新到最新版本。
            
            设置完成后，此功能将自动启用。如果选择不设置，将继续使用剪贴板进行替换。
            """
            alert.alertStyle = .informational
            
            alert.addButton(withTitle: "好的")
            alert.addButton(withTitle: "复制设置路径")
            
            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString("查看 > 开发者 > 允许来自Apple事件的JavaScript", forType: .string)
                
                let confirmationAlert = NSAlert()
                confirmationAlert.messageText = "路径已复制"
                confirmationAlert.informativeText = "设置路径已复制到剪贴板。"
                confirmationAlert.runModal()
            }
        }
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