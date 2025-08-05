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
        
        if appInfo.bundleId == "net.whatsapp.WhatsApp" {
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
        
        // Clear current messages before loading from database
        messages.removeAll()
        messageHashes.removeAll()
        
        let recentRecords = dbManager.getRecentMessages(forApp: appName, sessionId: sessionId, limit: limit)
        
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
             
            // Add to messages array and tracking set
            messages.append(message)
            messageHashes.insert(message.messageHash)
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
        // Start a timer to periodically check for new messages
        messageUpdateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
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
        let extractedMessages = WhatsAppMessagesProcessor.extractMessages(from: activeApp, filterAfterTimestamp: lastMessageTimestamp ?? Date.distantPast)
         
        
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
        let dbManager = DatabaseManager.shared
        
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
                let targetLanguage = ConfigManager.shared.getUserPreferredLanguage()
                finalTranslationLanguage = targetLanguage
                
                // Translate message using non-streaming mode
                do {
                    let translationResult = try await translateMessage(message.content, to: targetLanguage) 
                    finalLanguage = translationResult.fromLanguage ?? ""
                    finalTranslation = translationResult.translated
                    
                    Logger.info("Translated message: \(message.content.prefix(30))... -> \(translationResult.translated.prefix(30))...")
                    Logger.info("Detected source language: \(finalLanguage)")
                
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
     
}

/// Observable data model for chat translation view
class ChatTranslationData: ObservableObject {
    @Published var appName: String = ""
    @Published var sessionId: String = ""
    @Published var messages: [ChatMessage] = []
    @Published var isTranslating: Bool = false
    @Published var isUnsupportedApp: Bool = false
    
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
    
    func setUnsupportedApp(_ unsupported: Bool) {
        isUnsupportedApp = unsupported
    }
    
    func clear() {
        appName = ""
        sessionId = ""
        messages.removeAll()
        isTranslating = false
        isUnsupportedApp = false
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
                        if isUnsupportedApp {
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
