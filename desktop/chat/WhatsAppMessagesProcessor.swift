import Cocoa
import Foundation

/// WhatsApp messages processor using Accessibility API

// 根据whatsapp.md分析，使用元素块特征来查找内容：
// 1. 联系人元素块特征：AXGroup下面有4个子元素，第一个是AXHeading，其它3个是AXButton
// 2. 对话框元素块特征：AXGroup下面有5个子元素，第一个是AXGroup，第三个是AXTextArea，其它三个是AXButton

class WhatsAppMessagesProcessor: ChatMessagesProcessor {
    static let maxRecursionDepth = 20
    static let maxChildrenCount = 50
    
    /// Get current chat session ID from WhatsApp using element block features
    static func getCurrentChatSessionId(activeApp: NSRunningApplication) -> String? {
        
        let pid = activeApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        
        // Get the main window
        var mainWindow: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindow)
        
        guard windowResult == .success, let window = mainWindow else {
            return nil
        }
        
        let windowElement = window as! AXUIElement 

        // 首先尝试使用元素块特征查找联系人名称
        if let contactName = findContactNameByElementBlockFeatures(windowElement) {
            Logger.info("Found contact name using element block features: \(contactName)")
            return contactName
        }
        
        // 如果元素块特征查找失败，使用fallback方式从历史消息中解析
        Logger.info("Element block features failed, trying fallback method from history messages")
        if let contactName = findContactNameFromHistoryMessages(windowElement) {
            Logger.info("Found contact name from history messages: \(contactName)")
            return contactName
        }
        
        return nil
    }

    // 使用元素块特征查找联系人名称 - 添加深度限制防止崩溃
    private static func findContactNameByElementBlockFeatures(_ element: AXUIElement, currentDepth: Int = 0, maxDepth: Int = 10) -> String? {
        // 防止过深的递归导致栈溢出
        if currentDepth > maxDepth {
            Logger.warn("WhatsApp: Reached maximum search depth (\(maxDepth)) for contact name, stopping traversal")
            return nil
        }
        
        // 检查当前元素是否为联系人元素块
        if let contactName = checkContactElementBlock(element) {
            return contactName
        }
        
        // 递归搜索子元素 - 限制递归深度
        var children: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        if childrenResult == .success, let childrenArray = children as? [AXUIElement] {
            // 限制子元素数量，避免处理过大的UI树
            let limitedChildren = Array(childrenArray.prefix(maxChildrenCount))
            if childrenArray.count > maxChildrenCount {
                Logger.warn("WhatsApp: Contact search UI tree has \(childrenArray.count) children, limiting to \(maxChildrenCount)")
            }
            
            for child in limitedChildren {
                if let found = findContactNameByElementBlockFeatures(child, currentDepth: currentDepth + 1, maxDepth: maxDepth) {
                    return found
                }
            }
        }
        return nil
    }
    
    // 检查元素是否为联系人元素块
    private static func checkContactElementBlock(_ element: AXUIElement) -> String? {
        var role: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        guard roleResult == .success, let roleString = role as? String, roleString == "AXGroup" else {
            return nil
        }
        
        // 获取子元素
        var children: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        guard childrenResult == .success, let childrenArray = children as? [AXUIElement], childrenArray.count == 4 else {
            return nil
        }
        
        // 检查第一个子元素是否为AXHeading
        var firstChildRole: CFTypeRef?
        let firstChildRoleResult = AXUIElementCopyAttributeValue(childrenArray[0], kAXRoleAttribute as CFString, &firstChildRole)
        guard firstChildRoleResult == .success, let firstChildRoleString = firstChildRole as? String, firstChildRoleString == "AXHeading" else {
            return nil
        }
        
        // 检查其他3个子元素是否为AXButton
        for i in 1..<4 {
            var childRole: CFTypeRef?
            let childRoleResult = AXUIElementCopyAttributeValue(childrenArray[i], kAXRoleAttribute as CFString, &childRole)
            guard childRoleResult == .success, let childRoleString = childRole as? String, childRoleString == "AXButton" else {
                return nil
            }
        }
        
        // 获取AXHeading的描述作为联系人名称
        var description: CFTypeRef?
        let descResult = AXUIElementCopyAttributeValue(childrenArray[0], kAXDescriptionAttribute as CFString, &description)
        if descResult == .success, let descString = description as? String, !descString.isEmpty {
            Logger.info("Found contact name from element block: \(descString)")
            return descString.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return nil
    }
    
    // 从历史消息中解析联系人名称（fallback方法） - 添加深度限制防止崩溃
    private static func findContactNameFromHistoryMessages(_ element: AXUIElement, currentDepth: Int = 0, maxDepth: Int = 8) -> String? {
        // 防止过深的递归导致栈溢出
        if currentDepth > maxDepth {
            Logger.warn("WhatsApp: Reached maximum search depth (\(maxDepth)) for history messages, stopping traversal")
            return nil
        }
        
        // 检查当前元素是否为AXGenericElement且包含消息
        var role: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        if roleResult == .success, let roleString = role as? String {
            if roleString == "AXGenericElement" {
                var descValue: CFTypeRef?
                let descResult = AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descValue)
                if descResult == .success, let desc = descValue as? String {
                    // 尝试从接收消息中提取联系人名称
                   if let chatMessage = ContentProcessor.shared.parseWhatsAppMessage(desc,language: "en"),
                      !chatMessage.sender.isEmpty && chatMessage.sender != "You" {
                        Logger.info("Found contact name from received message: \(chatMessage.sender)")
                        return chatMessage.sender
                    } 

                    if let chatMessage = ContentProcessor.shared.parseWhatsAppMessage(desc,language: "zh"),
                       !chatMessage.sender.isEmpty && chatMessage.sender != "You" {
                        Logger.info("Found contact name from received message: \(chatMessage.sender)")
                        return chatMessage.sender
                    }
                }
            }
        }
        
        // 递归搜索子元素 - 限制递归深度
        var children: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        if childrenResult == .success, let childrenArray = children as? [AXUIElement] {
            // 限制子元素数量，避免处理过大的UI树
            let limitedChildren = Array(childrenArray.prefix(maxChildrenCount))
            if childrenArray.count > maxChildrenCount {
                Logger.warn("WhatsApp: History message search UI tree has \(childrenArray.count) children, limiting to \(maxChildrenCount)")
            }
            
            for child in limitedChildren {
                if let found = findContactNameFromHistoryMessages(child, currentDepth: currentDepth + 1, maxDepth: maxDepth) {
                    return found
                }
            }
        }
        return nil
    }
    
    /// Extract messages from WhatsApp using Accessibility API with element block features
    static func extractMessages(from app: NSRunningApplication, filterAfterTimestamp: Date) -> [ChatMessage] {
        var extractedMessages: [ChatMessage] = []
        
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        
        // Get the main window
        var mainWindow: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindow)
        
        guard windowResult == .success, let window = mainWindow else {
            Logger.debug("Failed to get WhatsApp main window")
            return extractedMessages
        }
        
        let windowElement = window as! AXUIElement
        
        // Note: printElementTree removed to prevent performance issues and crashes
        // Only enable for debugging purposes when needed
        // ChatMessagesUtil.printElementTree(windowElement)

        // 首先尝试使用元素块特征查找对话框
        if let messages = findMessagesByElementBlockFeatures(windowElement, filterAfterTimestamp: filterAfterTimestamp) {
            Logger.info("Extracted \(messages.count) messages using element block features")
            return messages
        }
        
        // 如果元素块特征查找失败，使用fallback方式
        Logger.info("Element block features failed, trying fallback method")
        return fallback(windowElement: windowElement, filterAfterTimestamp: filterAfterTimestamp)
    }
    
    // 使用元素块特征查找消息 - 添加深度限制防止崩溃
    private static func findMessagesByElementBlockFeatures(_ element: AXUIElement, filterAfterTimestamp: Date, currentDepth: Int = 0, maxDepth: Int = maxRecursionDepth) -> [ChatMessage]? {
        // 防止过深的递归导致栈溢出
        if currentDepth > maxDepth {
            Logger.warn("WhatsApp: Reached maximum search depth (\(maxDepth)), stopping traversal to prevent crashes")
            return nil
        }
        
        var messages: [ChatMessage] = []
        
        // 检查当前元素是否为对话框元素块
        if let elementMessages = checkDialogElementBlock(element, filterAfterTimestamp: filterAfterTimestamp) {
            messages.append(contentsOf: elementMessages)
            return messages
        }
        
        // 递归搜索子元素 - 限制递归深度
        var children: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        if childrenResult == .success, let childrenArray = children as? [AXUIElement] {
            // 限制子元素数量，避免处理过大的UI树，只取最后的maxChildrenCount个
            let limitedChildren = Array(childrenArray.suffix(maxChildrenCount))
            if childrenArray.count > maxChildrenCount {
                Logger.warn("WhatsApp: UI tree has \(childrenArray.count) children, limiting to \(maxChildrenCount) to prevent performance issues")
            }
            
            for child in limitedChildren {
                if let childMessages = findMessagesByElementBlockFeatures(child, filterAfterTimestamp: filterAfterTimestamp, currentDepth: currentDepth + 1, maxDepth: maxDepth) {
                    messages.append(contentsOf: childMessages)
                    return messages
                }
            }
        }
        
        return messages.isEmpty ? nil : messages
    }
    
    // 检查元素是否为对话框元素块
    private static func checkDialogElementBlock(_ element: AXUIElement, filterAfterTimestamp: Date) -> [ChatMessage]? {
        var role: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        guard roleResult == .success, let roleString = role as? String, roleString == "AXGroup" else {
            return nil
        }
        
        // 获取子元素
        var children: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        guard childrenResult == .success, let childrenArray = children as? [AXUIElement], childrenArray.count >= 5 else {
            return nil
        }
        
        // 检查第一个子元素是否为AXGroup
        var firstChildRole: CFTypeRef?
        let firstChildRoleResult = AXUIElementCopyAttributeValue(childrenArray[0], kAXRoleAttribute as CFString, &firstChildRole)
        guard firstChildRoleResult == .success, let firstChildRoleString = firstChildRole as? String, firstChildRoleString == "AXGroup" else {
            return nil
        }
        
        // Check if there is at least one AXTextArea and the rest are AXButton (order does not matter)
        var textAreaFound = false
        var buttonCount = 0
        for (idx, child) in childrenArray.enumerated() {
            var childRole: CFTypeRef?
            let childRoleResult = AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &childRole)
            guard childRoleResult == .success, let childRoleString = childRole as? String else {
                return nil
            }
            if childRoleString == "AXTextArea" {
                textAreaFound = true
            } else if childRoleString == "AXButton" {
                buttonCount += 1
            }
        }
        // There must be at least one AXTextArea and at least three AXButton
        guard textAreaFound, buttonCount >= 3 else {
            return nil
        }
        
        // 解析第一个AXGroup中的消息
        return parseMessagesFromDialogGroup(childrenArray[0], filterAfterTimestamp: filterAfterTimestamp)
    }
    
    // 解析对话框组中的消息
    private static func parseMessagesFromDialogGroup(_ dialogGroup: AXUIElement, filterAfterTimestamp: Date) -> [ChatMessage]? {
        var messages: [ChatMessage] = []
        
        // 获取对话框组的子元素
        var children: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(dialogGroup, kAXChildrenAttribute as CFString, &children)
        guard childrenResult == .success, let childrenArray = children as? [AXUIElement] else {
            return nil
        }
        
        Logger.info("Found \(childrenArray.count) elements in dialog group")
        
        // 遍历所有子元素，查找AXGenericElement类型的消息
        for (index, child) in childrenArray.enumerated() {
            // 获取子元素
            var children2: CFTypeRef?
            let childrenResult2 = AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &children2)
            guard childrenResult2 == .success, let childrenArray2 = children2 as? [AXUIElement] else {
                return nil
            }
            
            if childrenArray2.count<1 {
                continue
            }

            var role: CFTypeRef?
            let roleResult = AXUIElementCopyAttributeValue(childrenArray2[0], kAXRoleAttribute as CFString, &role)
            guard roleResult == .success, let roleString = role as? String else {
                continue
            }
            
            if roleString == "AXGenericElement" {
                // 获取消息描述
                var description: CFTypeRef?
                let descResult = AXUIElementCopyAttributeValue(childrenArray2[0], kAXDescriptionAttribute as CFString, &description)
                if descResult == .success, let descString = description as? String, !descString.isEmpty {
                    Logger.debug("Raw description for message \(index + 1): \(descString)")
                    
                    if let chatMessage = ContentProcessor.shared.parseWhatsAppMessage(descString) {
                        // 过滤时间戳
                        if let messageTimestamp = ChatMessagesUtil.parseTimestamp(chatMessage.timestamp) {
                            let isNewer = messageTimestamp > filterAfterTimestamp
                            Logger.debug("Message timestamp: \(chatMessage.timestamp) -> \(messageTimestamp), is newer: \(isNewer)")
                            if isNewer {
                                messages.append(chatMessage)
                                Logger.info("Append parsed message (newer than \(filterAfterTimestamp)): \(chatMessage)")
                            } else {
                                Logger.info("Skipping message (older than \(filterAfterTimestamp)): \(chatMessage.content.prefix(30))...")
                            }
                        } else {
                            Logger.warn("Failed to parse timestamp for message: '\(chatMessage.timestamp)', including message")
                            messages.append(chatMessage)
                            Logger.info("Append parsed message (timestamp parsing failed): \(chatMessage)")
                        }
                    }
                }
            }
        }
        
        return messages.isEmpty ? nil : messages
    }

    private static func fallback(windowElement: AXUIElement, filterAfterTimestamp: Date? = nil) -> [ChatMessage] {
        var extractedMessages: [ChatMessage] = []

        Logger.info("Fallback to old data structure")

        // Get the chat area element (5th child of first child of first child)
        guard let chatAreaElement = getChatAreaElement(from: windowElement) else {
            Logger.debug("Failed to get chat area element")
            return extractedMessages
        }
        
        // Parse chat messages from the chat area
        parseChatMessagesFromElement(chatAreaElement, messages: &extractedMessages, filterAfterTimestamp: filterAfterTimestamp)
        return extractedMessages
    }
    

    
    /// Get the chat area element from the window
    private static func getChatAreaElement(from windowElement: AXUIElement) -> AXUIElement? {
        // Get the first child of the window
        var firstChild: CFTypeRef?
        let firstChildResult = AXUIElementCopyAttributeValue(windowElement, kAXChildrenAttribute as CFString, &firstChild)
        
        guard firstChildResult == .success, let children = firstChild as? [AXUIElement], children.count > 0 else {
            return nil
        }
        
        let firstChildElement = children[0]
        
        // Get the first child of the first child
        var firstChildOfFirstChild: CFTypeRef?
        let firstChildOfFirstChildResult = AXUIElementCopyAttributeValue(firstChildElement, kAXChildrenAttribute as CFString, &firstChildOfFirstChild)
        
        guard firstChildOfFirstChildResult == .success, let firstChildChildren = firstChildOfFirstChild as? [AXUIElement], firstChildChildren.count > 0 else {
            return nil
        }
        
        let firstChildOfFirstChildElement = firstChildChildren[0]
        
        // Get the fifth child of the first child of the first child
        var fifthChild: CFTypeRef?
        let fifthChildResult = AXUIElementCopyAttributeValue(firstChildOfFirstChildElement, kAXChildrenAttribute as CFString, &fifthChild)
        
        guard fifthChildResult == .success, let fifthChildren = fifthChild as? [AXUIElement], fifthChildren.count >= 5 else {
            return nil
        }
        
        return fifthChildren[4] // Index 4 is the 5th element
    }
    
    /// Parse chat messages from the chat area element
    private static func parseChatMessagesFromElement(_ chatAreaElement: AXUIElement, messages: inout [ChatMessage], filterAfterTimestamp: Date? = nil) {
        // Get children of chat area (should be 2 elements)
        var children: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(chatAreaElement, kAXChildrenAttribute as CFString, &children)
        
        guard childrenResult == .success, let childrenArray = children as? [AXUIElement], childrenArray.count >= 2 else {
            Logger.debug("Chat area doesn't have expected 2 children")
            return
        }
         
        // Parse messages from second child
        parseMessagesFromContentArea(childrenArray[1], messages: &messages, filterAfterTimestamp: filterAfterTimestamp)
         
    } 
    
    /// Parse messages from the content area (second child)
    private static func parseMessagesFromContentArea(_ element: AXUIElement, messages: inout [ChatMessage], filterAfterTimestamp: Date? = nil) {
        // Get the first child of this element
        var firstChild: CFTypeRef?
        let firstChildResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &firstChild)
        guard firstChildResult == .success, let children = firstChild as? [AXUIElement] , children.count>0 else {
            Logger.info("No children found in content area")
            return
        }
        
        var firstChild2: CFTypeRef?
        let firstChildResult2 = AXUIElementCopyAttributeValue(children[0], kAXChildrenAttribute as CFString, &firstChild2)
        guard firstChildResult2 == .success, let children2 = firstChild2 as? [AXUIElement] else {
            Logger.info("No children found in content area2")
            return
        }
        
        Logger.info("Found \(children2.count) elements in content area")
        
        // Get the second child (index 1)
        guard children2.count >= 1 else {
            Logger.info("Not enough children, need at least 1")
            return
        }

        var limtiedChildren = children2
        if children2.count > maxChildrenCount  {
            Logger.warn("WhatsApp: UI tree has \(children2.count) children, limiting to \(maxChildrenCount) to prevent performance issues")
            let limitedChildren = Array(children2.suffix(maxChildrenCount))
        }
         
        // ChatMessagesUtil.printElementTree(children[0])  // Disabled to prevent performance issues
        // Loop through all children, parse each if it's AXGenericElement
        for (index, child) in limtiedChildren.enumerated() {
            var firstChild3: CFTypeRef?
            let firstChildResult3 = AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &firstChild3)
            guard firstChildResult3 == .success, let children3 = firstChild3 as? [AXUIElement] else {
                Logger.info("No children found in content area3")
                continue
            }
            
            if children3.count<1 {
                continue
            }
            
            // Get the role of the child element
            var role: CFTypeRef?
            let roleResult = AXUIElementCopyAttributeValue(children3[0], kAXRoleAttribute as CFString, &role)
            guard roleResult == .success, let roleString = role as? String else {
                Logger.info("Failed to get role for child at index \(index)")
                continue
            }
            Logger.debug("Child \(index + 1) role: \(roleString)")
            
            // Only parse if the role is AXGenericElement
            if roleString == "AXGenericElement" {
                // Get the description attribute (contains message content)
                var description: CFTypeRef?
                let descResult = AXUIElementCopyAttributeValue(children3[0], kAXDescriptionAttribute as CFString, &description)
                if descResult == .success, let descString = description as? String, !descString.isEmpty {
                    Logger.debug("Raw description for child \(index + 1): \(descString)")
                    
                    if let chatMessage = ContentProcessor.shared.parseWhatsAppMessage(descString) {
                        // Filter by timestamp if provided
                        if let filterTimestamp = filterAfterTimestamp {
                            if let messageTimestamp = ChatMessagesUtil.parseTimestamp(chatMessage.timestamp) {
                                let isNewer = messageTimestamp > filterTimestamp
                                Logger.debug("Message timestamp: \(chatMessage.timestamp) -> \(messageTimestamp), is newer: \(isNewer)")
                                if isNewer {
                                    messages.append(chatMessage)
                                    Logger.info("Append parsed message (newer than \(filterTimestamp)): \(chatMessage)")
                                } else {
                                    Logger.debug("Skipping message (older than \(filterTimestamp)): \(chatMessage.content.prefix(30))...")
                                }
                            } else {
                                Logger.warn("Failed to parse timestamp for message: '\(chatMessage.timestamp)', including message")
                                messages.append(chatMessage)
                                Logger.info("Append parsed message (timestamp parsing failed): \(chatMessage)")
                            }
                        } else {
                            // No timestamp filter, include all messages
                            messages.append(chatMessage)
                            Logger.info("Append parsed message: \(chatMessage)")
                        }
                    }
                } else {
                    Logger.debug("No description found for AXGenericElement at child \(index + 1)")
                }
            } else {
                Logger.debug("Child \(index + 1) is not AXGenericElement, role: \(roleString)")
            }
        }
    } 
}
