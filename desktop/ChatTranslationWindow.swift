import Cocoa
import SwiftUI



/// Chat translation floating window that appears next to IM applications
class ChatTranslationWindow: NSWindow {
    private var hostingView: NSHostingView<ChatTranslationView>?
    private var chatTranslationData: ChatTranslationData?
    private var currentAppInfo: AppInfo?
    private var windowPosition: NSPoint = .zero
    private var isUserMoved: Bool = false
    private var appName: String = ""
    private var messages: [ChatMessage] = []
    private var messageUpdateTimer: Timer?
    private var messageHashes: Set<String> = [] // Track existing message hashes for deduplication
    private let maxMessagesLimit = 100 // Limit total messages to prevent memory issues
    private var currentSessionId: String = "default"
    private var lastMessageTimestamp: Date?
    private var isFetchingMessages: Bool = false // Track if fetchWhatsAppMessages is currently running
    
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
        
        // Start message monitoring once during initialization
        startMessageMonitoring()
        
        // Register with SimpleMemoryManager
        SimpleMemoryManager.shared.registerWindow(self)
    }
    
    private func setupContent() {
        // Initialize the content using updateChatTranslationView
        updateChatTranslationView()
    }
    
    private func setupWindowBehavior() {
        // Make window stay on top of other windows
        self.level = .floating
        
        // Enable window dragging, but we'll control it more precisely
        self.isMovableByWindowBackground = true
        
        // Track window movement to detect user interaction
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove),
            name: NSWindow.didMoveNotification,
            object: self
        )
        
        // Override mouse tracking behavior
        self.acceptsMouseMovedEvents = false
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
        
        // Update the view with app information
        updateChatTranslationView()
        
        // Position window next to the IM application
        positionWindowNextToApp()
        
        // Show the window
        self.makeKeyAndOrderFront(nil)
        
        Logger.info("Chat translation window shown for app: \(appInfo.appName)")
    }
    
    /// Load recent messages from database
    private func loadRecentMessagesFromDatabase() {
        let dbManager = MessageDatabaseManager.shared
        
        // Clear current messages before loading from database
        messages.removeAll()
        messageHashes.removeAll()
        
        let recentRecords = dbManager.getRecentMessages(forApp: "WhatsApp", sessionId: currentSessionId, limit: 50)
        
        Logger.info("Loading \(recentRecords.count) recent messages from database for session: \(currentSessionId)")
        
        for record in recentRecords {
            // Convert database record to ChatMessage with translation fields
            let message = ChatMessage(
                sender: record.sender,
                content: record.content,
                timestamp: formatTimestamp(record.contentTimestamp),
                isFromMe: record.sender == "You",
                contentTranslation: record.contentTranslation,
                contentLanguage: record.contentLanguage,
                contentTranslationLanguage: record.contentTranslationLanguage,
                contentHash: record.contentHash
            )
             
            // Add to messages array and tracking set
            messages.append(message)
            messageHashes.insert(message.messageHash)
        }
        
        // Get the timestamp of the last message for filtering new messages
        lastMessageTimestamp = dbManager.getLastMessageTimestamp(forApp: "WhatsApp", sessionId: currentSessionId)
        if let lastTimestamp = lastMessageTimestamp {
            Logger.info("Last message timestamp for session \(currentSessionId): \(lastTimestamp)")
        } else {
            Logger.info("No previous messages found for session \(currentSessionId)")
        }
        
        // Update UI after loading messages
        updateChatTranslationView()
    }
    
    /// Format timestamp from Date to string
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMMM d, HH:mm"
        return formatter.string(from: date)
    }
    
    /// Hide the window
    func hideWindow() {
        // Clear the data model
        chatTranslationData?.clear()
        
        self.orderOut(nil)
        Logger.info("Chat translation window hidden")
    }
    
    /// Update the chat translation view with current app name and messages
    private func updateChatTranslationView() {
        // Initialize data and view only once
        if chatTranslationData == nil {
            chatTranslationData = ChatTranslationData()
            
            let chatView = ChatTranslationView(
                data: chatTranslationData!,
                onClose: { [weak self] in
                    self?.hideWindow()
                }
            )
            
            hostingView = NSHostingView(rootView: chatView)
            self.contentView = hostingView
        }
        
        // Update data instead of recreating the view
        chatTranslationData?.updateData(appName: appName, sessionId: currentSessionId, messages: messages)
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
            // Check if position actually needs updating to avoid unnecessary moves
            let currentPosition = self.frame.origin
            
            // Store current position before calculating new one
            let oldWindowPosition = windowPosition
            
            // Calculate what the new position should be
            positionWindowNextToApp()
            
            // Only apply position if it actually changed significantly (more than 10 pixels)
            let deltaX = abs(currentPosition.x - windowPosition.x)
            let deltaY = abs(currentPosition.y - windowPosition.y)
            
            if deltaX < 10 && deltaY < 10 {
                // Position hasn't changed significantly, restore old position to avoid flicker
                windowPosition = oldWindowPosition
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stopMessageMonitoring()
        Logger.info("ChatTranslationWindow deallocating")
    }
 
    /// Start monitoring WhatsApp messages
    private func startMessageMonitoring() {
        // Start a timer to periodically check for new messages
        messageUpdateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.fetchWhatsAppMessages()
        }
        
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
        // Check if already fetching messages to prevent overlapping executions
        guard !isFetchingMessages else {
            Logger.debug("Skipping fetchWhatsAppMessages - previous execution still in progress")
            return
        }
        
        guard let activeApp = NSWorkspace.shared.frontmostApplication,
              activeApp.bundleIdentifier == "net.whatsapp.WhatsApp" else {
            return
        }
        
        Logger.info("Start to fetch Whatsapp messages ...")
        
        // Set fetching flag to prevent overlapping executions
        isFetchingMessages = true
        

        // Check if chat session has changed
        if let newSessionId = getCurrentChatSessionId() {
            Logger.info("Current session ID: \(currentSessionId), new session ID: \(newSessionId)")
            if newSessionId != currentSessionId {
                Logger.info("Chat session changed from '\(currentSessionId)' to '\(newSessionId)'")
                currentSessionId = newSessionId
                loadRecentMessagesFromDatabase()
            }
        }
        
        // If lastMessageTimestamp is nil, try to get it from database to avoid re-processing history
        if lastMessageTimestamp == nil {
            let dbManager = MessageDatabaseManager.shared
            lastMessageTimestamp = dbManager.getLastMessageTimestamp(forApp: "WhatsApp", sessionId: currentSessionId)
            if let lastTimestamp = lastMessageTimestamp {
                Logger.info("Set lastMessageTimestamp from database: \(lastTimestamp)")
            } else {
                Logger.info("No previous messages found in database for session: \(currentSessionId)")
            }
        }

        // Extract messages from WhatsApp with timestamp filtering
        let extractedMessages = extractWhatsAppMessages(from: activeApp, filterAfterTimestamp: lastMessageTimestamp)
         
        
        // Only process if there are actually new messages
        if !extractedMessages.isEmpty {
            Logger.info("Found \(extractedMessages.count) new messages")
            
            // Process messages with translation in background
            Task {
                await self.processNewMessages(extractedMessages)
                // Reset fetching flag after processing is complete
                await MainActor.run {
                    self.isFetchingMessages = false
                }
            }
        } else {
            // Reset fetching flag if no new messages to process
            isFetchingMessages = false
        }
        // Do absolutely nothing if no new messages - no logging, no updates, nothing
    }
    
    /// Process new messages with translation
    private func processNewMessages(_ newMessages: [ChatMessage]) async {
        let dbManager = MessageDatabaseManager.shared
        
        // Show translation indicator
        await MainActor.run {
            chatTranslationData?.setTranslating(true)
        }
        
        for message in newMessages {
            // Calculate content hash
            let contentHash = dbManager.calculateContentHash(message.content)
            
            var finalTranslation: String?
            var finalLanguage: String?
            var finalTranslationLanguage: String?
            
            // Check if message already exists in database
            Logger.debug("Checking database for message with content hash: \(contentHash)")
            if let existingRecord = dbManager.getMessage(byContentHash: contentHash) {
                // Use existing translation
                finalTranslation = existingRecord.contentTranslation
                finalLanguage = existingRecord.contentLanguage
                finalTranslationLanguage = existingRecord.contentTranslationLanguage
                
                Logger.info("Found existing translation for message: \(message.content.prefix(30))...")
            } else {
                Logger.info("No existing translation found, will translate message: \(message.content.prefix(30))...")
                // Detect language and translate， 不需要检测原始语言是什么，LLM会返回结果
//                let detectedLanguage = detectLanguage(message.content)
//                finalLanguage = detectedLanguage
                
                // Always translate to user's preferred language
                let targetLanguage = getUserPreferredLanguage()
                finalTranslationLanguage = targetLanguage
                
                // Translate message using non-streaming mode
                do {
                    let translationResult = try await translateMessage(message.content, to: targetLanguage) 
                    finalLanguage = translationResult.fromLanguage ?? ""
                    finalTranslation = translationResult.translated
                    
                    Logger.info("Translated message: \(message.content.prefix(30))... -> \(translationResult.translated.prefix(30))...")
                    Logger.info("Detected source language: \(finalLanguage)")
                
                    // Save to database
                    let timestamp = parseTimestamp(message.timestamp) ?? Date()
                    let messageRecord = MessageRecord(
                        sender: message.sender,
                        content: message.content,
                        contentHash: contentHash,
                        contentLanguage: finalLanguage ?? "",
                        contentTranslation: finalTranslation ?? "",
                        contentTranslationLanguage: targetLanguage,
                        contentTimestamp: timestamp,
                        chatApp: "WhatsApp",
                        sessionId: currentSessionId
                    )
                    
                    _ = dbManager.insertMessage(messageRecord)
                    
                    // Update lastMessageTimestamp after successful insertion
                    lastMessageTimestamp = timestamp
                    Logger.debug("Updated lastMessageTimestamp to: \(timestamp)")
                } catch {
                    Logger.error("Failed to translate message: \(error)")
                    finalTranslation = "[Translation failed]"
                }
            }
            
            // Create processed message with all translation fields
            let processedMessage = ChatMessage(
                sender: message.sender,
                content: message.content,
                timestamp: message.timestamp,
                isFromMe: message.isFromMe,
                contentTranslation: finalTranslation,
                contentLanguage: finalLanguage,
                contentTranslationLanguage: finalTranslationLanguage,
                contentHash: contentHash
            )
            
            // Add to messages array maintaining chronological order
            messages.append(processedMessage) 
            
            // Keep messages within limit
            if messages.count > maxMessagesLimit {
                messages.removeFirst() 
            }
            
            // Update UI immediately after each message is processed
            await MainActor.run {
                self.updateChatTranslationView()
            }
        }
        
        // Hide translation indicator after all messages are processed
        await MainActor.run {
            chatTranslationData?.setTranslating(false)
        }
    }
    
    /// Get user's preferred language for translation
    private func getUserPreferredLanguage() -> String {
        // Check system locale to determine user's preferred language
        let locale = Locale.current
        let languageCode = locale.language.languageCode?.identifier ?? "en"
        
        // Map common language codes to our supported languages
        switch languageCode {
        case "zh", "zh-Hans", "zh-Hant":
            return "zh"
        case "en":
            return "en"
        case "ja":
            return "ja"
        case "ko":
            return "ko"
        case "es":
            return "es"
        case "fr":
            return "fr"
        case "de":
            return "de"
        case "it":
            return "it"
        case "pt":
            return "pt"
        case "ru":
            return "ru"
        default:
            // Default to English if language not supported
            return "en"
        }
    }
    
    /// Detect language of text (simple heuristic)
//    private func detectLanguage(_ text: String) -> String {
//        // Simple detection: check for Chinese characters
//        let chineseRange = text.range(of: "\\p{Han}", options: .regularExpression)
//        return chineseRange != nil ? "zh" : "en"
//    }
    
    /// Translate message using TranslatorClient
    private func translateMessage(_ text: String, to language: String) async throws -> TranslationResult {
        return try await withCheckedThrowingContinuation { continuation in
            TranslatorClient.shared.translate(text: text, to: language) { result in
                switch result {
                case .success(let translationResult):
                    continuation.resume(returning: translationResult)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Compare two chat messages for chronological ordering using timestamp field
    private func compareMessages(_ message1: ChatMessage, _ message2: ChatMessage) -> Bool {
        // If both have timestamps, parse and compare them properly
        if !message1.timestamp.isEmpty && !message2.timestamp.isEmpty {
            let date1 = parseTimestamp(message1.timestamp)
            let date2 = parseTimestamp(message2.timestamp)
            
            if let d1 = date1, let d2 = date2 {
                Logger.debug("Comparing timestamps: '\(message1.timestamp)' vs '\(message2.timestamp)' -> \(d1 < d2)")
                return d1 < d2
            }
            
            // Fallback to string comparison if parsing fails
            Logger.debug("Timestamp parsing failed, using string comparison: '\(message1.timestamp)' vs '\(message2.timestamp)'")
            return message1.timestamp < message2.timestamp
        }
        
        // If only one has timestamp, prioritize the one with timestamp
        if !message1.timestamp.isEmpty && message2.timestamp.isEmpty {
            return true  // message1 comes first
        }
        if message1.timestamp.isEmpty && !message2.timestamp.isEmpty {
            return false // message2 comes first
        }
        
        // If neither has timestamp, maintain insertion order (new messages at the end)
        return false
    }
    
    /// Parse timestamp string into Date object for proper comparison
    /// Expected format: "July 30, 14:30" or "July 30, 02:30"
    private func parseTimestamp(_ timestamp: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        
        // Try different timestamp formats
        let formats = [
            "MMMM d, HH:mm",    // "July 30, 14:30"
            "MMMM d, H:mm",     // "July 30, 2:30"
            "MMM d, HH:mm",     // "Jul 30, 14:30"
            "MMM d, H:mm",      // "Jul 30, 2:30"
            "yyyy-MM-dd HH:mm", // "2024-07-30 14:30"
            "dd/MM/yyyy HH:mm", // "30/07/2024 14:30"
            "MM/dd/yyyy HH:mm"  // "07/30/2024 14:30"
        ]
        
        let currentYear = Calendar.current.component(.year, from: Date())
        
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: timestamp) {
                // If the parsed date doesn't have a year (month/day only), add current year
                let calendar = Calendar.current
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                
                // Check if year is reasonable (not 1, 2000, or nil)
                let year = components.year ?? 1
                if year < 2020 {
                    // Date without year or with invalid year, add current year
                    var newComponents = components
                    newComponents.year = currentYear
                    if let dateWithYear = calendar.date(from: newComponents) {
                        Logger.debug("Parsed timestamp '\(timestamp)' as \(dateWithYear) (added current year)")
                        return dateWithYear
                    }
                }
                
                Logger.debug("Parsed timestamp '\(timestamp)' as \(date)")
                return date
            }
        }
        
        Logger.warn("Failed to parse timestamp: '\(timestamp)'")
        return nil
    }
    
    /// Get current chat session ID from WhatsApp
    private func getCurrentChatSessionId() -> String? {
        guard let activeApp = NSWorkspace.shared.frontmostApplication,
              activeApp.bundleIdentifier == "net.whatsapp.WhatsApp" else {
            return nil
        }
        
        let pid = activeApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        
        // Get the main window
        var mainWindow: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindow)
        
        guard windowResult == .success, let window = mainWindow else {
            return nil
        }
        
        let windowElement = window as! AXUIElement
        
        // Get the chat area element
        guard let chatAreaElement = getChatAreaElement(from: windowElement) else {
            return nil
        }
        
        // Get children of chat area (should be 2 elements)
        var children: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(chatAreaElement, kAXChildrenAttribute as CFString, &children)
        
        guard childrenResult == .success, let childrenArray = children as? [AXUIElement], childrenArray.count >= 2 else {
            return nil
        }
        
        // Parse contact name from first child
        return parseContactName(from: childrenArray[0])
    }
    
    /// Extract messages from WhatsApp using Accessibility API
    private func extractWhatsAppMessages(from app: NSRunningApplication, filterAfterTimestamp: Date? = nil) -> [ChatMessage] {
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
        // Logger.info("=== WhatsApp Chat Area Element Tree ===")
        // printChatAreaElementTree(windowElement)
        // Logger.info("=== End Chat Area Element Tree ===")
        
        // Get the chat area element (5th child of first child of first child)
        guard let chatAreaElement = getChatAreaElement(from: windowElement) else {
            Logger.debug("Failed to get chat area element")
            return extractedMessages
        }
        
        // Parse chat messages from the chat area
        parseChatMessagesFromElement(chatAreaElement, messages: &extractedMessages, filterAfterTimestamp: filterAfterTimestamp)
        
        Logger.info("Extracted \(extractedMessages.count) messages from WhatsApp")
        return extractedMessages
    }
     
    
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
    private func parseChatMessagesFromElement(_ chatAreaElement: AXUIElement, messages: inout [ChatMessage], filterAfterTimestamp: Date? = nil) {
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
 
        // 不在这里更新，因为第一次启动时，需要比对SessionID的变化，这时更新后会导致加载不到
        // Update current session ID based on contact name
        // currentSessionId = contactName
        // Logger.debug("Updated session ID to: \(currentSessionId)")
        
        // Parse messages from second child
        parseMessagesFromContentArea(childrenArray[1], contactName: contactName, messages: &messages, filterAfterTimestamp: filterAfterTimestamp)
        
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
    private func parseMessagesFromContentArea(_ element: AXUIElement, contactName: String, messages: inout [ChatMessage], filterAfterTimestamp: Date? = nil) {
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
                            if let messageTimestamp = parseTimestamp(chatMessage.timestamp) {
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
    

}

/// Observable data model for chat translation view
class ChatTranslationData: ObservableObject {
    @Published var appName: String = ""
    @Published var sessionId: String = ""
    @Published var messages: [ChatMessage] = []
    @Published var isTranslating: Bool = false
    
    func updateData(appName: String, sessionId: String, messages: [ChatMessage]) {
        self.appName = appName
        self.sessionId = sessionId
        self.messages = messages
    }
    
    func appendMessage(_ message: ChatMessage) {
        // Check if message already exists to prevent duplicates
        if !messages.contains(where: { $0.id == message.id }) {
            messages.append(message)
        }
    }
    
    func setTranslating(_ translating: Bool) {
        isTranslating = translating
    }
    
    func clear() {
        appName = ""
        sessionId = ""
        messages.removeAll()
        isTranslating = false
    }
}

/// SwiftUI view for chat translation window content
struct ChatTranslationView: View {
    @ObservedObject var data: ChatTranslationData
    let onClose: () -> Void
    
    var appName: String { data.appName }
    var sessionId: String { data.sessionId }
    var messages: [ChatMessage] { data.messages }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header (draggable area)
            HStack {
                Text("Glotera AI")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                if !appName.isEmpty {
                    Text("- \(appName)")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                
                if !sessionId.isEmpty && sessionId != "default" {
                    Text("- \(sessionId)")
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
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
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
                                    .id(message.id) // Important for scroll targeting
                            }
                            
                            // Show translation indicator if translating
                            if data.isTranslating {
                                HStack {
                                    TranslationIndicator()
                                    Text("Translating...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(NSColor.controlBackgroundColor))
                                )
                                .frame(maxWidth: 200)
                                .id("translating")
                            }
                            
                            // Invisible anchor at the bottom
                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                    }
                    .padding()
                }
                .scrollDisabled(false) // Ensure scrolling is enabled but controlled
                .onChange(of: messages.count) { _ in
                    // Auto-scroll to bottom when new messages are added (like IM apps)
                    if !messages.isEmpty {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: data.isTranslating) { isTranslating in
                    // Auto-scroll when translation indicator appears
                    if isTranslating {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("translating", anchor: .bottom)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
            .contentShape(Rectangle()) // Make the messages area non-draggable
            .allowsHitTesting(true) // Allow scroll and selection, but block window dragging
        }
        .frame(width: 400, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }
}

/// Translation status indicator with animated dots
struct TranslationIndicator: View {
    @State private var dotOffset: CGFloat = 0
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .offset(y: dotOffset)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: dotOffset
                    )
            }
        }
        .onAppear {
            dotOffset = -8
        }
    }
}

/// Individual message view with IM-style colors and alignment
struct MessageView: View {
    let message: ChatMessage
    
    // Message bubble colors
    private var sentMessageColor: Color {
        // Blue gradient for sent messages (like iMessage)
        Color(red: 0.0, green: 0.48, blue: 1.0) // iOS-style blue
    }
    
    private var receivedMessageColor: Color {
        // Adaptive gray for received messages that works in light/dark mode
        Color(NSColor.controlBackgroundColor)
    }
    
    var body: some View {
        HStack {
            if message.isFromMe {
                Spacer() // Push sent messages to the right
            }
            
            VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 4) {
                // Sender and timestamp row
                HStack(spacing: 8) {
                    if !message.isFromMe {
                        Text(message.sender)
                            .font(.caption) 
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                    
                    Text(message.timestamp)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .opacity(0.7)
                }
                
                // Message content bubble
                VStack(alignment: .leading, spacing: 6) {
                    // Original content - Show with lighter color and italic
                    Text(message.content)
                        .font(.caption)
                        .italic()
                        .foregroundColor(message.isFromMe ? Color.white.opacity(0.6) : Color.secondary)
                        .textSelection(.enabled)
                    
                    // Translation (if available) - Show with normal color and prominent
                    if let translation = message.contentTranslation,
                       !translation.isEmpty && translation != "[Translation failed]" {
                        Divider()
                            .background(message.isFromMe ? Color.white.opacity(0.3) : Color.secondary.opacity(0.3))
                        
                        Text(translation)
                            .font(.body)
                            .foregroundColor(message.isFromMe ? .white : .primary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(message.isFromMe ? 
                              sentMessageColor : // Sent messages - blue
                              receivedMessageColor // Received messages - adaptive gray
                        )
                        .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1) // Subtle shadow
                )
                .frame(maxWidth: 280, alignment: message.isFromMe ? .trailing : .leading)
            }
            .frame(maxWidth: .infinity, alignment: message.isFromMe ? .trailing : .leading)
            
            if !message.isFromMe {
                Spacer() // Push received messages to the left
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
} 
