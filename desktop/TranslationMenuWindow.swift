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
    private var currentStreamWindow: TranslationResultWindow?
    
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
                Logger.debug("Key pressed while menu visible, hiding menu")
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
        self.sourceElementPid = AppDetectionManager.shared.getPid(for: element)
        
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
        
        // 清理当前流式翻译窗口引用
        currentStreamWindow = nil
        
        Logger.debug("Translation menu hidden")
    }
    
    // 重写方法以控制窗口焦点行为
    override var canBecomeKey: Bool {
        return true  // 允许菜单接收点击事件
    }
    
    override var canBecomeMain: Bool {
        return false
    }
     
    private func translateToLanguage(_ language: String) {
        Logger.debug("Translating to language: \(language)")
        
        guard !selectedText.isEmpty else {
            Logger.warn("No text selected for translation")
            hide()
            return
        }
        
        // 检查源元素是否可编辑
        let isEditable = sourceElement != nil ? AXController.shared.isElementEditable(sourceElement!) : false 
        
        // 隐藏菜单
        hide()
        
        if isEditable {

            // 对于可编辑元素，直接使用新的"仅粘贴"方法替换选中文本
            TranslationStatusWindow.shared.showTranslating(near: sourceElement, mousePoint: lastMousePosition)
            
            // Check login status before translation
            guard SessionManager.shared.isAuthenticated else {
                Logger.info("User not logged in, showing login prompt")
                UserManager.shared.promptLogin(reason: "Please sign in to use Glotera.")
                return
            }
            
            // User is logged in, proceed with normal translation
            TranslatorClient.shared.translate(text: selectedText, to: language) { [weak self] result in
                DispatchQueue.main.async {
                    TranslationStatusWindow.shared.hideStatus()
                    switch result {
                    case .success(let translationResult):
                        if let self = self {
                            // 调用新的、只粘贴不全选的方法
                            AXController.shared.replaceSelectionWithPaste(with: translationResult.translated, for: self.sourceElementPid) {
                                Logger.info("Selection replaced successfully.")
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
                            TranslationStatusWindow.shared.showFailure()
                        }
                        // 翻译失败后也清除缓存的应用信息
                        EnvironmentManager.shared.clearTriggerAppInfo()
                    }
                }
            }
        } else {
            // 对于不可编辑的元素，显示一个浮动窗口展示翻译结果（保留原逻辑）
            // Check login status before stream translation
            guard SessionManager.shared.isAuthenticated else {
                Logger.info("User not logged in for stream translation, showing login prompt")
                UserManager.shared.promptLogin(reason: "Please sign in to use Glotera.")
                return
            }
            
            // User is logged in, proceed with stream translation
            showStreamTranslationResult(original: selectedText, targetLanguage: language)
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
        Logger.info("Sent double-click event at \(position)")
    }
   
    
    // 显示翻译结果浮窗 - 一次性翻译
    private func showTranslationResult(original: String, translated: String) {
        let resultWindow = TranslationResultWindow(original: original, translated: translated)
        resultWindow.showAt(point: lastMousePosition)
    }
    
    // 显示流式翻译结果浮窗 - 新增
    private func showStreamTranslationResult(original: String, targetLanguage: String) {
        // 先清理之前的窗口
        currentStreamWindow?.hide()
        
        // 创建新的流式翻译窗口并持有强引用
        currentStreamWindow = TranslationResultWindow(originalText: original, targetLanguage: targetLanguage)
        currentStreamWindow?.showAt(point: lastMousePosition)
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
        Logger.info("Typed text: '\(text)'")
    }
    
    // 使用Base64编码来安全传递文本到JavaScript，避免转义问题
    private func encodeForJavaScript(_ text: String) -> String {
        guard let data = text.data(using: .utf8) else {
            return ""
        }
        return data.base64EncodedString()
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
        ("id", "Bahasa"),
        ("th", "ไทย"),
        ("vi", "Tiếng Việt"),
        ("ar", "العربية"),
        ("hi", "हिन्दी") 
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
