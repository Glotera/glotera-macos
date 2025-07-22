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
    private var lastCtrlATime: Date = Date.distantPast 
    
    // 用于跟踪最近的自动翻译操作
    private var lastAutoTranslationTime: Date = Date.distantPast
    private var lastAutoTranslationText: String = ""

    private init() {}

        // 开始监听选中文本变化
    func startSelectionMonitoring() {
        Logger.info("Starting selection monitoring (keyboard-event-safe)")
        
        // Initialize trigger pattern cache for optimized trigger detection
        TriggerManager.shared.refreshCaches()
        
        // 延迟启动鼠标监听，确保键盘监听优先建立
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.startMouseEventMonitoring()
        }
        
        // 使用较低频率的定时器进一步减少对系统的影响
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            self.checkForTextSelection()
        }
    }

     // 监听鼠标事件
    private func startMouseEventMonitoring() {
        // 监听鼠标事件，包括双击
        mouseEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged]) { [weak self] event in
            DispatchQueue.main.async {
                self?.handleMouseEvent(event)
            }
        }
        
        // 移除键盘事件监听，避免与 InputMonitor 的 CGEvent 监听冲突
        // keyboardEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
        //     DispatchQueue.main.async {
        //         self?.handleKeyboardEvent(event)
        //     }
        // }
        
        Logger.info("Mouse event monitoring started (keyboard monitoring delegated to InputMonitor)")
    }
    
    private func handleMouseEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            // 检测双击
            let now = Date()
            let timeSinceLastClick = now.timeIntervalSince(lastDoubleClickTime)
            
            if timeSinceLastClick < 0.5 && timeSinceLastClick > 0.1 {
                // 双击检测
                Logger.info("Double click detected")
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
        Logger.info("Checking text selection after mouse up")
        
        // 等待一个更长的延迟，确保选择完全稳定
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // 只有在鼠标拖拽选择后才显示菜单
            self.checkSelectedTextAndShowMenuAfterMouseSelection()
        }
    }
    
    // 双击后的文本选择检查
    private func checkForTextSelectionAfterDoubleClick() {
        Logger.info("Checking text selection after double click")
        
        // 等待延迟，确保双击选择完全稳定
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.checkSelectedTextAndShowMenuAfterMouseSelection()
        }
    }

       // 只隐藏菜单，不显示菜单的逻辑
    private func hideMenuIfNoSelection() {
        let startTime = Date()
        
        guard let selection = getSelectedText() else {
            // 如果没有选中文本，隐藏菜单并重置状态
            if !lastSelectedText.isEmpty {
                TranslationMenuWindow.shared.hide()
                lastSelectedText = ""
                isMenuShowing = false
            }
            
            let processingTime = Date().timeIntervalSince(startTime)
            if processingTime > 0.2 {
                Logger.warn("hideMenuIfNoSelection took \(String(format: "%.3f", processingTime))s - performance warning")
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
        
        let processingTime = Date().timeIntervalSince(startTime)
        if processingTime > 0.2 {
            Logger.warn("hideMenuIfNoSelection took \(String(format: "%.3f", processingTime))s - performance warning")
        }
    }
    

    // 鼠标选择后的菜单显示逻辑
    private func checkSelectedTextAndShowMenuAfterMouseSelection() {
        checkSelectedTextAndShowMenu(selectionType: "mouse")
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
            // 如果没有选中文本，隐藏菜单并重置状态
            if !lastSelectedText.isEmpty {
                TranslationMenuWindow.shared.hide()
                lastSelectedText = ""
                isMenuShowing = false
            }
            
            let processingTime = Date().timeIntervalSince(startTime)
            if processingTime > 0.2 {
                Logger.warn("checkSelectedTextAndShowMenu (\(selectionType)) took \(String(format: "%.3f", processingTime))s - performance warning")
            }
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
            
            Logger.info("Selected text after \(selectionType) selection: '\(originalText)' (length: \(originalText.count))") 
            
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
                Logger.info("Menu closed callback triggered")
                }
        }
    }

      

    // 获取当前选中的文本
    func getSelectedText() -> (text: String, element: AXUIElement)? {
        guard let focused = InputManager.shared.getFocusedElementWithRetry(maxRetries: 3) else {
            // print("[LOG] No focused element for selection")
            return nil
        }
        
        // 首先尝试通过AX API获取选中文本
        if let selectedText = getSelectedTextAttribute(of: focused), !selectedText.isEmpty {
            // Logger.debug("[LOG] Got selected text via AX: '\(selectedText)'")
            return (text: selectedText, element: focused)
        }
        
        // 如果在浏览器环境中，尝试通过JavaScript获取选中文本
        if AppDetectionManager.shared.isWebEnvironment() {
            if let selectedText = AppleScriptManager.shared.getWebSelectedText(), !selectedText.isEmpty {
                Logger.info("Got selected text via Web: '\(selectedText)'")
                return (text: selectedText, element: focused)
            }
        }
         
        return nil
    }

     
    // 获取选中文本属性
    func getSelectedTextAttribute(of element: AXUIElement) -> String? {
        let startTime = Date()
        
        var selectedTextValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextValue)
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        // 性能监控：如果处理时间过长，记录警告
        if processingTime > 0.2 {
            Logger.warn("AXUIElementCopyAttributeValue took \(String(format: "%.3f", processingTime))s - performance warning")
        }
        
        if result == .success, let text = selectedTextValue as? String {
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
}
