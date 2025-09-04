//
//  SelectEventManager.swift
//  Manages mouse event monitoring and selection detection.
//  Created by Claude Code on 2025-07-21.
//  Copyright © 2025 Glotera AI. All rights reserved.
//
import Cocoa

class SelectEventManager {
    static let shared = SelectEventManager()
    
    // 选中文本监听相关变量
    private var isSelectionMonitoringPaused = false
     
    private var lastSelectedText: String = ""
    private var lastSelectionCheckTime: Date = Date()
    private var isMenuShowing: Bool = false
    private var isMouseDragging: Bool = false
    private var lastMouseUpTime: Date = Date.distantPast
    private var mouseEventMonitor: Any?
    private var keyboardEventMonitor: Any?
    private var lastDoubleClickTime: Date = Date.distantPast
    private var doubleClickCheckScheduled: Bool = false
    private var lastDoubleClickHandledTime: Date = Date.distantPast // 新增：上次处理双击的时间
    private let doubleClickIgnoreInterval: TimeInterval = 1.0 // 1秒内忽略后续双击
    private var clickCount: Int = 0
    private var firstClickTime: Date = Date.distantPast
    private var doubleClickWindow: TimeInterval = 0.5 // 双击时间窗口
    private var lastCtrlATime: Date = Date.distantPast
    
    // 鼠标拖拽检测相关变量
    private var mouseDownLocation: NSPoint = NSPoint.zero
    private let dragThreshold: CGFloat = 10.0 // 10像素的移动阈值
    private var isMouseDownOnTextElement: Bool = false // 标记鼠标是否在文本元素上按下 
    
    // 用于跟踪最近的自动翻译操作
    private var lastAutoTranslationTime: Date = Date.distantPast
    private var lastAutoTranslationText: String = ""
    
    // WhatsApp 特殊处理
    private var isWhatsAppMessageSelected: Bool = false
    private var whatsAppMessageShowTime: Date = Date.distantPast
    private var lastWhatsAppSelectedText: String = ""
    
    // WeChat 特殊处理
    private var isWeChatMessageSelected: Bool = false
    private var weChatMessageShowTime: Date = Date.distantPast
    private var lastWeChatSelectedText: String = ""
    
    // WeChat 历史消息标记（用于区分历史消息和输入框）
    private var wechatHistoryMessageElements: Set<Int> = []
    
    // 焦点元素缓存，减少频繁的 Accessibility API 调用
    private var cachedFocusedElement: AXUIElement?
    private var lastFocusedElementTime: Date = Date.distantPast
    private let focusElementCacheTTL: TimeInterval = 1.0 // 1秒缓存时间

    private init() {
        // 监听应用切换，清除焦点元素缓存
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidActivate),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }
    
    // Application switching observer
    @objc private func applicationDidActivate(_ notification: Notification) {
        // Clear focused element cache when user switches applications
        clearFocusedElementCache()
        Logger.debug("Application switched - focused element cache cleared")
    }
    
    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // 获取缓存的焦点元素，减少频繁的 Accessibility API 调用
    private func getCachedFocusedElement() -> AXUIElement? {
        let now = Date()
        
        // 检查缓存是否有效
        if let cached = cachedFocusedElement,
           now.timeIntervalSince(lastFocusedElementTime) < focusElementCacheTTL {
            return cached
        }
        
        // 缓存过期或不存在，重新获取
        if let focused = InputManager.shared.getFocusedElementWithRetry(maxRetries: 3) {
            cachedFocusedElement = focused
            lastFocusedElementTime = now
            return focused
        }
        
        // 获取失败，清除缓存
        cachedFocusedElement = nil
        return nil
    }
    
    // 清除焦点元素缓存（当应用切换时调用）
    private func clearFocusedElementCache() {
        cachedFocusedElement = nil
        lastFocusedElementTime = Date.distantPast
    }

        // 开始监听选中文本变化
    func startSelectionMonitoring() {
        Logger.info("Starting selection monitoring (keyboard-event-safe)")
        
        // Initialize trigger pattern cache for optimized trigger detection
        TriggerManager.shared.refreshCaches()
        
        // 延迟启动鼠标监听，确保键盘监听优先建立
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.startMouseEventMonitoring()
        }
        
        // 移除定时器，改为纯事件驱动的方式
        // 菜单的隐藏将通过事件监听和菜单关闭回调来处理
    }

     // 监听鼠标事件
    private func startMouseEventMonitoring() {
        // 监听鼠标事件，包括双击
        mouseEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged]) { [weak self] event in
            DispatchQueue.main.async {
                self?.handleMouseEvent(event)
            }
        } 
        
        Logger.info("Mouse event monitoring started (keyboard monitoring delegated to InputMonitor)")
    }
    
    private func handleMouseEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            // 菜单的隐藏由 TranslationMenuWindow 自己的事件监听器处理
            // 这里不需要额外的处理
            
            // 记录鼠标按下位置
            mouseDownLocation = event.locationInWindow
            
            // 检测鼠标按下位置下的元素是否为文本元素
            isMouseDownOnTextElement = isMouseOverTextElement(at: event.locationInWindow)
            Logger.debug("Mouse down on text element: \(isMouseDownOnTextElement)")
            
            // 简化版双击容错检测
            let now = Date()
            let timeSinceLastHandled = now.timeIntervalSince(lastDoubleClickHandledTime)
            let timeSinceLastClick = now.timeIntervalSince(lastDoubleClickTime)
            
            if timeSinceLastClick < 0.5 && timeSinceLastClick > 0.1 {
                // 检查3秒内是否已处理过双击
                if timeSinceLastHandled < doubleClickIgnoreInterval {
                    Logger.info("Double click ignored (within 1s interval)")
                } else {
                    Logger.info("===========================================")
                    Logger.info("Double click detected and handled")
                    lastDoubleClickHandledTime = now
                    lastDoubleClickTime = now
                    if !doubleClickCheckScheduled {
                        doubleClickCheckScheduled = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self.checkForTextSelectionAfterDoubleClick()
                            self.doubleClickCheckScheduled = false
                        }
                    }
                }
            } else {
                lastDoubleClickTime = now
            }
            
            // 重置拖拽状态
            isMouseDragging = false
            
        case .leftMouseDragged:
            // 只有在文本元素上的拖拽才被认为是文本选择
            guard isMouseDownOnTextElement else {
                Logger.debug("Mouse dragged but not on text element, ignoring")
                return
            }
            
            // 计算鼠标移动距离
            let currentLocation = event.locationInWindow
            let distance = sqrt(pow(currentLocation.x - mouseDownLocation.x, 2) + pow(currentLocation.y - mouseDownLocation.y, 2))
            
            // 只有当移动距离超过阈值时才认为是真正的拖拽
            if distance > dragThreshold {
                if !isMouseDragging {
                    isMouseDragging = true
                    Logger.info("set isMouseDragging true (distance: \(String(format: "%.1f", distance))px) on text element")
                }
            } else {
                Logger.debug("Mouse moved but below threshold: \(String(format: "%.1f", distance))px < \(dragThreshold)px")
            }
            
        case .leftMouseUp:
            // 鼠标释放
            if isMouseDragging {
                lastMouseUpTime = Date()
                // 延迟检查，给文本选择时间稳定
                Logger.info("===========================================")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.checkForTextSelectionAfterMouseUp()
                }
            }
            isMouseDragging = false
            
        default:
            break
        }
    }
    
    // 重置菜单状态 - 现在由 TranslationMenuWindow 的 onMenuClosed 回调处理
    // 这个方法保留以备将来使用
    private func resetMenuState() {
        lastSelectedText = ""
        isMenuShowing = false
        isWhatsAppMessageSelected = false
        lastWhatsAppSelectedText = ""
        isWeChatMessageSelected = false
        lastWeChatSelectedText = ""
    }

    
    // 鼠标释放后的专门检查
    private func checkForTextSelectionAfterMouseUp() { 
        Logger.info("Checking text selection after mouse up")
        
        // 等待一个更长的延迟，确保选择完全稳定
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // 只有在鼠标拖拽选择后才显示菜单
            self.checkSelectedTextAndShowMenu(selectionType: "mouse")
        }
    }
    
    // 双击后的文本选择检查
    private func checkForTextSelectionAfterDoubleClick() { 
        Logger.info("Checking text selection after double click")
        
        // 等待延迟，确保双击选择完全稳定
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.checkSelectedTextAndShowMenu(selectionType: "mouse")
        }
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
            // If accessibility fails, try async clipboard method
            Logger.info("Accessibility failed, trying async clipboard method")
            tryClipboardSelectionAsync(selectionType: selectionType, startTime: startTime)
            return
        }

        if selection.text == "false_trigger" {
            Logger.info("false selection trigger, finish!")
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
        
        if trimmedForCheck.count < 1 {
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
            
            Logger.debug("Selected text after \(selectionType) selection: '\(originalText)' (length: \(originalText.count))")
            Logger.debug("WhatsApp message selected flag: \(isWhatsAppMessageSelected)")
            Logger.debug("WeChat message selected flag: \(isWeChatMessageSelected)")
            
            // ⭐️ 关键：在弹出翻译菜单之前记录应用信息，这时应用还在前台
            EnvironmentManager.shared.recordTriggerApp()
            
            // 标记选中文本翻译开始，通知 InputMonitor
            InputMonitor.shared.markSelectionTranslationStart()
            
            // 获取选中文本的位置和应用信息
            let mouseLocation = NSEvent.mouseLocation
            let appInfo = AppDetectionManager.shared.getAppInfo(for: selection.element)
            
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
                    self?.isWhatsAppMessageSelected = false
                    self?.lastWhatsAppSelectedText = ""
                    self?.isWeChatMessageSelected = false
                    self?.lastWeChatSelectedText = ""
                Logger.debug("Menu closed callback triggered - Special App flag reset")
                }
        }
    }

      

    // 获取当前选中的文本 - 智能缓存版本，改进重试逻辑
    func getSelectedText(checkSpecialApps: Bool = true) -> (text: String, element: AXUIElement)? {
        let appManager = AppDetectionManager.shared
        
        // For known problematic apps, skip accessibility and use clipboard method
        if appManager.shouldUseClipboardDirectly() {
            Logger.info("Using clipboard selection for known accessibility-failed app")
            // Return nil to trigger async clipboard method
            return nil
        }
        
        // Try accessibility first with improved retry logic
        var focused: AXUIElement?
        
        // Retry accessibility API up to 2 times with short delays
        for attempt in 0..<2 {
            focused = getCachedFocusedElement()
            if focused != nil {
                break
            }
            
            if attempt < 1 { // Only sleep on first attempt
                Logger.debug("Accessibility failed on attempt \(attempt + 1), retrying...")
                Thread.sleep(forTimeInterval: 0.05) // Brief 50ms delay
            }
        }
        
        guard let focusedElement = focused else {
            Logger.info("No focused element via accessibility after retries, will try clipboard as fallback")
            // Return nil to trigger async clipboard method
            return nil
        }

        // 先处理特殊应用
        if checkSpecialApps {
            // 对于Wechat、Whatsapp特殊应用，首先使用标准方式获取，因为用户有可能选中的是输入框，而不是历史消息内容
            if let selectedText = getSelectedTextAttribute(of: focusedElement) {
                if !selectedText.isEmpty {
                    Logger.debug("Returning selected text from AX API for special apps")
                    return (text: selectedText, element: focusedElement)
                }  
            } 

            // 特殊处理：WhatsApp 聊天历史 - 使用鼠标位置定位正确的消息
            if let whatsappResult = getWhatsAppChatHistoryTextWithMousePosition() { 
                // 标记这是 WhatsApp 消息选择
                isWhatsAppMessageSelected = true
                whatsAppMessageShowTime = Date()
                lastWhatsAppSelectedText = whatsappResult.text
                Logger.info("WhatsApp message selected - protection activated for 2.5 seconds")
                // 重要：返回实际的消息元素，不是焦点元素
                return (text: whatsappResult.text, element: whatsappResult.element)
            }
            
            // 特殊处理：WeChat 聊天历史 - 使用鼠标位置定位正确的消息
            if let wechatResult = getWeChatHistoryTextWithMousePosition() {
                // 标记这是 WeChat 消息选择
                isWeChatMessageSelected = true
                weChatMessageShowTime = Date()
                lastWeChatSelectedText = wechatResult.text
                Logger.info("WeChat message selected - protection activated for 2.5 seconds")
                // 重要：为了确保显示浮动翻译窗口而不是粘贴到输入框，
                // 我们需要标记这个元素为WeChat历史消息
                markElementAsWeChatHistoryMessage(wechatResult.element)
                return (text: wechatResult.text, element: wechatResult.element)
            }
        }
        
        // 再尝试通过AX API标准方法获取选中文本
        if let selectedText = getSelectedTextAttribute(of: focusedElement) {
            Logger.debug("getSelectedTextAttribute returned: '\(selectedText)' (length: \(selectedText.count), isEmpty: \(selectedText.isEmpty))")
            if !selectedText.isEmpty {
                Logger.debug("Returning selected text from AX API")
                return (text: selectedText, element: focusedElement)
            } else {
                Logger.debug("Selected text is empty, false trigger, finish!")
                return (text: "false_trigger", element: focusedElement)
            }
        } else {
            Logger.debug("getSelectedTextAttribute returned nil")
        }
        
        // 如果在浏览器环境中，尝试通过JavaScript获取选中文本
        if AppDetectionManager.shared.isWebEnvironment() {
            if let selectedText = AppleScriptManager.shared.getWebSelectedText(), !selectedText.isEmpty {
                Logger.info("Got selected text via Web: '\(selectedText)'")
                return (text: selectedText, element: focusedElement)
            }
        }
        

        
        // If all accessibility methods fail, record failure and try clipboard
        // Logger.warn("All accessibility methods failed, using clipboard fallback")
        // appManager.recordAccessibilityFailure()
        // Return nil to trigger async clipboard method
        return nil
    }
    
    
    // Async clipboard selection method for force clipboard mode - improved version
    private func tryClipboardSelectionAsync(selectionType: String, startTime: Date) {
        let pasteboard = NSPasteboard.general
        
        // Store original clipboard content and change count for integrity check
        let originalContent = pasteboard.string(forType: .string)
        let originalChangeCount = pasteboard.changeCount
        
        // Add delay before clipboard manipulation to avoid interfering with user operations
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            
            // Check if user has performed clipboard operations in the meantime
            if pasteboard.changeCount != originalChangeCount {
                Logger.info("Clipboard changed during delay, skipping automated selection")
                return
            }
            
            // Clear and copy current selection with safer approach
            let preClipboardChangeCount = pasteboard.changeCount
            pasteboard.clearContents()
            
            // Use a more reliable copy command
            InputManager.shared.postCopy()
            
            // Use progressive delay checking to ensure copy operation completes
            self.waitForClipboardChange(
                originalChangeCount: preClipboardChangeCount + 1, // +1 for clearContents
                originalContent: originalContent,
                selectionType: selectionType,
                startTime: startTime,
                attempts: 0
            )
        }
    }
    
    // Progressive clipboard change detection to avoid timing issues
    private func waitForClipboardChange(
        originalChangeCount: Int,
        originalContent: String?,
        selectionType: String,
        startTime: Date,
        attempts: Int
    ) {
        let pasteboard = NSPasteboard.general
        let maxAttempts = 5
        let baseDelay = 0.05 // Start with 50ms
        
        // Check if clipboard has changed (indicating copy completed)
        if pasteboard.changeCount > originalChangeCount {
            // Copy operation completed, process the result
            self.processClipboardSelection(
                originalContent: originalContent,
                selectionType: selectionType,
                startTime: startTime
            )
            return
        }
        
        // If we've reached max attempts, give up
        guard attempts < maxAttempts else {
            Logger.info("Clipboard selection timeout after \(maxAttempts) attempts")
            self.restoreClipboardAndCleanup(originalContent: originalContent)
            return
        }
        
        // Progressive delay: 50ms, 100ms, 150ms, 200ms, 250ms
        let delay = baseDelay * Double(attempts + 1)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.waitForClipboardChange(
                originalChangeCount: originalChangeCount,
                originalContent: originalContent,
                selectionType: selectionType,
                startTime: startTime,
                attempts: attempts + 1
            )
        }
    }
    
    // Process clipboard selection result
    private func processClipboardSelection(
        originalContent: String?,
        selectionType: String,
        startTime: Date
    ) {
        let pasteboard = NSPasteboard.general
        
        guard let selectedText = pasteboard.string(forType: .string),
              !selectedText.isEmpty,
              selectedText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 1 else {
            
            Logger.info("No valid selection found in clipboard")
            self.restoreClipboardAndCleanup(originalContent: originalContent)
            return
        }
        
        // Verify this isn't the original clipboard content being restored
        if let original = originalContent, selectedText == original {
            Logger.info("Clipboard selection matches original content, likely no selection")
            self.restoreClipboardAndCleanup(originalContent: originalContent)
            return
        }
        
        // Restore original clipboard immediately to minimize interference
        self.restoreClipboardAndCleanup(originalContent: originalContent)
        
        // Process the selected text
        let processingTime = Date().timeIntervalSince(startTime)
        if processingTime > 0.3 {
            Logger.warn("Clipboard selection took \(String(format: "%.3f", processingTime))s - performance warning")
        }
        
        self.processSelectedText(selectedText, selectionType: selectionType, startTime: startTime)
    }
    
    // Restore clipboard and cleanup state
    private func restoreClipboardAndCleanup(originalContent: String?) {
        let pasteboard = NSPasteboard.general
        
        // Restore original clipboard content if it existed
        if let originalContent = originalContent {
            pasteboard.clearContents()
            pasteboard.setString(originalContent, forType: .string)
            Logger.debug("Restored original clipboard content")
        }
        
        // Hide menu if no selection found
        if !self.lastSelectedText.isEmpty {
            Logger.info("Hiding menu - no clipboard selection found")
            TranslationMenuWindow.shared.hide()
            self.lastSelectedText = ""
            self.isMenuShowing = false
            self.isWhatsAppMessageSelected = false
            self.isWeChatMessageSelected = false
            self.lastWhatsAppSelectedText = ""
        }
    }
    
    // Process selected text and show menu
    private func processSelectedText(_ text: String, selectionType: String, startTime: Date) {
        let processingTime = Date().timeIntervalSince(startTime)
        if processingTime > 0.2 {
            Logger.debug("checkSelectedTextAndShowMenu (\(selectionType)) took \(String(format: "%.3f", processingTime))s - performance warning")
        }
        
        // Check if this is likely a translation result
        if isLikelyTranslationResult(text) {
            Logger.info("Skipping menu for likely translation result: '\(text)'")
            return
        }
        
        // Filter out too short text, but keep original format
        let originalText = text
        let trimmedForCheck = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedForCheck.count < 1 {
            if !lastSelectedText.isEmpty {
                TranslationMenuWindow.shared.hide()
                lastSelectedText = ""
                isMenuShowing = false
            }
            return
        }
        
        // Use original text (preserving whitespace) for comparison and passing
        if originalText != lastSelectedText {
            lastSelectedText = originalText
            isMenuShowing = true
            
            Logger.debug("Selected text after \(selectionType) selection: '\(originalText)' (length: \(originalText.count))")
            
            // ⭐️ Key: Record app info before showing translation menu
            EnvironmentManager.shared.recordTriggerApp()
            
            // Mark selection translation start
            InputMonitor.shared.markSelectionTranslationStart()
            
            // Get selection position and app info
            let mouseLocation = NSEvent.mouseLocation
            
            // 使用前台应用信息而不是系统级元素
            let frontmostApp = NSWorkspace.shared.frontmostApplication
            let appInfo = AppDetectionManager.shared.getAppInfo(for: frontmostApp?.processIdentifier ?? 0)
            
            // Show translation menu
            TranslationMenuWindow.shared.show(
                for: originalText,
                from: AXUIElementCreateSystemWide(), // 仍然传递系统级元素，但不会用于获取PID
                at: mouseLocation,
                browserInfo: appInfo.isBrowser ? appInfo : nil
            )
            
            // Set close callback
            TranslationMenuWindow.shared.onMenuClosed = { [weak self] in
                self?.isMenuShowing = false
                self?.lastSelectedText = ""
                self?.isWhatsAppMessageSelected = false
                self?.lastWhatsAppSelectedText = ""
                self?.isWeChatMessageSelected = false
                self?.lastWeChatSelectedText = ""
                Logger.debug("Menu closed callback triggered - flags reset")
            }
        }
    }
    
    // 获取 WhatsApp 聊天历史文本
    private func getWhatsAppChatHistoryText(from element: AXUIElement) -> String? {
        // 检查是否为 WhatsApp 应用
        guard AppDetectionManager.shared.isWhatsAppApp() else {
            //Logger.info("Not WhatsApp app")
            return nil
        }
        
        // 检查元素角色
        var role: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        guard roleResult == .success, let roleString = role as? String else {
            Logger.info("Failed to get element role")
            return nil
        }
        
        Logger.info("Found WhatsApp element with role: \(roleString)")
        
        // 处理 AXGenericElement（直接包含消息内容）
        if roleString == "AXGenericElement" {
            return getMessageFromGenericElement(element)
        }
        
        // 处理 AXGroup（包含子元素，需要查找消息）
        if roleString == "AXGroup" {
            return getMessageFromGroupElement(element)
        }
        
        Logger.info("Element role not supported: \(roleString)")
        return nil
    }
    
    // 从 AXGenericElement 获取消息
    private func getMessageFromGenericElement(_ element: AXUIElement) -> String? {
        Logger.info("Getting message from AXGenericElement...")
        
        // 首先尝试从 Label 属性获取（Inspector 显示这里包含消息内容）
        var label: CFTypeRef?
        let labelResult = AXUIElementCopyAttributeValue(element, "AXLabel" as CFString, &label)
        
        if labelResult == .success, let labelString = label as? String, !labelString.isEmpty {
            Logger.info("AXGenericElement Label: '\(labelString)'")
            
            // 检查是否包含 WhatsApp 消息的特征
            if labelString.contains(",") && (labelString.contains("message") || labelString.contains("Your message")) {
                Logger.info("Found WhatsApp message in Label attribute")
                if let chatMessage = ContentProcessor.shared.parseWhatsAppMessage(labelString) {
                    return chatMessage.content
                }
            }
        } else {
            Logger.info("AXGenericElement Label: empty or failed (result: \(labelResult))")
        }
        
        // 如果 Label 没有内容，尝试其他属性
        let attributesToTry: [(CFString, String)] = [
            (kAXValueAttribute as CFString, "Value"),
            (kAXDescriptionAttribute as CFString, "Description"),
            (kAXTitleAttribute as CFString, "Title"),
            (kAXHelpAttribute as CFString, "Help"),
            (kAXSelectedTextAttribute as CFString, "SelectedText")
        ]
        
        for (attribute, attributeName) in attributesToTry {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, attribute, &value)
            
            if result == .success, let stringValue = value as? String, !stringValue.isEmpty {
                Logger.info("AXGenericElement \(attributeName): '\(stringValue)'")
                
                if let chatMessage = ContentProcessor.shared.parseWhatsAppMessage(stringValue) {
                    Logger.info("Successfully parsed WhatsApp message from \(attributeName): '\(chatMessage.content)'")
                    return chatMessage.content
                }
            }
        }
        
        return nil
    }
    
    // 从 AXGroup 获取消息
    private func getMessageFromGroupElement(_ element: AXUIElement) -> String? {
        Logger.info("Getting message from AXGroup...")
        
        // 获取子元素
        var children: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        
        if childrenResult == .success, let childrenArray = children {
            // 首先尝试从当前元素本身获取消息（可能是直接选中的元素）
            if let message = getMessageFromElementDirectly(element) {
                Logger.info("Found message directly from current element: '\(message)'")
                return message
            }
            
            // 将CFTypeRef转换为NSArray，然后遍历
            if let nsArray = childrenArray as? NSArray {
                Logger.info("Found \(nsArray.count) child elements in AXGroup")
                
                for i in 0..<nsArray.count {
                    let child = nsArray[i] as! AXUIElement
                    Logger.info("Checking child element \(i)...")
                    
                    // 检查子元素的角色
                    var childRole: CFTypeRef?
                    let childRoleResult = AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &childRole)
                    if childRoleResult == .success, let childRoleString = childRole as? String {
                        Logger.info("Child \(i) role: \(childRoleString)")
                        
                        // 如果子元素是 AXGenericElement，尝试获取消息
                        if childRoleString == "AXGenericElement" {
                            if let message = getMessageFromGenericElement(child) {
                                Logger.info("Found WhatsApp message in child \(i): '\(message)'")
                                return message
                            }
                        }
                        
                        // 如果子元素是 AXGroup，递归查找
                        if childRoleString == "AXGroup" {
                            if let message = getMessageFromGroupElement(child) {
                                Logger.info("Found WhatsApp message in child \(i) group: '\(message)'")
                                return message
                            }
                        }
                        
                        // 尝试从子元素的其他属性获取文本
                        let attributesToTry: [(CFString, String)] = [
                            ("AXLabel" as CFString, "Label"),
                            (kAXValueAttribute as CFString, "Value"),
                            (kAXDescriptionAttribute as CFString, "Description"),
                            (kAXTitleAttribute as CFString, "Title"),
                            (kAXHelpAttribute as CFString, "Help"),
                            (kAXSelectedTextAttribute as CFString, "SelectedText")
                        ]
                        
                        for (attribute, attributeName) in attributesToTry {
                            var childValue: CFTypeRef?
                            let childResult = AXUIElementCopyAttributeValue(child, attribute, &childValue)
                            
                            if childResult == .success, let childStringValue = childValue as? String, !childStringValue.isEmpty {
                                Logger.info("Child \(i) \(attributeName): '\(childStringValue)'")
                                
                                if let chatMessage = ContentProcessor.shared.parseWhatsAppMessage(childStringValue) {
                                    Logger.info("Successfully parsed WhatsApp message from child \(i) \(attributeName): '\(chatMessage.content)'")
                                    return chatMessage.content
                                }
                            }
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    // 直接从元素获取消息（不遍历子元素）
    private func getMessageFromElementDirectly(_ element: AXUIElement) -> String? {
        Logger.info("Getting message directly from element...")
        
        let attributesToTry: [(CFString, String)] = [
            ("AXLabel" as CFString, "Label"),
            (kAXValueAttribute as CFString, "Value"),
            (kAXDescriptionAttribute as CFString, "Description"),
            (kAXTitleAttribute as CFString, "Title"),
            (kAXHelpAttribute as CFString, "Help"),
            (kAXSelectedTextAttribute as CFString, "SelectedText")
        ]
        
        for (attribute, attributeName) in attributesToTry {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, attribute, &value)
            
            if result == .success, let stringValue = value as? String, !stringValue.isEmpty {
                Logger.info("Element \(attributeName): '\(stringValue)'")
                
                if let chatMessage = ContentProcessor.shared.parseWhatsAppMessage(stringValue) {
                    Logger.info("Successfully parsed WhatsApp message from element \(attributeName): '\(chatMessage.content)'")
                    return chatMessage.content
                }
            }
        }
        
        return nil
    }
    
    // 使用鼠标位置获取 WhatsApp 聊天历史文本和元素
    private func getWhatsAppChatHistoryTextWithMousePosition() -> (text: String, element: AXUIElement)? {
        // 检查是否为 WhatsApp 应用
        guard AppDetectionManager.shared.isWhatsAppApp() else {
            // Logger.info("Not WhatsApp app, skipping mouse position detection")
            return nil
        }
        
        // 获取当前鼠标位置
        let mouseLocation = NSEvent.mouseLocation
        
        // 将屏幕坐标转换为CGPoint（屏幕坐标系原点在左下角）
        let screenFrame = NSScreen.main?.frame ?? NSRect.zero
        let cgPoint = CGPoint(x: mouseLocation.x, y: screenFrame.height - mouseLocation.y)
        
        // 获取系统的 UI 元素访问对象
        var systemWideElement: AXUIElement
        systemWideElement = AXUIElementCreateSystemWide()
        
        // 查找鼠标位置下的元素
        var elementUnderMouse: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWideElement, Float(cgPoint.x), Float(cgPoint.y), &elementUnderMouse)
        
        guard result == .success, let mouseElement = elementUnderMouse else {
            return nil
        }
        
        // 验证该元素是否属于 WhatsApp
        var pid: pid_t = 0
        let pidResult = AXUIElementGetPid(mouseElement, &pid)
        guard pidResult == .success else {
            return nil
        }
        
        // 检查该 PID 是否属于 WhatsApp 进程
        guard let app = NSRunningApplication(processIdentifier: pid),
              let bundleId = app.bundleIdentifier,
              bundleId.lowercased().contains("whatsapp") else {
            return nil
        }
        
        // 尝试从鼠标位置的元素获取消息内容
        if let messageText = getWhatsAppMessageFromElement(mouseElement) {
            Logger.debug("Successfully extracted WhatsApp message from mouse position: '\(messageText)'")
            return (text: messageText, element: mouseElement)
        }
        
        // 如果直接获取失败，尝试遍历父元素
        var currentElement: AXUIElement? = mouseElement
        var depth = 0
        let maxDepth = 3 // 限制遍历深度，防止无限循环
        
        while currentElement != nil && depth < maxDepth {
            if let messageText = getWhatsAppMessageFromElement(currentElement!) {
                Logger.debug("Successfully extracted WhatsApp message from parent element (depth \(depth)): '\(messageText)'")
                return (text: messageText, element: currentElement!)
            }
            
            // 获取父元素
            var parent: CFTypeRef?
            let parentResult = AXUIElementCopyAttributeValue(currentElement!, kAXParentAttribute as CFString, &parent)
            if parentResult == .success, let parentRef = parent {
                let parentElement = parentRef as! AXUIElement
                currentElement = parentElement
                depth += 1
            } else {
                break
            }
        }
        return nil
    }
    
    // 从指定元素获取 WhatsApp 消息内容
    private func getWhatsAppMessageFromElement(_ element: AXUIElement) -> String? {
        // 检查元素角色
        var role: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        guard roleResult == .success, let roleString = role as? String else {
            return nil
        }
        
        // 处理不同类型的元素
        switch roleString {
        case "AXGenericElement":
            return getMessageFromGenericElement(element)
        case "AXGroup":
            return getMessageFromGroupElement(element)
        case "AXStaticText":
            // 对于静态文本，直接尝试获取内容
            return getMessageFromElementDirectly(element)
        case "AXTextArea":
            // 对于输入框文本，直接获取内容
            Logger.info("Whatsapp AXTextArea element, return value directly")
            return AXController.shared.getStandardValue(of: element, isWeb: false)
        default:
            // 对于其他类型，尝试直接获取消息
            Logger.info("Trying direct message extraction for role: \(roleString)")
            return getMessageFromElementDirectly(element)
        }
    }
    


     
    // 获取选中文本属性
    func getSelectedTextAttribute(of element: AXUIElement) -> String? {
        let startTime = Date()
        
        var selectedTextValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextValue)
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        // 性能监控：如果处理时间过长，记录警告
        if processingTime > 0.2 {
            Logger.debug("AXUIElementCopyAttributeValue took \(String(format: "%.3f", processingTime))s - performance warning")
        }
        
        if result == .success, let text = selectedTextValue as? String {
            Logger.info("Get selected text successfully: '\(text)' (length: \(text.count))")
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
    

    
    // MARK: - WeChat Message Detection
    
    // 使用鼠标位置获取 WeChat 聊天历史文本和元素
    private func getWeChatHistoryTextWithMousePosition() -> (text: String, element: AXUIElement)? {
        // 检查是否为 WeChat 应用
        guard AppDetectionManager.shared.isWeChatApp() else {
            //Logger.info("Not WeChat app, skipping mouse position detection")
            return nil
        }
        
        // 获取当前鼠标位置
        let mouseLocation = NSEvent.mouseLocation
        
        // 将屏幕坐标转换为CGPoint（屏幕坐标系原点在左下角）
        let screenFrame = NSScreen.main?.frame ?? NSRect.zero
        let cgPoint = CGPoint(x: mouseLocation.x, y: screenFrame.height - mouseLocation.y)
        
        // 获取系统的 UI 元素访问对象
        var systemWideElement: AXUIElement
        systemWideElement = AXUIElementCreateSystemWide()
        
        // 查找鼠标位置下的元素
        var elementUnderMouse: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWideElement, Float(cgPoint.x), Float(cgPoint.y), &elementUnderMouse)
        
        guard result == .success, let mouseElement = elementUnderMouse else {
            return nil
        }
        
        // 验证该元素是否属于 WeChat
        var pid: pid_t = 0
        let pidResult = AXUIElementGetPid(mouseElement, &pid)
        guard pidResult == .success else {
            return nil
        }
        
        // 检查该 PID 是否属于 WeChat 进程
        guard let app = NSRunningApplication(processIdentifier: pid),
              let bundleId = app.bundleIdentifier,
              bundleId.contains("wechat") || bundleId.contains("WeChat") else {
            if let failedApp = NSRunningApplication(processIdentifier: pid) {
                Logger.info("Element not from WeChat process - bundleId: \(failedApp.bundleIdentifier ?? "nil")")
            } else {
                Logger.info("Element not from WeChat process - failed to get app")
            }
            return nil
        }
          
        // 尝试从鼠标位置的元素获取消息内容
        if let messageText = getWeChatMessageFromElement(mouseElement) { 
            return (text: messageText, element: mouseElement)
        }
        
        // 如果直接获取失败，尝试遍历父元素
        var currentElement: AXUIElement? = mouseElement
        var depth = 0
        let maxDepth = 5 // 限制遍历深度，防止无限循环
        
        while currentElement != nil && depth < maxDepth {
            if let messageText = getWeChatMessageFromElement(currentElement!) { 
                return (text: messageText, element: currentElement!)
            }
            
            // 获取父元素
            var parent: CFTypeRef?
            let parentResult = AXUIElementCopyAttributeValue(currentElement!, kAXParentAttribute as CFString, &parent)
            if parentResult == .success, let parentRef = parent {
                let parentElement = parentRef as! AXUIElement
                currentElement = parentElement
                depth += 1
            } else {
                break
            }
        }
        return nil
    }
    
    // 从指定元素获取 WeChat 消息内容
    private func getWeChatMessageFromElement(_ element: AXUIElement) -> String? {
        // 检查元素角色
        var role: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        guard roleResult == .success, let roleString = role as? String else {
            Logger.info("Failed to get element role")
            return nil
        } 
        
        // WeChat 历史消息通常是 AXStaticText 角色
        if roleString == "AXStaticText" {
            // 根据用户的Inspector发现，WeChat消息内容在Title属性中
            var title: CFTypeRef?
            let titleResult = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
            
            if titleResult == .success, let titleString = title as? String, !titleString.isEmpty {
                Logger.info("WeChat AXStaticText Title: '\(titleString)'")
                
                // 验证这是否是有效的消息内容（过滤掉UI元素标题）
                if isValidWeChatMessage(titleString) { 
                    return titleString
                }
            }
        }
        
        // 如果不是 AXStaticText 或者没有找到内容，尝试其他常见的WeChat消息元素类型
        let supportedRoles = ["AXGroup", "AXGenericElement", "AXTextArea", "AXTextField"]
        if supportedRoles.contains(roleString) {
            return getWeChatMessageFromElementDirectly(element)
        }
        
        return nil
    }
    
    // 直接从元素获取WeChat消息（尝试多个属性）
    private func getWeChatMessageFromElementDirectly(_ element: AXUIElement) -> String? {
        Logger.info("Getting WeChat message directly from element...")
        
        let attributesToTry: [(CFString, String)] = [
            (kAXTitleAttribute as CFString, "Title"),      // WeChat主要使用Title
            (kAXValueAttribute as CFString, "Value"),
            ("AXLabel" as CFString, "Label"),
            (kAXDescriptionAttribute as CFString, "Description"),
            (kAXHelpAttribute as CFString, "Help"),
            (kAXSelectedTextAttribute as CFString, "SelectedText")
        ]
        
        for (attribute, attributeName) in attributesToTry {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, attribute, &value)
            
            if result == .success, let stringValue = value as? String, !stringValue.isEmpty {
                Logger.info("WeChat Element \(attributeName): '\(stringValue)'")
                
                if isValidWeChatMessage(stringValue) {
                    Logger.info("Successfully extracted WeChat message from element \(attributeName): '\(stringValue)'")
                    return stringValue
                }
            }
        }
        
        return nil
    }
    
    // 验证是否是有效的WeChat消息内容
    private func isValidWeChatMessage(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 过滤掉太短的文本
        guard trimmedText.count >= 1 else {
            return false
        }
        
        // 过滤掉常见的UI元素标题（可以根据需要扩展）
        let uiElementTitles = [
            "发送", "Send", "取消", "Cancel", "确定", "OK", 
            "最小化", "Minimize", "关闭", "Close", "最大化", "Maximize",
            "搜索", "Search", "更多", "More", "设置", "Settings",
            "微信", "WeChat", "联系人", "Contacts", "发现", "Discover",
            "我", "Me", "聊天", "Chats"
        ]
        
        // 如果文本是常见UI元素标题，则不是消息
        for uiTitle in uiElementTitles {
            if trimmedText == uiTitle {
                Logger.info("Filtered out UI element title: '\(trimmedText)'")
                return false
            }
        }
        
        // 其他过滤规则
        // 过滤掉只包含单个字符的表情符号按钮等
        if trimmedText.count == 1 && trimmedText.unicodeScalars.first?.properties.isEmojiPresentation == true {
            Logger.info("Filtered out single emoji: '\(trimmedText)'")
            return false
        }
        
        // Logger.info("Valid WeChat message detected: '\(trimmedText)'")
        return true
    }
    
    // 标记元素为WeChat历史消息
    private func markElementAsWeChatHistoryMessage(_ element: AXUIElement) {
        let elementHash = Unmanaged.passUnretained(element).toOpaque().hashValue
        wechatHistoryMessageElements.insert(elementHash)
        Logger.info("Marked element as WeChat history message: \(elementHash)")
        
        // 清理旧的标记（保留最近的100个）
        if wechatHistoryMessageElements.count > 100 {
            let sortedElements = Array(wechatHistoryMessageElements).sorted()
            let toRemove = sortedElements.prefix(sortedElements.count - 100)
            wechatHistoryMessageElements.subtract(toRemove)
        }
    }
    
    // 检查元素是否为WeChat历史消息
    static func isWeChatHistoryMessage(_ element: AXUIElement) -> Bool {
        let elementHash = Unmanaged.passUnretained(element).toOpaque().hashValue
        return shared.wechatHistoryMessageElements.contains(elementHash)
    }
    
    // 检测鼠标位置下的元素是否为文本元素
    private func isMouseOverTextElement(at location: NSPoint) -> Bool {
        // 将屏幕坐标转换为CGPoint（屏幕坐标系原点在左下角）
        let screenFrame = NSScreen.main?.frame ?? NSRect.zero
        let cgPoint = CGPoint(x: location.x, y: screenFrame.height - location.y)
        
        // 获取系统的 UI 元素访问对象
        let systemWideElement = AXUIElementCreateSystemWide()
        
        // 查找鼠标位置下的元素
        var elementUnderMouse: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWideElement, Float(cgPoint.x), Float(cgPoint.y), &elementUnderMouse)
        
        guard result == .success, let mouseElement = elementUnderMouse else {
            Logger.debug("Failed to get element under mouse")
            return false
        }
        
        // 检查元素角色
        var role: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(mouseElement, kAXRoleAttribute as CFString, &role)
        
        guard roleResult == .success, let roleString = role as? String else {
            Logger.debug("Failed to get element role")
            return false
        }
        
        // 定义文本相关的角色
        let textRoles = [
            "AXTextField",      // 文本输入框
            "AXTextArea",       // 文本区域
            "AXStaticText",     // 静态文本
            "AXGenericElement", // 通用元素（可能包含文本）
            "AXGroup"           // 组元素（可能包含文本）
        ]
        
        let isTextRole = textRoles.contains(roleString)
        Logger.debug("Element under mouse has role: \(roleString), isTextRole: \(isTextRole)")
        
        // 如果是文本角色，进一步检查是否可编辑
        if isTextRole {
            var editable: CFTypeRef?
            let editableResult = AXUIElementCopyAttributeValue(mouseElement, kAXValueAttribute as CFString, &editable)
            
            if editableResult == .success {
                Logger.debug("Element is editable or has value")
                return true
            }
            
            // 检查是否有子元素包含文本
            var children: CFTypeRef?
            let childrenResult = AXUIElementCopyAttributeValue(mouseElement, kAXChildrenAttribute as CFString, &children)
            
            if childrenResult == .success, let childrenArray = children as? NSArray, childrenArray.count > 0 {
                Logger.debug("Element has \(childrenArray.count) children, likely contains text")
                return true
            }
        }
        
        return isTextRole
    }
}
