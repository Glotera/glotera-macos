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
        setupEventHandlers()
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
    
    private func setupEventHandlers() {
        // 监听失去焦点事件
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: self
        )
        
        // 监听鼠标点击外部区域
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let window = self, window.isVisible {
                let clickLocation = NSEvent.mouseLocation
                let windowFrame = window.frame
                
                // 如果点击在窗口外部，隐藏菜单
                if !windowFrame.contains(clickLocation) {
                    window.hideMenu()
                }
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
        self.makeKey()
        
        print("[LOG] Translation menu shown at \(menuPoint) for text: '\(text)'")
    }
    
    func hideMenu() {
        self.orderOut(nil)
        onMenuClosed?()
        onMenuClosed = nil
        print("[LOG] Translation menu hidden")
    }
    
    // 重写方法以控制窗口焦点行为
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return false
    }
    
    private func translateToLanguage(_ language: String) {
        print("[LOG] Translating to language: \(language)")
        
        guard !selectedText.isEmpty else {
            print("[LOG] No text selected for translation")
            hideMenu()
            return
        }
        
        // 检查源元素是否可编辑
        let isEditable = sourceElement != nil ? AXController.shared.isElementEditable(sourceElement!) : false
        print("[LOG] Source element editable: \(isEditable)")
        
        // 隐藏菜单，显示翻译状态
        hideMenu()
        TranslationStatusWindow.shared.showTranslating(near: sourceElement)
        
        // 开始翻译
        TranslatorClient.shared.translate(text: selectedText, to: language) { [weak self] translated in
            DispatchQueue.main.async {
                if let translated = translated, !translated.isEmpty {
                    print("[LOG] Translation result: \(translated)")
                    TranslationStatusWindow.shared.showSuccess()
                    
                    if isEditable {
                        // 可编辑元素：替换选中的文本
                        print("[LOG] Replacing text in editable element")
                        if let element = self?.sourceElement {
                            self?.replaceSelectedText(in: element, with: translated)
                        } else {
                            print("[LOG] No source element available for text replacement")
                        }
                    } else {
                        // 不可编辑元素：显示翻译结果浮窗
                        print("[LOG] Showing translation result in popup")
                        self?.showTranslationResult(original: self?.selectedText ?? "", translated: translated)
                    }
                } else {
                    print("[LOG] Translation failed or empty result")
                    TranslationStatusWindow.shared.showFailure()
                }
            }
        }
    }
    
    private func replaceSelectedText(in element: AXUIElement, with text: String) {
        print("[LOG] Attempting to replace selected text with: '\(text)'")
        print("[LOG] Original selected text was: '\(selectedText)'")
        
        // 暂时禁用选中文本监听，防止我们的操作触发新的菜单
        AXController.shared.pauseSelectionMonitoring()
        
        // 使用最简单直接的方法：剪贴板替换
        replaceTextViaSimpleClipboard(with: text)
    }
    
    // 最简化的剪贴板替换方法
    private func replaceTextViaSimpleClipboard(with text: String) {
        print("[LOG] Using simple clipboard replacement method")
        
        // 保存当前剪贴板内容
        let pasteboard = NSPasteboard.general
        let originalClipboard = pasteboard.string(forType: .string)
        print("[LOG] Saved original clipboard: '\(originalClipboard ?? "nil")'")
        
        // 将新文本放入剪贴板
        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)
        
        if !success {
            print("[LOG] Failed to set clipboard content")
            return
        }
        
        print("[LOG] Set clipboard to: '\(text)'")
        
        // 重新激活原来的应用，然后粘贴
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.activateOriginalAppAndPaste(originalClipboard: originalClipboard)
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
                
                // 等待点击完成，然后粘贴
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.sendPasteCommand()
                    
                    // 延迟恢复剪贴板
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.restoreClipboard(originalClipboard)
                    }
                }
            } else {
                print("[LOG] Failed to get element position, trying direct paste")
                self.sendPasteCommand()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.restoreClipboard(originalClipboard)
                }
            }
        } else {
            print("[LOG] No source element, trying direct paste")
            self.sendPasteCommand()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.restoreClipboard(originalClipboard)
            }
        }
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
                HStack(spacing: 4) {
                    Text(languages.first { $0.0 == selectedLanguage }?.1 ?? "English")
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
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