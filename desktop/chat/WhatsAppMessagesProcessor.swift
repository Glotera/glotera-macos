import Cocoa
import Foundation

/// WhatsApp messages processor using Accessibility API
// Whatsapp Window Element Tree:
// AXWindow:
//   ContentGroup:
//      LeftSideBar:
//      Splitter:
//      SessionList:
//      Splitter:
//      ChatAreaHeader:
//         ContactName:
//         ...
//      ChatAreaContent:
//         AXGroup：
//            Messsage1:
//               Role: AXGenericElement
//               Description: xxx
//            Messsage2:
//               Role: AXGenericElement
//               Description: xxx
//            ...
//         ... // 最下面的输入框等
//         InputBox:
//            InputBoxContent:
//            ...
//   CloseButton:
//   MinimizeButton:
//   FullScrenButton: 
// 前一天debug时，ContentGroup只有5个，ChatAreaHeader和ChatAreaContent是一个元素下面，所以需要获取第5个元素
// 现在ContentGroup有6个，ChatAreaHeader和ChatAreaContent是两个元素，所以需要获取第6个元素
// MARK: 不知道后面还会不会再变
class WhatsAppMessagesProcessor: ChatMessagesProcessor {
    /// Get current chat session ID from WhatsApp
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

        // Start searching from the main window element
        if let contactName = findContactNameInElementTree(windowElement) {
            return contactName
        }
        return nil
    }

    // Traverse the window element tree to find AXButton with Description starting with "‎Start video call with" or "‎Start voice call with"
    private static func findContactNameInElementTree(_ element: AXUIElement) -> String? {
        // Check if element is AXButton
        var roleValue: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        if roleResult == .success, let role = roleValue as? String, role == kAXButtonRole as String {
            // Try to get the description
            var descValue: CFTypeRef?
            let descResult = AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descValue)
            if descResult == .success, let desc = descValue as? String {
                let videoPrefix = "‎Start video call with "
                let voicePrefix = "‎Start voice call with "
                if desc.hasPrefix(videoPrefix) {
                    let contactName = desc.replacingOccurrences(of: videoPrefix, with: "")
                    return contactName
                } else if desc.hasPrefix(voicePrefix) {
                    let contactName = desc.replacingOccurrences(of: voicePrefix, with: "")
                    return contactName
                }
            }
        }
        // Recursively search children
        var children: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        if childrenResult == .success, let childrenArray = children as? [AXUIElement] {
            for child in childrenArray {
                if let found = findContactNameInElementTree(child) {
                    return found
                }
            }
        }
        return nil
    }
    
    /// Extract messages from WhatsApp using Accessibility API
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
        
        // Print the chat area element tree
        Logger.info("=== WhatsApp Chat Area Element Tree ===")
        ChatMessagesUtil.printElementTree(windowElement)
        Logger.info("=== End Chat Area Element Tree ===")

          // Get the first child of the window
        var contentGroupElement: CFTypeRef?
        let contentGroupResult = AXUIElementCopyAttributeValue(windowElement, kAXChildrenAttribute as CFString, &contentGroupElement)
        
        guard contentGroupResult == .success, let children = contentGroupElement as? [AXUIElement], children.count > 0 else {
            return extractedMessages
        }
         
        
        var firstChild: CFTypeRef?
        let firstChildResult = AXUIElementCopyAttributeValue(children[0], kAXChildrenAttribute as CFString, &firstChild)
        
        guard firstChildResult == .success, let children2 = firstChild as? [AXUIElement], children.count > 0 else {
            return extractedMessages
        }
        
        // Get the 5th, 6th child of the first child
        var chatAreaChildren: CFTypeRef?
        let chatAreaResult = AXUIElementCopyAttributeValue(children2[0], kAXChildrenAttribute as CFString, &chatAreaChildren)
        
        //如果不是新的数据结构，尝试老的数据结构
        guard chatAreaResult == .success, let chatAreaChildren = chatAreaChildren as? [AXUIElement], chatAreaChildren.count >= 6 else {
            return fallback(windowElement: windowElement, filterAfterTimestamp: filterAfterTimestamp);
        } 
        
        parseMessagesFromContentArea(chatAreaChildren[5], messages: &extractedMessages, filterAfterTimestamp: filterAfterTimestamp)
        
        Logger.info("Extracted \(extractedMessages.count) messages from WhatsApp")
        return extractedMessages
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
        
        // Parse contact name from first child
        let contactName = parseContactName(from: childrenArray[0])
        Logger.info("=== WhatsApp Chat Parsing ===")
        Logger.info("Contact name: \(contactName)")
 
        // Parse messages from second child
        parseMessagesFromContentArea(childrenArray[1], messages: &messages, filterAfterTimestamp: filterAfterTimestamp)
        
        Logger.info("=== End WhatsApp Chat Parsing ===")
    }
    
    /// Parse contact name from the first child element
    private static func parseContactName(from element: AXUIElement) -> String {
        // Get the first child of this element
        var firstChild: CFTypeRef?
        let firstChildResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &firstChild)
        
        guard firstChildResult == .success, let children = firstChild as? [AXUIElement], children.count > 0 else {
            return "Unknown"
        }
        
        let firstChildElement = children[0]
        
        // Get element role
        var role: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(firstChildElement, kAXRoleAttribute as CFString, &role)
        
        guard roleResult == .success, let roleString = role as? String, roleString == "AXHeading" else {
            return "Unknown"
        }
        
        // Get element description (contains contact name)
        var description: CFTypeRef?
        let descResult = AXUIElementCopyAttributeValue(firstChildElement, kAXDescriptionAttribute as CFString, &description)
        
        if descResult == .success, let descString = description as? String, !descString.isEmpty {
            return descString.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return "Unknown"
    }
    
    /// Parse messages from the content area (second child)
    private static func parseMessagesFromContentArea(_ element: AXUIElement, messages: inout [ChatMessage], filterAfterTimestamp: Date? = nil) {
        // Get the first child of this element
        var firstChild: CFTypeRef?
        let firstChildResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &firstChild)
        guard firstChildResult == .success, let children = firstChild as? [AXUIElement] else {
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
         
        // Loop through all children, parse each if it's AXGenericElement
        for (index, child) in children2.enumerated() {
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
