import Cocoa
import Carbon

class InputMonitor {
    private var eventTap: CFMachPort?
    private let triggerPattern = #"(.*?)[@#](id|en|zh|ja|jp|ko|fr|de|es|ru|th)\s*$"#
    private let regex: NSRegularExpression

    init() {
        regex = try! NSRegularExpression(pattern: triggerPattern, options: .caseInsensitive)
    }

    func startMonitoringAndReturnEventTap() -> CFMachPort? {
        print("[LOG] InputMonitor startMonitoring called")
        
        // Check accessibility permissions first
        if !checkAccessibilityPermissions() {
            print("[LOG] Accessibility permissions not granted")
            requestAccessibilityPermissions()
            return nil
        }
        
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                if type == .keyDown {
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    
                    if keyCode == kVK_Space { // 空格键
                        DispatchQueue.main.async {
                            InputMonitor.shared.handleSpaceKey()
                        }
                    } else if keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter { // 回车键
                        // 检查是否需要翻译，如果需要则阻止回车事件
                        if InputMonitor.shared.shouldInterceptEnter() {
                            print("[LOG] Intercepting Enter key for translation")
                            DispatchQueue.main.async {
                                InputMonitor.shared.handleInterceptedEnter()
                            }
                            return nil // 阻止回车事件
                        }
                    } else if keyCode == kVK_Tab { // Tab键
                        DispatchQueue.main.async {
                            InputMonitor.shared.handleTabKey()
                        }
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        )
        
        if eventTap == nil {
            print("[LOG] Failed to create event tap - this usually indicates:")
            print("[LOG] 1. Accessibility permissions not granted")
            print("[LOG] 2. App Sandbox restrictions")
            print("[LOG] 3. System security settings blocking access")
        }
        
        return eventTap
    }
    
    private func checkAccessibilityPermissions() -> Bool {
        let trusted = AXIsProcessTrusted()
        print("[LOG] Accessibility permission check result: \(trusted)")
        
        if !trusted {
            // 获取当前应用的Bundle ID和路径以便调试
            if let bundleId = Bundle.main.bundleIdentifier {
                print("[LOG] Current Bundle ID: \(bundleId)")
            }
            let bundlePath = Bundle.main.bundlePath
            print("[LOG] Current Bundle Path: \(bundlePath)")
        }
        
        return trusted
    }
    
    private func requestAccessibilityPermissions() {
        print("[LOG] Requesting accessibility permissions...")
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let result = AXIsProcessTrustedWithOptions(options as CFDictionary)
        print("[LOG] Permission request result: \(result)")
    }

    static let shared = InputMonitor()

    func handleSpaceKey() {
        print("[LOG] Space key detected")
        
        // 首先尝试标准检测
        if let result = AXController.shared.detectTriggerAndExtract() {
            print("[LOG] Trigger detected: text=\(result.text), lang=\(result.lang)")
            startTranslation(text: result.text, lang: result.lang)
            return
        }
        
        // 如果标准检测失败，等待一小段时间后重试（处理Discord等应用的延迟更新）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let result = AXController.shared.detectTriggerAndExtract() {
                print("[LOG] Delayed trigger detected: text=\(result.text), lang=\(result.lang)")
                self.startTranslation(text: result.text, lang: result.lang)
            } else {
                print("[LOG] No trigger detected in input")
            }
        }
    }
    
    private func startTranslation(text: String, lang: String) {
        // 标记自动翻译开始，用于后续过滤
        AXController.shared.markAutoTranslationStart(withText: text)
        
        // 获取当前焦点元素用于定位状态窗口
        let focusedElement = AXController.shared.getFocusedElement()
        
        // 显示翻译中状态
        TranslationStatusWindow.shared.showTranslating(near: focusedElement)
        
        // 开始翻译（不禁用输入，避免死锁）
        TranslatorClient.shared.translate(text: text, to: lang) { [weak self] translated in
            DispatchQueue.main.async {
                if let translated = translated {
                    print("[LOG] Translation result: \(translated)")
                    // 显示成功状态
                    TranslationStatusWindow.shared.showSuccess()
                    // 回填翻译结果
                    AXController.shared.replaceInput(with: translated)
                } else {
                    print("[LOG] Translation failed")
                    // 显示失败状态
                    TranslationStatusWindow.shared.showFailure()
                }
            }
        }
    }

    func handleEnterKey() {
        print("[LOG] Enter key detected (non-intercepted)")
        // 非拦截的Enter键处理，用于某些特殊情况
        attemptTriggerDetection(source: "Enter")
    }
    
    func handleTabKey() {
        print("[LOG] Tab key detected")
        // Tab键可能在某些应用中完成自动补全，然后触发翻译
        attemptTriggerDetection(source: "Tab")
    }
    
    private func attemptTriggerDetection(source: String) {
        if let result = AXController.shared.detectTriggerAndExtract() {
            print("[LOG] Trigger detected via \(source): text=\(result.text), lang=\(result.lang)")
            startTranslation(text: result.text, lang: result.lang)
        } else {
            // 对于Enter和Tab键，我们给更多时间让应用更新内容
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if let result = AXController.shared.detectTriggerAndExtract() {
                    print("[LOG] Delayed trigger detected via \(source): text=\(result.text), lang=\(result.lang)")
                    self.startTranslation(text: result.text, lang: result.lang)
                }
            }
        }
    }

    // 检查是否应该拦截回车键进行翻译
    func shouldInterceptEnter() -> Bool {
        // 快速检查当前输入内容是否包含触发器
        guard let focused = AXController.shared.getFocusedElement(),
              let value = AXController.shared.getValue(of: focused) else {
            return false
        }
        
        // 简单检查是否包含语言代码
        let supportedLangs = ["id", "en", "zh", "ja", "jp", "ko", "fr", "de", "es", "ru", "th"]
        let content = value.lowercased()
        
        for lang in supportedLangs {
            if content.contains(" \(lang) ") || content.hasSuffix(" \(lang)") || 
               content.contains("@\(lang)") || content.contains("#\(lang)") {
                return true
            }
        }
        
        return false
    }
    
    // 处理被拦截的回车键
    func handleInterceptedEnter() {
        print("[LOG] Handling intercepted Enter key")
        
        if let result = AXController.shared.detectTriggerAndExtract() {
            print("[LOG] Trigger detected via intercepted Enter: text=\(result.text), lang=\(result.lang)")
            
            // 开始翻译，完成后自动发送
            startTranslationWithAutoSend(text: result.text, lang: result.lang)
        } else {
            print("[LOG] No trigger found, sending original Enter key")
            // 如果没有检测到触发器，发送原始回车键
            sendEnterKey()
        }
    }
    
    // 翻译完成后自动发送
    private func startTranslationWithAutoSend(text: String, lang: String) {
        // 标记自动翻译开始，用于后续过滤
        AXController.shared.markAutoTranslationStart(withText: text)
        
        // 获取当前焦点元素用于定位状态窗口
        let focusedElement = AXController.shared.getFocusedElement()
        
        // 显示翻译中状态
        TranslationStatusWindow.shared.showTranslating(near: focusedElement)
        
        // 开始翻译（不禁用输入，避免死锁）
        TranslatorClient.shared.translate(text: text, to: lang) { [weak self] translated in
            DispatchQueue.main.async {
                if let translated = translated {
                    print("[LOG] Translation result: \(translated)")
                    // 显示成功状态
                    TranslationStatusWindow.shared.showSuccess()
                    // 回填翻译结果
                    AXController.shared.replaceInput(with: translated)
                    
                    // 等待一小段时间确保内容更新，然后发送回车键
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self?.sendEnterKey()
                    }
                } else {
                    print("[LOG] Translation failed")
                    // 显示失败状态
                    TranslationStatusWindow.shared.showFailure()
                    // 翻译失败时发送原始内容
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self?.sendEnterKey()
                    }
                }
            }
        }
    }
    
    // 发送回车键事件
    private func sendEnterKey() {
        print("[LOG] Sending Enter key event")
        
        let source = CGEventSource(stateID: .hidSystemState)
        if let enterKeyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: true),
           let enterKeyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: false) {
            
            enterKeyDown.post(tap: .cghidEventTap)
            enterKeyUp.post(tap: .cghidEventTap)
        }
    }
} 