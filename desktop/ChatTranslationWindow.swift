import Cocoa
import SwiftUI

/// Chat message data model
struct ChatMessage: Identifiable {
    let id = UUID()
    let sender: String
    let content: String
    let timestamp: String
    let isFromMe: Bool
}

/// Chat translation floating window that appears next to IM applications
class ChatTranslationWindow: NSWindow {
    private var hostingView: NSHostingView<ChatTranslationView>?
    private var chatTranslationView: ChatTranslationView?
    private var currentAppInfo: AppInfo?
    private var windowPosition: NSPoint = .zero
    private var isUserMoved: Bool = false
    private var appName: String = ""
    private var messages: [ChatMessage] = []
    private var messageUpdateTimer: Timer?
    
    init() {
        // Initial window size for chat translation
        let initialSize = NSSize(width: 400, height: 600)
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: initialSize.width, height: initialSize.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = NSColor.clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.isReleasedWhenClosed = false
        
        setupContent()
        setupWindowBehavior()
        
        // Register with SimpleMemoryManager
        SimpleMemoryManager.shared.registerWindow(self)
    }
    
    private func setupContent() {
        chatTranslationView = ChatTranslationView(
            appName: appName,
            messages: messages,
            onClose: { [weak self] in
                self?.hideWindow()
            }
        )
        
        hostingView = NSHostingView(rootView: chatTranslationView!)
        self.contentView = hostingView
    }
    
    private func setupWindowBehavior() {
        // Make window stay on top of other windows
        self.level = .floating
        
        // Enable window dragging
        self.isMovableByWindowBackground = true
        
        // Track window movement to detect user interaction
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove),
            name: NSWindow.didMoveNotification,
            object: self
        )
    }
    
    @objc private func windowDidMove() {
        isUserMoved = true
        windowPosition = self.frame.origin
    }
    
    /// Show the window next to the specified application
    func showNextToApp(_ appInfo: AppInfo) {
        currentAppInfo = appInfo
        appName = appInfo.appName
        
        // Reset user movement state when switching to a new app
        isUserMoved = false
        
        // Clear previous messages
        messages = []
        
        // Update the view with app information by recreating it
        updateChatTranslationView()
        
        // Position window next to the IM application
        positionWindowNextToApp()
        
        // Show the window
        self.makeKeyAndOrderFront(nil)
        
        // Start monitoring messages if it's WhatsApp
        if appInfo.bundleId == "net.whatsapp.WhatsApp" {
            startMessageMonitoring()
        }
        
        Logger.info("Chat translation window shown for app: \(appInfo.appName)")
    }
    
    /// Hide the window
    func hideWindow() {
        // Stop message monitoring
        stopMessageMonitoring()
        
        self.orderOut(nil)
        Logger.info("Chat translation window hidden")
    }
    
    /// Update the chat translation view with current app name and messages
    private func updateChatTranslationView() {
        chatTranslationView = ChatTranslationView(
            appName: appName,
            messages: messages,
            onClose: { [weak self] in
                self?.hideWindow()
            }
        )
        
        hostingView = NSHostingView(rootView: chatTranslationView!)
        self.contentView = hostingView
    }
    
    /// Position the window next to the IM application
    private func positionWindowNextToApp() {
        guard currentAppInfo != nil else { return }
        
        // Get the active application window
        if let activeApp = NSWorkspace.shared.frontmostApplication {
            
            // Try to get the main window of the active application using Accessibility API
            if let appWindowFrame = getMainWindowFrameForApplication(activeApp) {
                
                let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
                let windowFrame = self.frame
                
                // If user hasn't manually moved the window, position it automatically
                if !isUserMoved {
                    // Calculate position to the right of the chat application window
                    var newX = appWindowFrame.maxX + 10 // 10px gap from the chat window
                    var newY = appWindowFrame.origin.y + (appWindowFrame.height - windowFrame.height) / 2 // Align vertically
                    
                    // Ensure the floating window doesn't go off screen
                    if newX + windowFrame.width > screenFrame.maxX {
                        // If it would go off the right edge, position it to the left of the chat window
                        newX = appWindowFrame.origin.x - windowFrame.width - 10
                    }
                    
                    if newY + windowFrame.height > screenFrame.maxY {
                        // If it would go off the top, adjust to fit
                        newY = screenFrame.maxY - windowFrame.height - 20
                    }
                    
                    if newY < screenFrame.origin.y {
                        // If it would go off the bottom, adjust to fit
                        newY = screenFrame.origin.y + 20
                    }
                    
                    // Animate the position change for smooth movement
                    NSAnimationContext.runAnimationGroup({ context in
                        context.duration = 0.2
                        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                        self.animator().setFrameOrigin(NSPoint(x: newX, y: newY))
                    }) {
                        self.windowPosition = self.frame.origin
                    }
                }
            } else {
                // Fallback positioning if we can't get the app window
                Logger.debug("Using fallback positioning for app: \(activeApp.localizedName ?? "Unknown")")
                positionWindowWithFallback()
            }
        }
    }
    
    /// Fallback positioning method when Accessibility API fails
    private func positionWindowWithFallback() {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
        let windowFrame = self.frame
        
        // Position window to the right side of the screen
        let newX = screenFrame.maxX - windowFrame.width - 20
        let newY = screenFrame.maxY - windowFrame.height - 100
        
        // Animate the position change for smooth movement
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrameOrigin(NSPoint(x: newX, y: newY))
        }) {
            self.windowPosition = self.frame.origin
        }
    }
    
    /// Get the main window frame for an application using Accessibility API
    private func getMainWindowFrameForApplication(_ app: NSRunningApplication) -> NSRect? {
        let pid = app.processIdentifier
        
        // Create accessibility element for the application
        let appElement = AXUIElementCreateApplication(pid)
        
        // Get the main window
        var mainWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindow)
        
        guard result == .success, let mainWindow = mainWindow else {
            Logger.debug("Failed to get main window for app: \(app.localizedName ?? "Unknown")")
            return nil
        }
        
        let windowElement = mainWindow as! AXUIElement
        
        // Get window position and size
        var position: CFTypeRef?
        var size: CFTypeRef?
        
        let posResult = AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &position)
        let sizeResult = AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &size)
        
        guard posResult == .success, sizeResult == .success else {
            Logger.debug("Failed to get window position or size for app: \(app.localizedName ?? "Unknown")")
            return nil
        }
        
        // Safely convert position and size values
        guard let posValue = position as? CGPoint,
              let sizeValue = size as? CGSize else {
            Logger.debug("Failed to convert position or size values for app: \(app.localizedName ?? "Unknown")")
            return nil
        }
        
        // Convert to screen coordinates
        let windowFrame = NSRect(origin: posValue, size: sizeValue)
        
        // Convert from accessibility coordinates to screen coordinates
        // Accessibility coordinates have origin at bottom-left, screen coordinates have origin at top-left
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let convertedOrigin = NSPoint(x: windowFrame.origin.x, y: screenHeight - windowFrame.origin.y - windowFrame.height)
        
        return NSRect(origin: convertedOrigin, size: windowFrame.size)
    }
    
    /// Update window position when IM application window changes
    func updatePosition() {
        guard currentAppInfo != nil else { return }
        
        // Only auto-position if user hasn't manually moved the window
        if !isUserMoved {
            positionWindowNextToApp()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stopMessageMonitoring()
        Logger.info("ChatTranslationWindow deallocating")
    }
    
    // MARK: - Message Monitoring
    
    /// Start monitoring WhatsApp messages
    private func startMessageMonitoring() {
        // Stop any existing timer
        stopMessageMonitoring()
        
        // Start a timer to periodically check for new messages
        messageUpdateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.fetchWhatsAppMessages()
        }
        
        // Fetch messages immediately
        fetchWhatsAppMessages()
        
        Logger.info("Started WhatsApp message monitoring")
    }
    
    /// Stop monitoring WhatsApp messages
    private func stopMessageMonitoring() {
        messageUpdateTimer?.invalidate()
        messageUpdateTimer = nil
        Logger.info("Stopped WhatsApp message monitoring")
    }
    
    /// Fetch WhatsApp messages using Accessibility API
    private func fetchWhatsAppMessages() {
        guard let activeApp = NSWorkspace.shared.frontmostApplication,
              activeApp.bundleIdentifier == "net.whatsapp.WhatsApp" else {
            return
        }
        
        let newMessages = extractWhatsAppMessages(from: activeApp)
        
        // Update messages if there are new ones
        if newMessages.count != messages.count {
            messages = newMessages
            updateChatTranslationView()
            Logger.info("Updated WhatsApp messages: \(messages.count) messages")
        }
    }
    
    /// Extract messages from WhatsApp using Accessibility API
    private func extractWhatsAppMessages(from app: NSRunningApplication) -> [ChatMessage] {
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
        printChatAreaElementTree(windowElement)
        Logger.info("=== End Chat Area Element Tree ===")
        
        // Get the chat area element (5th child of first child of first child)
        guard let chatAreaElement = getChatAreaElement(from: windowElement) else {
            Logger.debug("Failed to get chat area element")
            return extractedMessages
        }
        
        // Parse chat messages from the chat area
        parseChatMessagesFromElement(chatAreaElement, messages: &extractedMessages)
        
        Logger.info("Extracted \(extractedMessages.count) messages from WhatsApp")
        return extractedMessages
    }
    
    /// Recursively extract messages from UI elements
    private func extractMessagesFromElement(_ element: AXUIElement, messages: inout [ChatMessage]) {
        // Get children elements
        var children: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        
        guard childrenResult == .success, let childrenArray = children as? [AXUIElement] else {
            return
        }
        
        let messageElementParent = childrenArray[0]
        var firstChild: CFTypeRef?
        let firstChildResult = AXUIElementCopyAttributeValue(messageElementParent, kAXChildrenAttribute as CFString, &firstChild)
        guard firstChildResult == .success, let firstChildArray = firstChild as? [AXUIElement], firstChildArray.count > 0 else {
            return
        }

        let messageElements = firstChildArray[0]
        // Check if this element contains message content
        if let message = extractMessageFromElement(messageElements) {
            messages.append(message)
        }
         
        
    }
    
    /// Extract a single message from an element
    private func extractMessageFromElement(_ element: AXUIElement) -> ChatMessage? {
        // Get element role
        var role: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        
        guard roleResult == .success, let roleString = role as? String else {
            return nil
        }
        
        // Look for text elements that might contain messages
        if roleString == "AXStaticText" || roleString == "AXText" {
            // Get the text content
            var value: CFTypeRef?
            let valueResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
            
            if valueResult == .success, let text = value as? String, !text.isEmpty {
                // Try to parse the message
                return parseWhatsAppMessage(text)
            }
        }
        
        return nil
    }
    
    /// Print the chat area element tree for debugging
    private func printChatAreaElementTree(_ windowElement: AXUIElement) {
        // Get the first child of the window
        var firstChild: CFTypeRef?
        let firstChildResult = AXUIElementCopyAttributeValue(windowElement, kAXChildrenAttribute as CFString, &firstChild)
        
        guard firstChildResult == .success, let children = firstChild as? [AXUIElement], children.count > 0 else {
            Logger.info("Failed to get first child of window")
            return
        }
        
        let firstChildElement = children[0]
        Logger.info("Window first child:")
        printElementInfo(firstChildElement, depth: 1)
        
        // Get the first child of the first child
        var firstChildOfFirstChild: CFTypeRef?
        let firstChildOfFirstChildResult = AXUIElementCopyAttributeValue(firstChildElement, kAXChildrenAttribute as CFString, &firstChildOfFirstChild)
        
        guard firstChildOfFirstChildResult == .success, let firstChildChildren = firstChildOfFirstChild as? [AXUIElement], firstChildChildren.count > 0 else {
            let availableCount = (firstChildOfFirstChild as? [AXUIElement])?.count ?? 0
            Logger.info("Failed to get first child of first child (available: \(availableCount))")
            return
        }
        
        let firstChildOfFirstChildElement = firstChildChildren[0]
        Logger.info("First child of first child:")
        printElementInfo(firstChildOfFirstChildElement, depth: 2)
        
        // Get the fifth child of the first child of the first child
        var fifthChild: CFTypeRef?
        let fifthChildResult = AXUIElementCopyAttributeValue(firstChildOfFirstChildElement, kAXChildrenAttribute as CFString, &fifthChild)
        
        guard fifthChildResult == .success, let fifthChildren = fifthChild as? [AXUIElement], fifthChildren.count >= 5 else {
            let availableCount = (fifthChild as? [AXUIElement])?.count ?? 0
            Logger.info("Failed to get fifth child of first child of first child (available: \(availableCount))")
            return
        }
        
        let chatAreaElement = fifthChildren[4] // Index 4 is the 5th element
        Logger.info("Chat area (5th child of first child of first child):")
        printElementTree(chatAreaElement, depth: 2)
    }
    
    /// Print element information
    private func printElementInfo(_ element: AXUIElement, depth: Int) {
        let indent = String(repeating: "  ", count: depth)
        
        // Get element role
        var role: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let roleString = (roleResult == .success) ? (role as? String ?? "unknown") : "unknown"
        
        // Get element title
        var title: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
        let titleString = (titleResult == .success) ? (title as? String ?? "no title") : "no title"
        
        // Get element value
        var value: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        let valueString = (valueResult == .success) ? (value as? String ?? "no value") : "no value"
        
        // Get element description
        var description: CFTypeRef?
        let descResult = AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &description)
        let descString = (descResult == .success) ? (description as? String ?? "no description") : "no description"
        
        // Print element info
        Logger.info("\(indent)Role: \(roleString)")
        if titleString != "no title" && !titleString.isEmpty {
            Logger.info("\(indent)Title: \(titleString)")
        }
        if valueString != "no value" && !valueString.isEmpty {
            Logger.info("\(indent)Value: \(valueString)")
        }
        if descString != "no description" && !descString.isEmpty {
            Logger.info("\(indent)Description: \(descString)")
        }
        
        // Get children count
        var children: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        
        if childrenResult == .success, let childrenArray = children as? [AXUIElement] {
            Logger.info("\(indent)Children count: \(childrenArray.count)")
        } else {
            Logger.info("\(indent)No children")
        }
        
        Logger.info("\(indent)---")
    }
    
    /// Print the entire element tree for debugging
    private func printElementTree(_ element: AXUIElement, depth: Int) {
        let indent = String(repeating: "  ", count: depth)
        
        // Get element role
        var role: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let roleString = (roleResult == .success) ? (role as? String ?? "unknown") : "unknown"
        
        // Get element title
        var title: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
        let titleString = (titleResult == .success) ? (title as? String ?? "no title") : "no title"
        
        // Get element value
        var value: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        let valueString = (valueResult == .success) ? (value as? String ?? "no value") : "no value"
        
        // Get element description
        var description: CFTypeRef?
        let descResult = AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &description)
        let descString = (descResult == .success) ? (description as? String ?? "no description") : "no description"
        
        // Print element info
        Logger.info("\(indent)Role: \(roleString)")
        if titleString != "no title" && !titleString.isEmpty {
            Logger.info("\(indent)Title: \(titleString)")
        }
        if valueString != "no value" && !valueString.isEmpty {
            Logger.info("\(indent)Value: \(valueString)")
        }
        if descString != "no description" && !descString.isEmpty {
            Logger.info("\(indent)Description: \(descString)")
        }
        
        // Get children
        var children: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        
        if childrenResult == .success, let childrenArray = children as? [AXUIElement] {
            Logger.info("\(indent)Children count: \(childrenArray.count)")
            
            // Limit the depth to avoid infinite recursion and too much output
            if depth < 10 {
                for (index, child) in childrenArray.enumerated() {
                    Logger.info("\(indent)Child \(index + 1):")
                    printElementTree(child, depth: depth + 1)
                }
            } else {
                Logger.info("\(indent)Max depth reached, skipping children")
            }
        } else {
            Logger.info("\(indent)No children")
        }
        
        Logger.info("\(indent)---")
    }
    
    /// Parse WhatsApp message text to extract sender, content, and timestamp
    private func parseWhatsAppMessage(_ text: String) -> ChatMessage? {
        // WhatsApp message patterns
        // Pattern 1: "Sender Name\nMessage content"
        // Pattern 2: "Sender Name\nTime\nMessage content"
        // Pattern 3: "You\nMessage content" (for own messages)
        
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        
        guard lines.count >= 2 else {
            return nil
        }
        
        let sender = lines[0].trimmingCharacters(in: .whitespaces)
        let content = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespaces)
        
        // Determine if it's from the user
        let isFromMe = sender.lowercased() == "you" || sender.lowercased() == "你"
        
        // Extract timestamp if available (look for time pattern in the second line)
        var timestamp = ""
        if lines.count >= 2 {
            let secondLine = lines[1]
            if secondLine.matches(of: #/\d{1,2}:\d{2}/#).count > 0 {
                timestamp = secondLine
            }
        }
        
        // Only create message if we have valid content
        guard !content.isEmpty else {
            return nil
        }
        
        return ChatMessage(
            sender: sender,
            content: content,
            timestamp: timestamp,
            isFromMe: isFromMe
        )
    }
    
    // MARK: - WhatsApp Chat Parsing
    
    /// Get the chat area element from the window
    private func getChatAreaElement(from windowElement: AXUIElement) -> AXUIElement? {
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
    private func parseChatMessagesFromElement(_ chatAreaElement: AXUIElement, messages: inout [ChatMessage]) {
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
        Logger.info("---")
        
        // Parse messages from second child
        parseMessagesFromContentArea(childrenArray[1], contactName: contactName, messages: &messages)
        
        Logger.info("=== End WhatsApp Chat Parsing ===")
    }
    
    /// Parse contact name from the first child element
    private func parseContactName(from element: AXUIElement) -> String {
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
    private func parseMessagesFromContentArea(_ element: AXUIElement, contactName: String, messages: inout [ChatMessage]) {
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
            Logger.info("Child \(index + 1) role: \(roleString)")
            
            // Only parse if the role is AXGenericElement
            if roleString == "AXGenericElement" {
                // Get the description attribute (contains message content)
                var description: CFTypeRef?
                let descResult = AXUIElementCopyAttributeValue(children3[0], kAXDescriptionAttribute as CFString, &description)
                if descResult == .success, let descString = description as? String, !descString.isEmpty {
                    Logger.info("Raw description for child \(index + 1): \(descString)")
                    
                    // Parse the message content (separated by U+200E)
                    let messageParts = descString.components(separatedBy: "\u{200E}")
                    Logger.info("Message parts count for child \(index + 1): \(messageParts.count)")
                    
                    for (partIndex, part) in messageParts.enumerated() {
                        if !part.isEmpty {
                            Logger.info("Part \(partIndex + 1) of child \(index + 1): \(part)")
                            if let message = parseMessageContent(part, contactName: contactName) {
                                messages.append(message)
                                Logger.info("✅ Parsed message: [\(message.sender)] \(message.content) (\(message.timestamp))")
                            } else {
                                Logger.info("❌ Failed to parse message from part: \(part)")
                            }
                        }
                    }
                } else {
                    Logger.info("No description found for AXGenericElement at child \(index + 1)")
                }
            } else {
                Logger.info("Child \(index + 1) is not AXGenericElement, role: \(roleString)")
            }
        }
           
    }
    
    /// Parse message content from the description string
    private func parseMessageContent(_ content: String, contactName: String) -> ChatMessage? {
        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !cleanContent.isEmpty else {
            Logger.info("Empty content, skipping")
            return nil
        }
        
        Logger.info("Parsing content: \(cleanContent)")
        
        // Try to extract timestamp and message content
        // WhatsApp format: "Message content\nTime" or just "Message content"
        let lines = cleanContent.components(separatedBy: .newlines).filter { !$0.isEmpty }
        Logger.info("Lines count: \(lines.count)")
        
        var messageContent = cleanContent
        var timestamp = ""
        
        // If there are multiple lines, the last line might be timestamp
        if lines.count > 1 {
            messageContent = lines.dropLast().joined(separator: "\n")
            timestamp = lines.last ?? ""
            Logger.info("Extracted timestamp: \(timestamp)")
        }
        
        // Determine if it's from the user (You) or contact
        let isFromMe = messageContent.contains("You") || messageContent.contains("你")
        Logger.info("Is from me: \(isFromMe)")
        
        let sender = isFromMe ? "You" : contactName
        Logger.info("Sender: \(sender)")
        Logger.info("Message content: \(messageContent)")
        
        return ChatMessage(
            sender: sender,
            content: messageContent,
            timestamp: timestamp,
            isFromMe: isFromMe
        )
    }
}

/// SwiftUI view for chat translation window content
struct ChatTranslationView: View {
    let appName: String
    let messages: [ChatMessage]
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Glotera AI")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                if !appName.isEmpty {
                    Text("- \(appName)")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Messages area
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if messages.isEmpty {
                        VStack {
                            Spacer()
                            
                            Text("Chat translation feature is active")
                                .font(.body)
                                .foregroundColor(.secondary)
                            
                            Text("Messages will appear here when detected")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ForEach(messages, id: \.id) { message in
                            MessageView(message: message)
                        }
                    }
                }
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 400, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }
}

/// Individual message view
struct MessageView: View {
    let message: ChatMessage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.sender)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(message.timestamp)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Text(message.content)
                .font(.body)
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }
} 
