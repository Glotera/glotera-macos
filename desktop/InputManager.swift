//
//  InputManager.swift
//  Manages input-related operations, such as obtaining the focus element, simulating keyboard events, etc.
//  Created by Claude Code on 2025-07-20.
//  Copyright © 2025 Glotera AI. All rights reserved.
//

import Cocoa 
import Carbon
import CoreFoundation
import ApplicationServices

class InputManager {
    static let shared = InputManager()
    
    // 事件过滤相关属性
    private var isSendingEnterKey = false
    private var enterKeySentTime: Date?
    private var _isSendingSimulatedEvent = false
    private var simulatedEventStartTime: Date?
    private var simulatedEventTimeout: TimeInterval = 0.5 // 500ms 超时
    
    // 事件标记常量
    private let kEventFlagSimulated = CGEventFlags(rawValue: 1 << 30) // 使用bit 30，避免与系统事件冲突
    
    private init() {} 
    
    // 带重试机制的焦点元素获取
    func getFocusedElementWithRetry(maxRetries: Int) -> AXUIElement? {
        for attempt in 1...maxRetries {
            // 直接调用，不使用异步
            if let element = getFocusedElementInternal() {
                Logger.debug("Successfully got focused element on attempt \(attempt)")
                return element
            }
            
            if attempt < maxRetries {
                Logger.debug("Failed to get focused element on attempt \(attempt), retrying...")
                // 短暂延迟后重试
                Thread.sleep(forTimeInterval: 0.3)
            }
        }
        
        Logger.debug("Failed to get focused element after \(maxRetries) attempts")
        return nil
    }
    
    // 内部焦点元素获取实现
    private func getFocusedElementInternal() -> AXUIElement? {
        //检查前台应用是否正确
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        if let frontmostApp  = frontmostApp {
            let name = frontmostApp.localizedName ?? "Unknown"
            let bundleId = frontmostApp.bundleIdentifier ?? "Unknown"
            let pid = frontmostApp.processIdentifier
            Logger.info("Frontmost App → name: \(name), bundleId: \(bundleId), pid: \(pid)")
        } else {
            Logger.warn("Unable to get frontmost application")
            return nil
        }

        // 检查是否是 Chrome，如果是则执行 Accessibility 预热
        let chromeBundleId = "com.google.Chrome"
        if chromeBundleId == AppDetectionManager.shared.getBundleId() {
            Logger.info("Chrome detected, performing accessibility warm-up")
            AppDetectionManager.shared.chromeWarmUpAccessibility()
        }

        // 1. 使用system-wide获取焦点应用
        let sysWide = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        let appResult = AXUIElementCopyAttributeValue(sysWide, kAXFocusedApplicationAttribute as CFString, &focusedApp)
        
        if appResult != .success , let frontmostApp = frontmostApp {
            Logger.debug("Failed to get focused application: \(appResult), try frontmost app") 
         
            // 1.1 使用前台应用直接获取焦点元素
            let pid = frontmostApp.processIdentifier
            let appElement = AXUIElementCreateApplication(pid)
            var focusedElement: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
            if result == .success, let focusedElement = focusedElement {
                return (focusedElement as! AXUIElement)
            } else {
                Logger.warn("Frontmost App focus detection failed: result=\(result), focusedElement=\(focusedElement?.description ?? "nil")")
            }

            return nil // 如果前台应用获取失败，则返回nil
        }
        
        guard let app = focusedApp else {
            Logger.debug("Failed to get focused app")
            return nil
        }
        let appElement = app as! AXUIElement
        
        // 获取应用信息用于调试
        var appName: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXTitleAttribute as CFString, &appName) == .success,
           let name = appName as? String {
            Logger.debug("Focused app: \(name)")
        }
        
        // 2. 获取焦点元素
        var focusedElem: CFTypeRef?
        let elemResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElem)
        
        if elemResult != .success {
            Logger.debug("Failed to get focused UI element, try another method: \(elemResult)")
            
            // 特殊处理：Microsoft Teams
            if AppDetectionManager.shared.isTeamsApp() {
                Logger.info("Teams detected - trying specialized focus detection")
                if let teamsElement = getTeamsFocusedElement(appElement) {
                    return teamsElement
                }
            }
            
            //如果无法从system-wide元素->焦点应用->焦点元素这个路径获取成功，直接尝试 system-wide->焦点元素
            let elemResult = AXUIElementCopyAttributeValue(sysWide, kAXFocusedUIElementAttribute as CFString, &focusedElem)
            if elemResult != .success {
                Logger.debug("Failed to get focused UI element again")
                return nil
            }
        }
        
        guard let elem = focusedElem else {
            Logger.debug("Failed to get focused element")
            return nil
        }
        let element = elem as! AXUIElement
        
        // 4. 验证元素有效性
        if !isElementValid(element) {
            Logger.debug("Focused element is not valid")
            return nil
        }
        
        // 5. 记录元素信息用于调试
        logElementInfo(element)
        
        return element
    }
    
    // 验证元素是否有效
    private func isElementValid(_ element: AXUIElement) -> Bool {
        var pid: pid_t = 0
        let result = AXUIElementGetPid(element, &pid)
        return result == .success && pid > 0
    }
    
    // 记录元素信息用于调试
    private func logElementInfo(_ element: AXUIElement) {
        var role: CFTypeRef?
        var title: CFTypeRef?
        var description: CFTypeRef?
        var value: CFTypeRef?
        var enabled: CFTypeRef?
        var canEdit: CFTypeRef?
        
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let titleResult = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
        let descResult = AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &description)
        let valueResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        let enabledResult = AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabled)
        let canEditResult = AXUIElementCopyAttributeValue(element, "AXCanEdit" as CFString, &canEdit)
        
        var info = "Focused element: "
        if roleResult == .success, let roleStr = role as? String {
            info += "role=\(roleStr) "
        }
        if titleResult == .success, let titleStr = title as? String {
            info += "title='\(titleStr)' "
        }
        if descResult == .success, let descStr = description as? String {
            info += "description='\(descStr)' "
        }
        if valueResult == .success, let valueStr = value as? String {
            info += "value='\(valueStr.prefix(50))' "
        }
        if enabledResult == .success, let enabledBool = enabled as? Bool {
            info += "enabled=\(enabledBool) "
        }
        if canEditResult == .success, let canEditBool = canEdit as? Bool {
            info += "canEdit=\(canEditBool) "
        }
        
        Logger.debug(info)
        
        // 如果是TRAE应用，记录更详细的信息
        if AppDetectionManager.shared.isTRAEApp() {
            Logger.info("Element role=\(role as? String ?? "unknown"), enabled=\(enabled as? Bool ?? false), canEdit=\(canEdit as? Bool ?? false)")
        }
    }
    
    // Microsoft Teams 专用焦点检测
    private func getTeamsFocusedElement(_ appElement: AXUIElement) -> AXUIElement? {
        Logger.info("Starting specialized Teams focus detection")
        
        // Teams 是基于 Electron 的应用，通常有复杂的嵌套结构
        // 尝试多种方法来找到可编辑的输入元素
        
        // 方法1: 深度遍历查找文本输入框
        if let inputElement = findTeamsInputElement(appElement, depth: 0, maxDepth: 6) {
            Logger.info("Found Teams input element via deep traversal")
            return inputElement
        }
        
        // 方法2: 查找 WebArea 然后深入
        if let webElement = findTeamsWebArea(appElement) {
            Logger.info("Found Teams web area, searching for input")
            if let inputElement = findTeamsInputElement(webElement, depth: 0, maxDepth: 4) {
                Logger.info("Found Teams input element in web area")
                return inputElement
            }
        }
        
        // 方法3: 使用鼠标位置检测 (类似 WhatsApp 方法)
        if let mouseElement = getElementUnderMouse() {
            if isTeamsEditableElement(mouseElement) {
                Logger.info("Found Teams element under mouse")
                return mouseElement
            }
        }
        
        Logger.warn("All Teams focus detection methods failed")
        return nil
    }
    
    // 深度查找 Teams 输入元素
    private func findTeamsInputElement(_ element: AXUIElement, depth: Int, maxDepth: Int) -> AXUIElement? {
        if depth > maxDepth {
            return nil
        }
        
        // 检查当前元素是否是可编辑的输入框
        if isTeamsEditableElement(element) {
            return element
        }
        
        // 获取子元素并递归搜索
        var children: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        
        if childrenResult == .success, let childrenArray = children as? NSArray {
            for child in childrenArray {
                let childElement = child as! AXUIElement
                if let found = findTeamsInputElement(childElement, depth: depth + 1, maxDepth: maxDepth) {
                    return found
                }
            }
        }
        
        return nil
    }
    
    // 查找 Teams WebArea
    private func findTeamsWebArea(_ appElement: AXUIElement) -> AXUIElement? {
        var children: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(appElement, kAXChildrenAttribute as CFString, &children)
        
        if childrenResult == .success, let childrenArray = children as? NSArray {
            for child in childrenArray {
                let childElement = child as! AXUIElement
                var role: CFTypeRef?
                if AXUIElementCopyAttributeValue(childElement, kAXRoleAttribute as CFString, &role) == .success,
                   let roleString = role as? String,
                   roleString == "AXWebArea" {
                    return childElement
                }
                
                // 递归查找
                if let webArea = findTeamsWebArea(childElement) {
                    return webArea
                }
            }
        }
        
        return nil
    }
    
    // 检查是否是 Teams 可编辑元素
    private func isTeamsEditableElement(_ element: AXUIElement) -> Bool {
        var role: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        
        guard roleResult == .success, let roleString = role as? String else {
            return false
        }
        
        // Teams 中常见的可编辑元素类型
        let editableRoles = [
            "AXTextField",
            "AXTextArea", 
            "AXComboBox",
            "AXGroup",  // Teams 消息输入框通常是 AXGroup
            "AXGenericElement"  // 有时是通用元素
        ]
        
        if !editableRoles.contains(roleString) {
            return false
        }
        
        // 检查是否可编辑
        var canEdit: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXCanEdit" as CFString, &canEdit) == .success,
           let canEditBool = canEdit as? Bool,
           canEditBool {
            return true
        }
        
        // 检查是否有值属性 (输入框特征)
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success {
            return true
        }
        
        // Teams 的输入框可能没有标准的编辑属性，但有特定的描述
        var description: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &description) == .success,
           let descString = description as? String,
           descString.lowercased().contains("message") || descString.lowercased().contains("type") {
            return true
        }
        
        return false
    }
    
    // 获取鼠标位置下的元素
    private func getElementUnderMouse() -> AXUIElement? {
        let mouseLocation = NSEvent.mouseLocation
        let screenFrame = NSScreen.main?.frame ?? NSRect.zero
        let cgPoint = CGPoint(x: mouseLocation.x, y: screenFrame.height - mouseLocation.y)
        
        let systemWideElement = AXUIElementCreateSystemWide()
        var elementUnderMouse: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWideElement, Float(cgPoint.x), Float(cgPoint.y), &elementUnderMouse)
        
        if result == .success {
            return elementUnderMouse
        }
        
        return nil
    }

    // ==== 键盘模拟事件 ====

    // 发送Cmd+A
    func postSelectAll() {
        beginSimulatedEvent()
        defer { endSimulatedEvent() }
        
        let source = CGEventSource(stateID: .hidSystemState)
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: true)
        let aDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_A), keyDown: true)
        let aUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_A), keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: false)
        
        cmdDown?.flags = .maskCommand
        aDown?.flags = .maskCommand
        
        // 标记为模拟事件
        markEventAsSimulated(cmdDown!)
        markEventAsSimulated(aDown!)
        markEventAsSimulated(aUp!)
        markEventAsSimulated(cmdUp!)
        
        cmdDown?.post(tap: .cghidEventTap)
        aDown?.post(tap: .cghidEventTap)
        aUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
        
        Logger.info("Posted global Cmd+A (simulated)")
    }

    // 发送Cmd+C
    func postCopy() {
        beginSimulatedEvent()
        defer { endSimulatedEvent() }
        
        let source = CGEventSource(stateID: .hidSystemState)
        
        // 确保事件源有效
        guard source != nil else {
            Logger.error("Failed to create event source for copy command")
            return
        }
        
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: true)
        let cDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        let cUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: false)
        
        // 确保所有事件都有效
        guard let cmdDown = cmdDown, let cDown = cDown, let cUp = cUp, let cmdUp = cmdUp else {
            Logger.error("Failed to create copy command events")
            return
        }
        
        cmdDown.flags = .maskCommand
        cDown.flags = .maskCommand
        
        // 标记为模拟事件
        markEventAsSimulated(cmdDown)
        markEventAsSimulated(cDown)
        markEventAsSimulated(cUp)
        markEventAsSimulated(cmdUp)
        
        // 按顺序发送事件
        cmdDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05) // 短暂延迟确保按键顺序
        cDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        cUp.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        cmdUp.post(tap: .cghidEventTap)
        
        Logger.info("Posted global Cmd+C copy command (simulated)")
    }

    // 发送右箭头键以取消全选
    func postRightArrowKey() {
        beginSimulatedEvent()
        defer { endSimulatedEvent() }
        
        let source = CGEventSource(stateID: .hidSystemState)
        let rightArrowKeyCode = 124 as CGKeyCode // kVK_RightArrow
        
        let downEvent = CGEvent(keyboardEventSource: source, virtualKey: rightArrowKeyCode, keyDown: true)
        let upEvent = CGEvent(keyboardEventSource: source, virtualKey: rightArrowKeyCode, keyDown: false)
        
        // 标记为模拟事件
        markEventAsSimulated(downEvent!)
        markEventAsSimulated(upEvent!)
        
        downEvent?.post(tap: .cghidEventTap)
        upEvent?.post(tap: .cghidEventTap)
        
        Logger.info("Posted Right Arrow key to deselect text after misfire (simulated)")
    }

    // 发送粘贴命令Cmd+V
    func postPaste() {
        beginSimulatedEvent()
        defer { endSimulatedEvent() }
        
        let source = CGEventSource(stateID: .hidSystemState)
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: true)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: false)
        
        cmdDown?.flags = .maskCommand
        vDown?.flags = .maskCommand
        
        // 标记为模拟事件
        markEventAsSimulated(cmdDown!)
        markEventAsSimulated(vDown!)
        markEventAsSimulated(vUp!)
        markEventAsSimulated(cmdUp!)
        
        cmdDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
        
        Logger.info("Posted Cmd+V (Paste) (simulated)")
    }

    // 为文本编辑器发送智能选择命令（选择光标前的内容）
    // Shift+Cmd+Left 选择当前行到行首
    // Shift+Cmd+Up 选择当前行到文档开头
    func postSmartSelection() {
        beginSimulatedEvent()
        defer { endSimulatedEvent() }
        
        Logger.info("Using optimized smart selection - selecting content before cursor")
        
        let source = CGEventSource(stateID: .hidSystemState)
        
        // 确保事件源有效
        guard source != nil else {
            Logger.error("Failed to create event source")
            return
        }
        
        // 优化选择策略：减少延迟，提高响应速度
        
        // 第一步：选择当前行到行首 (Shift+Cmd+Left)
        Logger.info("Step 1 - Sending Shift+Cmd+Left to select to line start")
        let leftDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_LeftArrow), keyDown: true)
        leftDown?.flags = [.maskShift, .maskCommand]
        markEventAsSimulated(leftDown!)
        
        let leftUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_LeftArrow), keyDown: false)
        leftUp?.flags = [.maskShift, .maskCommand]
        markEventAsSimulated(leftUp!)
        
        leftDown?.post(tap: .cghidEventTap)
        leftUp?.post(tap: .cghidEventTap)
        
        // 减少等待时间，提高响应速度
        Thread.sleep(forTimeInterval: 0.1)
        
        // 第二步：继续向上选择到文档开头 (Shift+Cmd+Up)
        // 这会扩展当前选择，包含光标前的所有行
        Logger.info("Step 2 - Sending Shift+Cmd+Up to extend selection to document start")
        let upDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_UpArrow), keyDown: true)
        upDown?.flags = [.maskShift, .maskCommand]
        markEventAsSimulated(upDown!)
        
        let upUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_UpArrow), keyDown: false)
        upUp?.flags = [.maskShift, .maskCommand]
        markEventAsSimulated(upUp!)
        
        upDown?.post(tap: .cghidEventTap)
        upUp?.post(tap: .cghidEventTap)
        
        // 减少等待时间，提高响应速度
        Thread.sleep(forTimeInterval: 0.05)
        
        Logger.info("Smart selection completed - should have selected all content before cursor (simulated)")
    }

    // 发送回车键事件
    func sendEnterKey() {
        Logger.info("Sending Enter key event")
        
        // 设置标志防止拦截我们自己发送的Enter键
        isSendingEnterKey = true
        enterKeySentTime = Date()
        
        // 检查是否为微信，微信需要特殊处理 - 使用缓存的检测结果
        let isWeChat = AppDetectionManager.shared.isWeChatApp()
        
        if isWeChat {
            // 微信需要特殊处理：确保焦点正确且使用适当的事件发送方式
            sendEnterKeyForWeChat()
        } else {
            // 其他应用（包括Discord、钉钉等）使用标准方式
            sendEnterKeyStandard()
        }
        
        // 延迟清除标志，确保Enter键事件已经处理完毕
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isSendingEnterKey = false
            Logger.info("Enter key sending flag cleared")
        }
    }

       // 微信专用的Enter键发送
    private func sendEnterKeyForWeChat() {
        Logger.info("Sending Enter key for WeChat")
        
        // 确保微信窗口获得焦点
        ensureWeChatFocus { focused in
            guard focused else {
                Logger.warn("WeChat: Failed to ensure focus for Enter key")
                return
            }
            
            // 等待焦点稳定后发送Enter键
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                // 使用最直接有效的方法发送Enter键
                self.sendWeChatEnterKeyDirect()
            }
        }
    } 
    
    // 确保微信应用获得焦点
    private func ensureWeChatFocus(completion: @escaping (Bool) -> Void) {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier,
              bundleId.contains("wechat") || bundleId.contains("WeChat") else {
            Logger.warn("WeChat: Not currently the frontmost application")
            completion(false)
            return
        }
        
        // 微信已经是前台应用，直接成功
        Logger.info("WeChat: Already focused")
        completion(true)
    }
    
    // 直接发送微信Enter键的优化方法
    private func sendWeChatEnterKeyDirect() {
        Logger.info("WeChat: Sending Enter key directly")
        
        // 先验证输入框内容是否已更新（可选的安全检查）
        if let focused = AXController.shared.getFocusedElement(),
           let currentContent = AXController.shared.getValue(of: focused) {
            Logger.info("WeChat: Current input content before Enter: '\(currentContent)'")
        }
        
        // 使用AppleScript是最可靠的方法，因为它直接与系统事件交互
        let script = """
        tell application "System Events"
            tell process "WeChat"
                key code 36
            end tell
        end tell
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            if error == nil {
                Logger.info("WeChat: Enter key sent successfully via AppleScript")
            } else {
                Logger.warn("WeChat: AppleScript failed: \(error?.description ?? "Unknown error"), trying CGEvent")
                // 如果AppleScript失败，回退到CGEvent方法
                self.sendWeChatEnterKeyViaCGEvent()
            }
        } else {
            Logger.warn("WeChat: Failed to create AppleScript, trying CGEvent")
            self.sendWeChatEnterKeyViaCGEvent()
        }
    }


    
    // 使用CGEvent发送微信Enter键（备用方法）
    private func sendWeChatEnterKeyViaCGEvent() {
        beginSimulatedEvent()
        defer { endSimulatedEvent() }
        
        Logger.info("WeChat: Sending Enter key via CGEvent")
        
        let source = CGEventSource(stateID: .hidSystemState)
        if let enterKeyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: true),
           let enterKeyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: false) {
            
            // 设置事件标志以确保微信能够识别
            enterKeyDown.flags = []
            enterKeyUp.flags = []
            
            // 标记为模拟事件
            markEventAsSimulated(enterKeyDown)
            markEventAsSimulated(enterKeyUp)
            
            // 发送按下事件
            enterKeyDown.post(tap: .cghidEventTap)
            
            // 稍微延迟后发送释放事件
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                enterKeyUp.post(tap: .cghidEventTap)
                Logger.info("WeChat: Enter key sent via CGEvent (simulated)")
            }
        } else {
            Logger.error("WeChat: Failed to create CGEvent Enter key events")
        }
    }
    
    // 标准的Enter键发送
    private func sendEnterKeyStandard() {
        beginSimulatedEvent()
        defer { endSimulatedEvent() }
        
        Logger.info("Sending Enter key (standard method)")
        
        let source = CGEventSource(stateID: .hidSystemState)
        if let enterKeyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: true),
           let enterKeyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: false) {
            
            // 标记为模拟事件
            markEventAsSimulated(enterKeyDown)
            markEventAsSimulated(enterKeyUp)
            
            enterKeyDown.post(tap: .cghidEventTap)
            enterKeyUp.post(tap: .cghidEventTap)
            Logger.info("Standard: Enter key sent successfully (simulated)")
        }
    }

    func isSendingEnterKeyEvent() -> Bool {
        return isSendingEnterKey
    }

    func getEnterKeySentTime() -> Date? {
        return enterKeySentTime
    }

    // 恢复焦点并选中全部文本
    func restoreFocusAndSelectAll(for element: AXUIElement, appBundleId: String) {
        // 1. 切回原应用（如钉钉）
        NSRunningApplication.runningApplications(withBundleIdentifier: appBundleId).first?.activate(options: [.activateIgnoringOtherApps])

        // 2. 点击输入框（使其获取焦点）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.clickAXElement(element)

            // 3. 再发送 Cmd+A（选中全部文本）
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.postSelectAll()
            }
        }
    }

    // 点击AXElement
    private func clickAXElement(_ element: AXUIElement) {
        var frameRef: CFTypeRef?
        let kAXFrameAttribute = "AXFrame" as CFString
        
        if AXUIElementCopyAttributeValue(element, kAXFrameAttribute, &frameRef) == .success,
           let frameValue = frameRef {
            var rect = CGRect.zero
            if AXValueGetValue(frameValue as! AXValue, .cgRect, &rect) {
                let clickPoint = CGPoint(x: rect.midX, y: rect.midY)
                if let source = CGEventSource(stateID: .hidSystemState) {
                    if let mouseDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: clickPoint, mouseButton: .left),
                       let mouseUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: clickPoint, mouseButton: .left) {
                        mouseDown.post(tap: .cghidEventTap)
                        mouseUp.post(tap: .cghidEventTap)
                        Logger.info("Clicked AXElement: \(clickPoint)")
                    }  
                }  
            }  
        }  
    }

    // MARK: - Event Filtering Methods
    
    // 开始标记模拟事件
    func beginSimulatedEvent() {
        _isSendingSimulatedEvent = true
        simulatedEventStartTime = Date()
        Logger.debug("Begin simulated event mode")
    }
    
    // 结束标记模拟事件
    func endSimulatedEvent() {
        _isSendingSimulatedEvent = false
        simulatedEventStartTime = nil
        Logger.debug("End simulated event mode")
    }
    
    // 检查是否正在发送模拟事件
    func isSendingSimulatedEvent() -> Bool {
        // 检查超时
        if let startTime = simulatedEventStartTime,
           Date().timeIntervalSince(startTime) > simulatedEventTimeout {
            Logger.warn("Simulated event timeout, auto-clearing")
            endSimulatedEvent()
            return false
        }
        return _isSendingSimulatedEvent
    }
    
    // 标记事件为模拟事件
    private func markEventAsSimulated(_ event: CGEvent) {
        // Only mark keyboard events and use custom data field
        let eventType = event.type
        if eventType == .keyDown || eventType == .keyUp {
            event.flags.insert(kEventFlagSimulated)
        }
    }
    
    // 检查事件是否为模拟事件
    func isEventSimulated(_ event: CGEvent) -> Bool {
        // 首先检查事件类型 - 只处理键盘事件
        let eventType = event.type
        guard eventType == .keyDown || eventType == .keyUp else {
            // 非键盘事件直接返回false，避免处理鼠标事件
            return false
        }
        
        // 检查标志位
        let hasSimulatedFlag = event.flags.contains(kEventFlagSimulated)
        
        // 如果标志位匹配，还需要检查是否在模拟事件时间窗口内
        if hasSimulatedFlag {
            // 检查是否在模拟事件发送期间
            if isSendingSimulatedEvent() {
                Logger.debug("Keyboard event confirmed as simulated (flag + time window)")
                return true
            } else {
                // 标志位存在但不在时间窗口内，可能是残留的标志位，清除它
                Logger.debug("Found simulated flag on keyboard event but not in time window, clearing flag")
                event.flags.remove(kEventFlagSimulated)
                return false
            }
        }
        
        return false
    }
    
    // 获取模拟事件标志
    func getSimulatedEventFlag() -> CGEventFlags {
        return kEventFlagSimulated
    }

}
