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
    
    // Get the default language for translation menu
    private func getDefaultLanguage() -> String {
        // Use persistent preferred language from ConfigManager
        let preferredLanguage = ConfigManager.shared.getUserPreferredLanguage()
        Logger.debug("Using preferred/system language: \(preferredLanguage)")

        // Return the preferred language directly - if it's not in the menu, it will be added dynamically
        return preferredLanguage
    }

    // Update user's language selection (persistent)
    private func updateUserLanguageSelection(_ language: String) {
        // Save to persistent cache using ConfigManager
        let success = ConfigManager.shared.setPreferredLanguage(language)
        if success {
            Logger.debug("Updated user preferred language persistently: \(language)")
        } else {
            Logger.warn("Failed to save preferred language: \(language)")
        }
    }
    
    // Get language name from language code using ConfigManager
    private func getLanguageNativeName(for code: String) -> String {
        let languageConfigs = ConfigManager.shared.loadLanguageConfigs()
        if let config = languageConfigs.first(where: { $0.code == code }) {
            return config.nativeName
        }
        
        // For unknown languages, use the code itself capitalized
        Logger.debug("Language code '\(code)' not found in configurations, using uppercase code")
        return code.uppercased()
    }
    
    // Get dynamic language list with default languages + user preferred language if not in default list
    private func getLanguages() -> [(String, String)] {
        // Default language list (keep original popular languages)
        let defaultLanguages = [
            ("en", "English"),
            ("zh", "简体中文"),
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
        
        let defaultLanguage = getDefaultLanguage()
        
        // Check if the default language is already in the default list
        if defaultLanguages.contains(where: { $0.0 == defaultLanguage }) {
            return defaultLanguages
        }
        
        // If not, get the language name from ConfigManager and add it to the beginning
        let defaultLanguageName = getLanguageNativeName(for: defaultLanguage)
        var languages = [(defaultLanguage, defaultLanguageName)]
        languages.append(contentsOf: defaultLanguages)
        
        Logger.debug("Added preferred language '\(defaultLanguage)' (\(defaultLanguageName)) to language menu")
        return languages
    }
    
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
            defaultLanguage: getDefaultLanguage(),
            languages: getLanguages(),
            onTranslate: { [weak self] language in
                self?.translateToLanguage(language)
            },
            onLanguageSelected: { [weak self] language in
                self?.updateUserLanguageSelection(language)
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
        
        // 直接使用前台应用的 PID，避免从系统级元素获取 PID 失败
        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            self.sourceElementPid = frontmostApp.processIdentifier
            Logger.debug("Using frontmost app PID: \(frontmostApp.processIdentifier) for \(frontmostApp.localizedName ?? "unknown")")
        } else {
            self.sourceElementPid = 0
            Logger.warn("No frontmost application found")
        }
        
        // Refresh the content with updated default language before showing
        setupContent()
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
                            // Use smart error handling to show friendly reminders
                            ErrorNotificationManager.shared.showErrorNotification(error)
                            
                            // Update status window simultaneously
                            switch error {
                            case .networkError:
                                TranslationStatusWindow.shared.showNetworkError(near: self?.lastMousePosition ?? CGPoint.zero)
                            case .serverError:
                                TranslationStatusWindow.shared.showServerError(near: self?.lastMousePosition ?? CGPoint.zero)
                            default:
                                TranslationStatusWindow.shared.showFailure()
                            }
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
        // 使用 InputManager 的事件标记机制
        InputManager.shared.beginSimulatedEvent()
        defer { InputManager.shared.endSimulatedEvent() }
        
        for char in text.unicodeScalars {
            if let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) {
                var unichar = UniChar(char.value)
                event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
                
                // 标记为模拟事件
                event.flags.insert(InputManager.shared.getSimulatedEventFlag())
                event.post(tap: .cghidEventTap)
                
                if let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
                     keyUpEvent.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
                     
                     // 标记为模拟事件
                     keyUpEvent.flags.insert(InputManager.shared.getSimulatedEventFlag())
                     keyUpEvent.post(tap: .cghidEventTap)
                }
            }
        }
        Logger.info("Typed text: '\(text)' (simulated)")
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
    let defaultLanguage: String
    let languages: [(String, String)]
    let onTranslate: (String) -> Void
    let onLanguageSelected: (String) -> Void
    let onClose: () -> Void
    
    @State private var selectedLanguage: String
    @State private var isDropdownOpen: Bool = false
    
    init(defaultLanguage: String, languages: [(String, String)], onTranslate: @escaping (String) -> Void, onLanguageSelected: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        self.defaultLanguage = defaultLanguage
        self.languages = languages
        self.onTranslate = onTranslate
        self.onLanguageSelected = onLanguageSelected
        self.onClose = onClose
        self._selectedLanguage = State(initialValue: defaultLanguage)
    }
    

    
    @State private var isTranslateHovered: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            // "Translate to" 标签 - 可点击，带动态效果
            Button(action: {
                // 直接使用当前选中的语言进行翻译
                onTranslate(selectedLanguage)
            }) {
                Text("Translate To")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isTranslateHovered ? .accentColor : .primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isTranslateHovered ? 
                                  Color.accentColor.opacity(0.1) : 
                                  Color.clear)
                            .animation(.easeInOut(duration: 0.15), value: isTranslateHovered)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { isHovered in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isTranslateHovered = isHovered
                }
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
                        // Notify parent about user's language selection
                        onLanguageSelected(code)
                        // 延迟执行翻译，确保菜单有时间关闭
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            onTranslate(code)
                        }
                    }) {
                        HStack {
                            Text(name)
                                .font(.system(size: 13))
                            if code == selectedLanguage {
                                Spacer()
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                                    .font(.system(size: 12, weight: .semibold))
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
                    .fixedSize(horizontal: true, vertical: false)  // 让文本自动调整宽度
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
        .fixedSize()  // 让整个菜单根据内容自动调整大小
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
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
