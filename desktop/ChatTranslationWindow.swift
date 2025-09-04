import Cocoa
import SwiftUI



/// Chat translation floating window that appears next to IM applications
class ChatTranslationWindow: NSWindow {
    // Window positioning configuration
    private static let screenRightEdgeGap: CGFloat = 5 // Gap from screen right edge in pixels
    
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
        
        // Calculate initial position at screen right edge
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
        let initialX = screenFrame.maxX - initialSize.width - ChatTranslationWindow.screenRightEdgeGap
        let initialY = screenFrame.midY - (initialSize.height / 2)
        
        super.init(
            contentRect: NSRect(x: initialX, y: initialY, width: initialSize.width, height: initialSize.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = NSColor.clear
        self.hasShadow = true
        self.isMovableByWindowBackground = false
        self.isReleasedWhenClosed = false
        
        setupContent()
        setupWindowBehavior()
        
        // Start message monitoring once during initialization
        startMessageMonitoring()
        
        // Register with SimpleMemoryManager
        SimpleMemoryManager.shared.registerWindow(self)
        
        Logger.info("ChatTranslationWindow initialized at screen right edge: x=\(initialX), y=\(initialY)")
    }
    
    private func setupContent() {
        // Initialize the content using updateChatTranslationView
        updateChatTranslationView()
    }
    
    private func setupWindowBehavior() {
        // Make window stay on top of other windows
        self.level = .floating
        
        // Disable window dragging - window will be fixed at screen right edge
        self.isMovableByWindowBackground = false
        
        // Override mouse tracking behavior
        self.acceptsMouseMovedEvents = false
    }
    
    // Window movement tracking removed - window is now fixed at screen right edge
    
    /// Show the window at screen right edge
    func showWindowAtScreenSide(_ appInfo: AppInfo) {
        currentAppInfo = appInfo
        appName = appInfo.appName
        
        // Check if user has access to chat translation feature
        if !SessionManager.shared.hasChatTranslationAccess() {
            Logger.info("User does not have chat translation access - showing upgrade message")
            showUpgradeRequiredMessage(appInfo.appName)
        } else if appInfo.bundleId == "net.whatsapp.WhatsApp" {
            // Supported app - show normal translation interface
            Logger.info("WhatsApp detected - showing normal translation interface")
            updateChatTranslationView()
        } else if AppDetectionManager.shared.isChatApp(bundleId: appInfo.bundleId) {
            // Unsupported app - show coming soon message
            Logger.info("\(appInfo.appName) - Unsupported chat app detected")
            showUnsupportedAppMessage(appInfo.appName)
        } else {
            Logger.info("\(appInfo.appName) - Not chat app, hiding window")
            self.orderOut(nil)
            return
        }
        
        // Only show window for supported or unsupported chat apps
        // Show the window first
        self.makeKeyAndOrderFront(nil)
        
        // Then position window at screen right edge immediately
        DispatchQueue.main.async {
            self.positionWindowAtScreenRightEdge()
        }
        
        // Verify window is actually visible
        Logger.info("Chat translation window shown for app: \(appInfo.appName), isVisible: \(self.isVisible)")
        
        // Add a small delay to check if window stays visible
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Logger.info("Window visibility check after 0.5s: \(self.isVisible)")
        }
    }
    
    /// Load recent messages from database
    private func loadRecentMessagesFromDatabase(appName: String, sessionId: String, limit: Int = 50) {
        let dbManager = DatabaseManager.shared
        
        // Set loading state for UI
        chatTranslationData?.isLoadingHistory = true
        
        // Clear current messages before loading from database
        messages.removeAll()
        messageHashes.removeAll()
        
        var recentRecords = dbManager.getRecentMessages(forApp: appName, sessionId: sessionId, limit: limit)
        // Sort by created_time ascending to ensure stable order within the same minute
        recentRecords.sort { $0.createdTime < $1.createdTime }
        
        Logger.info("Loading \(recentRecords.count) recent messages from database for session: \(sessionId)")
        
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
            
            // Skip empty content
            if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Add to messages array and tracking set
                messages.append(message)
                messageHashes.insert(message.messageHash)
            }
        }
        
        // Get the timestamp of the last message for filtering new messages
        lastMessageTimestamp = dbManager.getLastMessageTimestamp(forApp: appName, sessionId: sessionId)
        if let lastTimestamp = lastMessageTimestamp {
            Logger.info("Last message timestamp for session \(sessionId): \(lastTimestamp)")
        } else {
            Logger.info("No previous messages found for session \(sessionId)")
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
    
    /// Format timestamp for database/message string (yyyy-MM-dd HH:mm:ss)
    private func formatDbTimestampString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
    
    /// Hide the window
    func hideWindow() {
        // Clear the data model
        chatTranslationData?.clear()
        
        self.orderOut(nil)
        Logger.debug("Chat translation window hidden, isVisible: \(self.isVisible)")
    }
    
    /// Update the chat translation view with current app name and messages
    private func updateChatTranslationView() {
        // Initialize data and view only once
        if chatTranslationData == nil {
            chatTranslationData = ChatTranslationData()
            
            let chatView = ChatTranslationView(
                data: chatTranslationData!,
                onClose: { [weak self] in
                    // Notify ChatTranslationManager that window was closed by user
                    ChatTranslationManager.shared.notifyWindowClosedByUser()
                    self?.hideWindow()
                }
            )
            
            hostingView = NSHostingView(rootView: chatView)
            self.contentView = hostingView
        }
        
        // Update data instead of recreating the view
        chatTranslationData?.updateData(appName: appName, sessionId: currentSessionId, messages: messages)
        chatTranslationData?.setUnsupportedApp(false) // Reset unsupported app state for supported apps
        chatTranslationData?.isLoadingHistory = false // Clear loading state after UI update
    }
    
    /// Show unsupported app message
    private func showUnsupportedAppMessage(_ appName: String) {
        // Clear current messages and session
        messages.removeAll()
        messageHashes.removeAll()
        currentSessionId = "default"
        lastMessageTimestamp = nil
        
        // Initialize data and view only once
        if chatTranslationData == nil {
            chatTranslationData = ChatTranslationData()
            
            let chatView = ChatTranslationView(
                data: chatTranslationData!,
                onClose: { [weak self] in
                    // Notify ChatTranslationManager that window was closed by user
                    ChatTranslationManager.shared.notifyWindowClosedByUser()
                    self?.hideWindow()
                }
            )
            
            hostingView = NSHostingView(rootView: chatView)
            self.contentView = hostingView
        }
        
        // Update data with unsupported app message
        chatTranslationData?.updateData(appName: appName, sessionId: "", messages: [])
        chatTranslationData?.setUnsupportedApp(true)
        
        Logger.info("Showing unsupported app message for: \(appName)")
    }
    
    /// Show upgrade required message for free users
    private func showUpgradeRequiredMessage(_ appName: String) {
        // Clear current messages and session
        messages.removeAll()
        messageHashes.removeAll()
        currentSessionId = "default"
        lastMessageTimestamp = nil
        
        // Initialize data and view only once
        if chatTranslationData == nil {
            chatTranslationData = ChatTranslationData()
            
            let chatView = ChatTranslationView(
                data: chatTranslationData!,
                onClose: { [weak self] in
                    // Notify ChatTranslationManager that window was closed by user
                    ChatTranslationManager.shared.notifyWindowClosedByUser()
                    self?.hideWindow()
                }
            )
            
            hostingView = NSHostingView(rootView: chatView)
            self.contentView = hostingView
        }
        
        // Update data with upgrade required message
        chatTranslationData?.updateData(appName: appName, sessionId: "", messages: [])
        chatTranslationData?.setUpgradeRequired(true)
        
        Logger.info("Showing upgrade required message for: \(appName)")
    }
    
    
    /// Position the window at screen right edge
    private func positionWindowAtScreenRightEdge() {
        Logger.info("Positioning window at screen right edge")
        
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
        let windowFrame = self.frame
        
        Logger.debug("Screen frame: \(screenFrame)")
        Logger.debug("Current window frame: \(windowFrame)")
        
        // Calculate position at screen right edge, vertically centered
        let newX = screenFrame.maxX - windowFrame.width - ChatTranslationWindow.screenRightEdgeGap
        let newY = screenFrame.midY - (windowFrame.height / 2) // Vertically centered
        
        Logger.debug("Calculated position: x=\(newX), y=\(newY)")
        
        // Ensure the window doesn't go off screen
        let finalY = max(screenFrame.origin.y + 20, min(newY, screenFrame.maxY - windowFrame.height - 20))
        
        Logger.debug("Final position: x=\(newX), y=\(finalY)")
        
        // Set position immediately without animation for initial positioning
        self.setFrameOrigin(NSPoint(x: newX, y: finalY))
        self.windowPosition = self.frame.origin
        
        Logger.debug("Window positioned at screen right edge, final frame: \(self.frame)")
    }
    
    // Fallback positioning method removed - window is now fixed at screen right edge
    
    // getMainWindowFrameForApplication method removed - window is now fixed at screen right edge
    
    /// Update window position to screen right edge
    func updatePosition() {
        Logger.debug("updatePosition called - positioning to screen right edge")
        
        // Always position at screen right edge since window is fixed
        positionWindowAtScreenRightEdge()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stopMessageMonitoring()
        Logger.info("ChatTranslationWindow deallocating")
    }
    
    /// Start monitoring WhatsApp messages
    private func startMessageMonitoring() {
        // Start a timer to periodically check for new messages (reduced frequency to minimize flicker)
        messageUpdateTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.fetchChatMessages()
        }
        
        Logger.info("Started message monitoring")
    }
    
    /// Stop monitoring WhatsApp messages
    private func stopMessageMonitoring() {
        messageUpdateTimer?.invalidate()
        messageUpdateTimer = nil
        Logger.info("Stopped message monitoring")
    }
    
    /// Fetch WhatsApp messages using Accessibility API
    private func fetchChatMessages() {
        // Check if already fetching messages to prevent overlapping executions
        guard !isFetchingMessages else {
            Logger.debug("Skipping fetchMessages - previous execution still in progress")
            return
        }
        
        // Check if window is actually visible to user - if not, skip message processing
        guard self.isVisible else {
            // Logger.debug("Chat translation window is not visible - skipping message processing")
            return
        }
        
        //MARK: 暂时只支持WhatsApp
        guard let activeApp = NSWorkspace.shared.frontmostApplication
                ,let bundleId = activeApp.bundleIdentifier else {
            return
        }
        let appName = AppDetectionManager.shared.getChatAppName(bundleId: bundleId)
        if AppDetectionManager.shared.isWhatsAppApp(bundleId: bundleId) {
            // TODO: 暂时只支持WhatsApp
        } else {
            return
        }
        
        
        Logger.info("Start to fetch chat messages ...")
        
        // Set fetching flag to prevent overlapping executions
        isFetchingMessages = true
        

        // Check if chat session has changed
        if let newSessionId = WhatsAppMessagesProcessor.getCurrentChatSessionId(activeApp: activeApp) {
            Logger.info("Current session ID: \(currentSessionId), new session ID: \(newSessionId)")
            if newSessionId != currentSessionId {
                Logger.info("Chat session changed from '\(currentSessionId)' to '\(newSessionId)'")
                currentSessionId = newSessionId
                loadRecentMessagesFromDatabase(appName: appName, sessionId: currentSessionId)
            }
        }
        
        // If lastMessageTimestamp is nil, try to get it from database to avoid re-processing history
        if lastMessageTimestamp == nil {
            let dbManager = DatabaseManager.shared
            lastMessageTimestamp = dbManager.getLastMessageTimestamp(forApp: appName, sessionId: currentSessionId)
            if let lastTimestamp = lastMessageTimestamp {
                    Logger.info("Set lastMessageTimestamp from database: \(lastTimestamp)")
            } else {
                Logger.info("No previous messages found in database for session: \(currentSessionId)")
            }
        }

        // Extract messages from WhatsApp with timestamp filtering
        // Align filter to minute start minus 1s so that messages within the same minute are included
        let filterAfterTs: Date = {
            guard let lastTs = lastMessageTimestamp else { return Date.distantPast }
            let calendar = Calendar(identifier: .gregorian)
            var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: lastTs)
            comps.second = 0
            let minuteFloor = calendar.date(from: comps) ?? lastTs
            return minuteFloor.addingTimeInterval(-1)
        }()
        let extractedMessages = WhatsAppMessagesProcessor.extractMessages(from: activeApp, filterAfterTimestamp: filterAfterTs)
         
        
        // Only process if there are actually new messages
        if !extractedMessages.isEmpty {
            Logger.info("Found \(extractedMessages.count) new messages")
            
            // Same-minute post check: if message is in the same minute as lastTimestamp and
            // DB has no same-minute record with the same hash, treat it as new and set its time to lastTimestamp+1s.
            let finalNewMessages: [ChatMessage] = {
                guard let lastTs = self.lastMessageTimestamp else { return extractedMessages }
                let calendar = Calendar(identifier: .gregorian)
                let lastMinuteComps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: lastTs)
                var results: [ChatMessage] = []
                for msg in extractedMessages {
                    guard let msgDate = ChatMessagesUtil.parseTimestamp(msg.timestamp) else {
                        results.append(msg)
                        continue
                    }
                    if msgDate > lastTs {
                        results.append(msg)
                        continue
                    }
                    if msg.isFromMe { continue }
                    let msgComps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: msgDate)
                    let sameMinute = (msgComps.year == lastMinuteComps.year &&
                                      msgComps.month == lastMinuteComps.month &&
                                      msgComps.day == lastMinuteComps.day &&
                                      msgComps.hour == lastMinuteComps.hour &&
                                      msgComps.minute == lastMinuteComps.minute)
                    if sameMinute {
                        let hash = DatabaseManager.shared.calculateContentHash(msg.content)
                        var minuteStartComps = lastMinuteComps
                        minuteStartComps.second = 0
                        let minuteStart = calendar.date(from: minuteStartComps) ?? lastTs
                        let exists = DatabaseManager.shared.hasReceivedMessageHashInSameMinute(appName: self.appName, sessionId: self.currentSessionId, contentHash: hash, minuteStart: minuteStart)
                        if !exists {
                            // Treat as new and adjust timestamp to lastTs + 1s
                            let adjusted = lastTs.addingTimeInterval(1)
                            let adjustedMsg = ChatMessage(
                                messageType: msg.messageType,
                                content: msg.content,
                                sender: msg.sender,
                                timestamp: self.formatDbTimestampString(adjusted),
                                isFromMe: msg.isFromMe
                            )
                            results.append(adjustedMsg)
                        }
                    }
                }
                return results
            }()

            // If nothing new after same-minute check, do nothing to avoid UI flicker
            if finalNewMessages.isEmpty {
                self.isFetchingMessages = false
            } else {
                // Process messages with translation in background
                Task {
                    await self.processNewMessages(finalNewMessages)
                    // Reset fetching flag after processing is complete
                    await MainActor.run {
                        self.isFetchingMessages = false
                    }
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
        let dbManager = DatabaseManager.shared

        // Decide whether to show translation indicator (only if there exists a received message that will be translated)
        let shouldShowIndicator: Bool = {
            for msg in newMessages {
                if !msg.isFromMe {
                    let lang = ContentProcessor.detectLanguage(msg.content)
                    if shouldTranslateMessage(sourceLanguage: lang) {
                        return true
                    }
                }
            }
            return false
        }()
        
        // If messages array is empty and we're processing new messages, show loading state
        let isInitialLoad = messages.isEmpty && !newMessages.isEmpty
        // Combine initial state updates to avoid multiple UI refreshes
        await MainActor.run {
            if isInitialLoad {
                self.chatTranslationData?.isLoadingHistory = true
            } else if shouldShowIndicator {
                self.chatTranslationData?.setTranslating(true)
            }
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
                Logger.info("No existing translation found for message: \(message.content.prefix(30))...")
                
                // Skip translation for sent messages (they were already translated before sending)
                if message.isFromMe {
                    Logger.info("Skipping translation for sent message: \(message.content.prefix(30))...")
                    
                    // For sent messages, only detect language but don't translate
                    let detectedLanguage = ContentProcessor.detectLanguage(message.content)
                    finalLanguage = detectedLanguage
                    
                    // Save sent message to database without translation
                    let timestamp = ChatMessagesUtil.parseTimestamp(message.timestamp) ?? Date()
                    let messageRecord = MessageRecord(
                        sender: message.sender,
                        content: message.content,
                        contentHash: contentHash,
                        contentLanguage: detectedLanguage,
                        contentTranslation: "", // No translation for sent messages
                        contentTranslationLanguage: "", // No translation language
                        contentTimestamp: timestamp,
                        chatApp: "WhatsApp",
                        sessionId: currentSessionId
                    )
                    
                    _ = dbManager.insertMessage(messageRecord)
                    
                    // Update lastMessageTimestamp after successful insertion
                    lastMessageTimestamp = timestamp
                    Logger.debug("Updated lastMessageTimestamp to: \(timestamp)")
                } else {
                    // For received messages, check translation rules
                    Logger.info("Checking translation rules for received message: \(message.content.prefix(30))...")
                    
                    // First detect the source language
                    let detectedLanguage = ContentProcessor.detectLanguage(message.content)
                    finalLanguage = detectedLanguage
                    
                    Logger.info("Detected source language: \(detectedLanguage)")
                    
                    // Check translation rules to determine if translation is needed
                    if shouldTranslateMessage(sourceLanguage: detectedLanguage) {
                        Logger.info("Translation rules allow translation for language: \(detectedLanguage)")
                        
                        // Translate to user's preferred language
                        let targetLanguage = ConfigManager.shared.getUserPreferredLanguage()
                        finalTranslationLanguage = targetLanguage
                        
                        // Record the current app info before translation for environment info
                        EnvironmentManager.shared.recordTriggerApp()
                        
                        // Translate message using non-streaming mode
                        do {
                            let translationResult = try await translateMessage(message.content, to: targetLanguage) 
                            finalLanguage = translationResult.fromLanguage ?? ""
                            finalTranslation = translationResult.translated
                            
                            Logger.info("Translated message: \(message.content.prefix(30))... -> \(translationResult.translated.prefix(30))...")
                            Logger.info("Detected source language: \(finalLanguage ?? "unknown")")
                        
                            // Save to database
                            let timestamp = ChatMessagesUtil.parseTimestamp(message.timestamp) ?? Date()
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
                            
                            // Even if translation fails, save the message to database to prevent reprocessing
                            let timestamp = ChatMessagesUtil.parseTimestamp(message.timestamp) ?? Date()
                            let messageRecord = MessageRecord(
                                sender: message.sender,
                                content: message.content,
                                contentHash: contentHash,
                                contentLanguage: finalLanguage ?? "",
                                contentTranslation: "[Translation failed]",
                                contentTranslationLanguage: targetLanguage,
                                contentTimestamp: timestamp,
                                chatApp: "WhatsApp",
                                sessionId: currentSessionId
                            )
                            
                            _ = dbManager.insertMessage(messageRecord)
                            
                            // Update lastMessageTimestamp to prevent reprocessing this message
                            lastMessageTimestamp = timestamp
                            Logger.debug("Updated lastMessageTimestamp after translation failure: \(timestamp)")
                        }
                        
                        // Clear trigger app info after translation is complete
                        EnvironmentManager.shared.clearTriggerAppInfo()
                    } else {
                        Logger.info("Translation rules do not allow translation for language: \(detectedLanguage), skipping translation")
                        
                        // Save message to database without translation
                        let timestamp = ChatMessagesUtil.parseTimestamp(message.timestamp) ?? Date()
                        let messageRecord = MessageRecord(
                            sender: message.sender,
                            content: message.content,
                            contentHash: contentHash,
                            contentLanguage: detectedLanguage,
                            contentTranslation: "", // No translation
                            contentTranslationLanguage: "", // No translation language
                            contentTimestamp: timestamp,
                            chatApp: "WhatsApp",
                            sessionId: currentSessionId
                        )
                        
                        _ = dbManager.insertMessage(messageRecord)
                        
                        // Update lastMessageTimestamp after successful insertion
                        lastMessageTimestamp = timestamp
                        Logger.debug("Updated lastMessageTimestamp to: \(timestamp)")
                    }
                }
            }
            
            // Create processed message with all translation fields
            // Unify display timestamp format for received/sent messages
            let displayTimestamp: String = {
                if let parsed = ChatMessagesUtil.parseTimestamp(message.timestamp) {
                    return self.formatTimestamp(parsed)
                } else {
                    return message.timestamp
                }
            }()
            
            let processedMessage = ChatMessage(
                sender: message.sender,
                content: message.content,
                timestamp: displayTimestamp,
                isFromMe: message.isFromMe,
                contentTranslation: finalTranslation,
                contentLanguage: finalLanguage,
                contentTranslationLanguage: finalTranslationLanguage,
                contentHash: contentHash
            )

            // Add only if content is not empty and not already processed
            if !processedMessage.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Check if message already exists to prevent duplicates
                if !messageHashes.contains(processedMessage.messageHash) {
                    // Add to messages array maintaining chronological order
                    messages.append(processedMessage)
                    messageHashes.insert(processedMessage.messageHash)
                } else {
                    Logger.debug("Skipping duplicate message: \(processedMessage.content.prefix(30))...")
                }
            }
            
            // Keep messages within limit
            if messages.count > maxMessagesLimit {
                messages.removeFirst()
        }
        
            // Defer UI updates until after the loop to avoid flicker
    }
    
        // Single UI update after all messages are processed to minimize flicker
        await MainActor.run { 
            self.updateChatTranslationView()
            // Update all states in a single MainActor call to avoid multiple UI refreshes
            if shouldShowIndicator {
                self.chatTranslationData?.setTranslating(false)
            }
            if isInitialLoad {
                self.chatTranslationData?.isLoadingHistory = false
            }
        }
    }
 
    // detectLanguage moved to ContentProcessor.detectLanguage
    
    /// Check if message should be translated based on translation rules
    private func shouldTranslateMessage(sourceLanguage: String) -> Bool {
        let settings = ConfigManager.shared.loadAppSettings()
        
        Logger.debug("Checking translation rules for language: \(sourceLanguage)")
        Logger.debug("Translation rule type: \(settings.translationRuleType)")
        Logger.debug("Includes languages: \(settings.translationRuleLanguagesIncludes)")
        Logger.debug("Excludes languages: \(settings.translationRuleLanguagesExcludes)")
        
        if settings.translationRuleType == "includes" {
            // In includes mode, only translate if the language is in the includes list
            let shouldTranslate = settings.translationRuleLanguagesIncludes.contains(sourceLanguage)
            Logger.debug("Includes mode: language \(sourceLanguage) should translate: \(shouldTranslate)")
            return shouldTranslate
        } else {
            // In excludes mode, translate all languages except those in the excludes list
            // Note: Preferred language is automatically excluded in excludes mode
            let preferredLanguage = settings.preferredLanguage
            let isExcluded = settings.translationRuleLanguagesExcludes.contains(sourceLanguage) || sourceLanguage == preferredLanguage
            let shouldTranslate = !isExcluded
            Logger.debug("Excludes mode: language \(sourceLanguage) is excluded: \(isExcluded), should translate: \(shouldTranslate)")
            Logger.debug("Preferred language from settings: \(preferredLanguage)")
            return shouldTranslate
        }
    }
    
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
    
    /// Get recent messages for external access
    func getRecentMessages() -> [ChatMessage]? {
        return messages.isEmpty ? nil : messages
    }
    
    /// Add user message immediately after sending (without waiting for timer)
    func addUserMessage(originalText: String, translatedText: String, sourceLanguage: String?, targetLanguage: String, sessionId: String) {
        Logger.info("Adding user message immediately: '\(originalText)' -> '\(translatedText)'")
        
        // Check if this is the correct session
        if sessionId != currentSessionId {
            Logger.debug("Session mismatch: current=\(currentSessionId), provided=\(sessionId), skipping immediate add")
            return
        }
        
        // Create ChatMessage with proper translation data
        let timestamp = Date()
        let formattedTimestamp = formatTimestamp(timestamp)
        
        let chatMessage = ChatMessage(
            sender: "You",
            content: originalText,  // 原文
            timestamp: formattedTimestamp,
            isFromMe: true,
            contentTranslation: translatedText,  // 译文
            contentLanguage: sourceLanguage ?? "unknown",
            contentTranslationLanguage: targetLanguage,
            contentHash: DatabaseManager.shared.calculateContentHash(originalText)
        )
        
        // Add only if original content is not empty
        if !chatMessage.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Add to messages array
            messages.append(chatMessage)
        }
        
        // Keep messages within limit
        if messages.count > maxMessagesLimit {
            messages.removeFirst()
        }
        
        // Update lastMessageTimestamp
        lastMessageTimestamp = timestamp
        
        // Update UI immediately
        updateChatTranslationView()
        
        Logger.debug("User message added immediately to chat window")
    }

}

/// Observable data model for chat translation view
class ChatTranslationData: ObservableObject {
    @Published var appName: String = ""
    @Published var sessionId: String = ""
    @Published var messages: [ChatMessage] = []
    @Published var isTranslating: Bool = false
    @Published var isUnsupportedApp: Bool = false
    @Published var isUpgradeRequired: Bool = false
    @Published var isLoadingHistory: Bool = false // Track initial history loading state
    
    func updateData(appName: String, sessionId: String, messages: [ChatMessage]) {
        // Only update if data has actually changed to prevent unnecessary UI refreshes
        if self.appName != appName {
            self.appName = appName
        }
        if self.sessionId != sessionId {
            self.sessionId = sessionId
        }
        // For messages, check if the count and content have changed
        if self.messages.count != messages.count || !messagesAreEqual(self.messages, messages) {
            self.messages = messages
        }
    }
    
    // Helper function to compare message arrays efficiently
    private func messagesAreEqual(_ lhs: [ChatMessage], _ rhs: [ChatMessage]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        // Compare just the last few messages for efficiency (most changes happen at the end)
        let compareCount = min(5, lhs.count)
        let lhsLast = lhs.suffix(compareCount)
        let rhsLast = rhs.suffix(compareCount)
        
        for (left, right) in zip(lhsLast, rhsLast) {
            if left.id != right.id || left.content != right.content || left.contentTranslation != right.contentTranslation {
                return false
            }
        }
        return true
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
    
    func setUnsupportedApp(_ unsupported: Bool) {
        isUnsupportedApp = unsupported
    }
    
    func setUpgradeRequired(_ upgradeRequired: Bool) {
        isUpgradeRequired = upgradeRequired
    }
    
    func clear() {
        appName = ""
        sessionId = ""
        messages.removeAll()
        isTranslating = false
        isUnsupportedApp = false
        isUpgradeRequired = false
    }
}

/// SwiftUI view for chat translation window content
struct ChatTranslationView: View {
    @ObservedObject var data: ChatTranslationData
    let onClose: () -> Void
    
    var appName: String { data.appName }
    var sessionId: String { data.sessionId }
    var messages: [ChatMessage] { data.messages }
    var isUnsupportedApp: Bool { data.isUnsupportedApp }
    var isUpgradeRequired: Bool { data.isUpgradeRequired }
    
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
                        if isUpgradeRequired {
                            // Show upgrade required message
                            VStack(spacing: 16) {
                                Spacer()
                                
                                Image(systemName: "star.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.yellow)
                                
                                Text("Pro Feature")
                                    .font(.title2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.center)
                                
                                Text("Chat translation is available for Pro and Max users")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                                
                                VStack(spacing: 8) {
                                    Text("• Pro: \(QuotaLimits.PRO_MONTHLY_LIMIT) translations/month")
                                    Text("• Max: Unlimited translations")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                                
                                Button(action: {
                                    // Open upgrade page
                                    if let url = URL(string: "https://glotera.ai/pricing") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }) {
                                    Text("Upgrade Now")
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 8)
                                        .background(Color.blue)
                                        .cornerRadius(16)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .padding(.top, 8)
                                
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                        } else if isUnsupportedApp {
                            // Show unsupported app message
                            VStack(spacing: 16) {
                                Spacer()
                                
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.orange)
                                
                                Text("\(appName) isn't supported now")
                                    .font(.title2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.center)
                                
                                Text("Will coming soon")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                        } else if data.isLoadingHistory {
                            VStack(spacing: 16) {
                                Spacer()
                                
                                // Loading animation
                                ProgressView()
                                    .scaleEffect(1.2)
                                    .progressViewStyle(CircularProgressViewStyle())
                                
                                Text("Loading chat history...")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                
                                Text("Please wait while we process your messages")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if messages.isEmpty {
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
