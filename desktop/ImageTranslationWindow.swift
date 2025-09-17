import Cocoa
import SwiftUI

class ImageTranslationWindow: NSWindow {
    private var hostingView: NSHostingView<ImageTranslationView>?
    let imageTranslationData: ImageTranslationData

    init(image: NSImage, base64Data: String, savedImageURL: URL?) {
        // Initialize the data model
        imageTranslationData = ImageTranslationData(image: image, base64Data: base64Data, savedImageURL: savedImageURL)

        // Window size
        let windowSize = NSSize(width: 800, height: 600)

        // Center window on screen
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
        let windowFrame = NSRect(
            x: screenFrame.midX - windowSize.width / 2,
            y: screenFrame.midY - windowSize.height / 2,
            width: windowSize.width,
            height: windowSize.height
        )

        super.init(
            contentRect: windowFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        self.title = "Glotera AI - Image Translation"
        self.level = .floating
        self.isReleasedWhenClosed = false

        setupContent()

        Logger.info("ImageTranslationWindow created with image size: \(image.size)")
    }

    private func setupContent() {
        let translationView = ImageTranslationView(
            data: imageTranslationData,
            onClose: { [weak self] in
                self?.close()
            }
        )

        hostingView = NSHostingView(rootView: translationView)
        self.contentView = hostingView
    }
}

// MARK: - Image Translation Data Model
class ImageTranslationData: ObservableObject {
    @Published var image: NSImage
    @Published var translationResult: String = ""
    @Published var isTranslating: Bool = false
    @Published var errorMessage: String?
    @Published var selectedTargetLanguage: String = "en" {
        didSet {
            if oldValue != selectedTargetLanguage && !isInitializing {
                Logger.info("Target language changed from \(oldValue) to \(selectedTargetLanguage)")
                // Save the new preferred language to cache
                ConfigManager.shared.setPreferredLanguage(selectedTargetLanguage)
                // Start new translation with the selected language
                startTranslation()
            }
        }
    }
    @Published var conversationHistory: [ConversationItem] = []
    @Published var followUpQuestion: String = ""
    @Published var isProcessingFollowUp: Bool = false

    let base64Data: String
    let savedImageURL: URL?

    // Available target languages
    let availableLanguages = [
        ("en", "English"),
        ("zh", "中文"),
        ("ja", "日本語"),
        ("ko", "한국어"),
        ("es", "Español"),
        ("fr", "Français"),
        ("de", "Deutsch"),
        ("ru", "Русский"),
        ("pt", "Português"),
        ("it", "Italiano"),
        ("ar", "العربية"),
        ("hi", "हिन्दी")
    ]

    private var isInitializing = true

    init(image: NSImage, base64Data: String, savedImageURL: URL?) {
        self.image = image
        self.base64Data = base64Data
        self.savedImageURL = savedImageURL

        // Load user's preferred language from settings
        self.selectedTargetLanguage = ConfigManager.shared.getUserPreferredLanguage()

        Logger.info("ImageTranslationData initialized with target language: \(selectedTargetLanguage)")

        // Mark initialization as complete
        self.isInitializing = false

        // Start translation automatically when initialized
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.startTranslation()
        }
    }

    func startTranslation() {
        guard !isTranslating else { return }

        Logger.info("Starting image translation to: \(selectedTargetLanguage)")
        isTranslating = true
        errorMessage = nil
        translationResult = ""
        // Clear previous conversation history when starting new translation
        conversationHistory.removeAll()

        // Use streaming translation for better user experience
        TranslatorClient.shared.translateImageStream(
            base64Data: base64Data,
            to: selectedTargetLanguage,
            onChunk: { [weak self] chunk, fullContent in
                Logger.info("📝 Image translation chunk received: chunk='\(chunk.prefix(50))...', fullContent length=\(fullContent.count)")
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    Logger.info("🔄 Updating UI with fullContent length: \(fullContent.count)")
                    // Add safety check to prevent rapid updates
                    if self.translationResult != fullContent {
                        self.translationResult = fullContent
                    }
                }
            },
            onComplete: { [weak self] result, quotaInfo in
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.isTranslating = false
                    if let result = result, !result.isEmpty {
                        self.translationResult = result
                        Logger.info("Image translation completed successfully")
                    } else {
                        self.errorMessage = "Translation completed but no result received"
                    }
                }
            },
            onError: { [weak self] error in
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.isTranslating = false
                    self.errorMessage = error
                    Logger.error("Image translation failed: \(error)")
                }
            }
        )
    }

    func submitFollowUpQuestion() {
        guard !followUpQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isProcessingFollowUp else { return }

        let question = followUpQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        Logger.info("Submitting follow-up question: \(question)")

        // Add user question to conversation history
        conversationHistory.append(ConversationItem(type: .userQuestion, content: question))
        Logger.info("💬 Added user question: '\(question)'. Total items: \(conversationHistory.count)")

        // Add temporary AI response for streaming updates with loading state
        var aiResponse = ConversationItem(type: .aiResponse, content: "")
        aiResponse.isLoading = true
        conversationHistory.append(aiResponse)
        let aiResponseIndex = conversationHistory.count - 1
        Logger.info("🤖 Added loading AI response at index \(aiResponseIndex). Total items: \(conversationHistory.count)")

        isProcessingFollowUp = true
        followUpQuestion = "" // Clear input immediately

        // Build conversation history from existing messages (exclude the current question and response)
        let previousHistory = conversationHistory.prefix(conversationHistory.count - 2) // Exclude current Q&A pair
        let conversationPairs = buildConversationPairs(from: Array(previousHistory))

        // Use chat API for follow-up questions
        TranslatorClient.shared.chat(
            message: question,
            originalText: "", // Image translation doesn't have original text
            translatedText: translationResult,
            conversationHistory: conversationPairs,
            onStreamUpdate: { [weak self] partialResponse in
                DispatchQueue.main.async {
                    // Update the specific AI response we just created (don't search for last AI response)
                    if let strongSelf = self, aiResponseIndex < strongSelf.conversationHistory.count {
                        Logger.info("🔄 Updating AI response at index \(aiResponseIndex) with content length: \(partialResponse.count)")
                        strongSelf.conversationHistory[aiResponseIndex].content = partialResponse
                        // Clear loading state when we start receiving actual content
                        if strongSelf.conversationHistory[aiResponseIndex].isLoading && !partialResponse.isEmpty {
                            strongSelf.conversationHistory[aiResponseIndex].isLoading = false
                        }
                    } else {
                        Logger.error("❌ Invalid AI response index \(aiResponseIndex), total items: \(self?.conversationHistory.count ?? 0)")
                    }
                }
            },
            completion: { [weak self] result in
                DispatchQueue.main.async {
                    self?.isProcessingFollowUp = false

                    switch result {
                    case .success(let response):
                        // Update the specific AI response with final content
                        if let strongSelf = self, aiResponseIndex < strongSelf.conversationHistory.count {
                            strongSelf.conversationHistory[aiResponseIndex].content = response
                            strongSelf.conversationHistory[aiResponseIndex].isLoading = false
                            Logger.info("✅ Follow-up question completed successfully")
                        }

                    case .failure(let error):
                        // Update the AI response with error message
                        if let strongSelf = self, aiResponseIndex < strongSelf.conversationHistory.count {
                            strongSelf.conversationHistory[aiResponseIndex].content = "Sorry, I encountered an error: \(error.localizedDescription)"
                            strongSelf.conversationHistory[aiResponseIndex].isLoading = false
                        }
                        Logger.error("❌ Follow-up question failed: \(error)")
                    }
                }
            }
        )
    }

    // Helper method to build conversation pairs from conversation history
    private func buildConversationPairs(from history: [ConversationItem]) -> [(userMessage: String, aiResponse: String)] {
        var pairs: [(userMessage: String, aiResponse: String)] = []

        var i = 0
        while i < history.count - 1 {
            let currentItem = history[i]
            if case .userQuestion = currentItem.type {
                let nextItem = history[i + 1]
                if case .aiResponse = nextItem.type {
                    pairs.append((userMessage: currentItem.content, aiResponse: nextItem.content))
                    i += 2 // Skip both items
                } else {
                    i += 1 // Skip lone user question
                }
            } else {
                i += 1 // Skip AI response or continue
            }
        }

        return pairs
    }

    func retryTranslation() {
        startTranslation()
    }

    func openImageInFinder() {
        guard let url = savedImageURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - Conversation Item
struct ConversationItem: Identifiable, Equatable {
    let id = UUID()
    let type: ConversationType
    var content: String
    let timestamp: Date = Date()
    var isLoading: Bool = false

    enum ConversationType {
        case userQuestion
        case aiResponse
    }
}

// MARK: - Image Translation SwiftUI View
struct ImageTranslationView: View {
    @ObservedObject var data: ImageTranslationData
    let onClose: () -> Void

    @State private var showImageFullSize = false

    var body: some View {
        HSplitView {
            // Left side - Translation results only
            VStack(spacing: 0) {
                // Translation result area (full height)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Translation Result")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Spacer()

                        Button(action: onClose) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if let errorMessage = data.errorMessage {
                                // Error message
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.red)
                                        Text("Translation Error")
                                            .fontWeight(.medium)
                                            .foregroundColor(.red)
                                    }

                                    Text(errorMessage)
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                }
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                            } else if !data.translationResult.isEmpty || data.isTranslating {
                                // Translation result with streaming support
                                VStack(alignment: .leading, spacing: 8) {
                                    if data.translationResult.isEmpty && data.isTranslating {
                                        // Initial loading state (no content yet)
                                        VStack(spacing: 12) {
                                            HStack {
                                                ProgressView()
                                                    .scaleEffect(1.2)
                                                Text("Processing image...")
                                                    .foregroundColor(.secondary)
                                            }
                                            Text("Please wait while we analyze and translate your screenshot")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .multilineTextAlignment(.center)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 40)
                                    } else {
                                        // Show translation content (either streaming or completed)
                                        HStack(alignment: .top) {
                                            // Always use Markdown rendering for better formatting, both during streaming and when completed
                                            ImageMarkdownText(markdown: data.translationResult)
                                                .textSelection(.enabled)
                                                .frame(maxWidth: .infinity, alignment: .leading)

                                            // Streaming indicator - shows real-time rendering is active
                                            if data.isTranslating {
                                                Text("|")
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundColor(.blue)
                                                    .opacity(0.8)
                                                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: data.isTranslating)
                                            }
                                        }
                                        .padding()

                                        // Streaming status indicator
                                        if data.isTranslating {
                                            HStack {
                                                ProgressView()
                                                    .scaleEffect(0.6)
                                                Text("Translating...")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                Spacer()
                                            }
                                            .padding(.horizontal)
                                            .padding(.bottom, 8)
                                        }
                                    }
                                }
                            } else {
                                // Initial state
                                VStack(spacing: 16) {
                                    Image(systemName: "photo.on.rectangle.angled")
                                        .font(.system(size: 48))
                                        .foregroundColor(.secondary)

                                    Text("Ready to translate your screenshot")
                                        .font(.title3)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)

                                    Text("Select language to start translation")
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                            }
                        }
                        .padding()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity) // Take all available space
                }
            }
            .frame(minWidth: 400)

            // Right side - Image (1/4 height) and Follow-up Questions (3/4 height)
            VStack(spacing: 0) {
                // Image preview section (1/4 of window height)
                VStack(spacing: 12) {
                    HStack {
                        Text("Screenshot")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Spacer()

                        // Show in Finder icon button (only show if image is saved)
                        if data.savedImageURL != nil {
                            Button(action: {
                                data.openImageInFinder()
                            }) {
                                Image(systemName: "folder")
                                    .font(.system(size: 16))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Show in Finder")
                        }
                    }

                    Button(action: {
                        showImageFullSize = true
                    }) {
                        Image(nsImage: data.image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 280, maxHeight: 140) // Reduced size for 1/4 height
                            .cornerRadius(8)
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Click to view full size")

                    // Language selection
                    Picker("Translate To", selection: $data.selectedTargetLanguage) {
                        ForEach(data.availableLanguages, id: \.0) { code, name in
                            Text(name).tag(code)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .disabled(data.isTranslating)

                    // Retry button (if there's an error)
                    if data.errorMessage != nil {
                        Button("Retry") {
                            data.retryTranslation()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding()
                .frame(height: 200) // Fixed height for 1/4 of typical window

                Divider()

                // Follow-up Questions section (3/4 of remaining height)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Follow-up Questions")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .padding(.horizontal)
                        .padding(.top)

                    // Conversation history
                    if !data.conversationHistory.isEmpty {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 12) {
                                    ForEach(data.conversationHistory) { item in
                                        ConversationBubble(item: item)
                                            .id(item.id) // Add ID for scrolling reference
                                    }


                                    // Bottom anchor for scrolling
                                    Color.clear
                                        .frame(height: 1)
                                        .id("bottom")
                                }
                                .padding(.horizontal)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onChange(of: data.conversationHistory.count) { _ in
                                // Auto-scroll to bottom when new messages are added
                                withAnimation(.easeOut(duration: 0.3)) {
                                    proxy.scrollTo("bottom", anchor: .bottom)
                                }
                            }
                            .onChange(of: data.conversationHistory.last?.content) { _ in
                                // Auto-scroll to bottom during streaming updates
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        proxy.scrollTo("bottom", anchor: .bottom)
                                    }
                                }
                            }
                            .onChange(of: data.isProcessingFollowUp) { isProcessing in
                                // Auto-scroll to bottom when processing starts (for better visibility)
                                if isProcessing {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        proxy.scrollTo("bottom", anchor: .bottom)
                                    }
                                }
                            }
                        }
                    } else if !data.translationResult.isEmpty && data.errorMessage == nil {
                        // Empty state for follow-up questions
                        VStack(spacing: 16) {
                            Image(systemName: "text.bubble")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)

                            Text("Ask follow-up questions")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)

                            Text("Get more details about the translation")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    } else {
                        Spacer() // Take up space when no translation available
                    }

                    // Input area (always at bottom when translation is available)
                    if !data.translationResult.isEmpty && data.errorMessage == nil {
                        Divider()
                            .padding(.horizontal)

                        HStack {
                            TextField("Ask a follow-up question...", text: $data.followUpQuestion)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .disabled(data.isProcessingFollowUp)
                                .onSubmit {
                                    data.submitFollowUpQuestion()
                                }

                            Button(action: {
                                data.submitFollowUpQuestion()
                            }) {
                                if data.isProcessingFollowUp {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                } else {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.title2)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(data.followUpQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || data.isProcessingFollowUp)
                        }
                        .padding()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity) // Take remaining space (3/4)
            }
            .frame(minWidth: 350, maxWidth: 400)
        }
        .sheet(isPresented: $showImageFullSize) {
            FullSizeImageView(image: data.image)
        }
    }
}

// MARK: - Loading Dots Animation
struct LoadingDotsView: View {
    @State private var animationPhase = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .frame(width: 6, height: 6)
                    .foregroundColor(.secondary)
                    .opacity(animationPhase == index ? 1.0 : 0.3)
                    .animation(.easeInOut(duration: 0.5), value: animationPhase)
            }
        }
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            stopAnimation()
        }
    }

    private func startAnimation() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                animationPhase = (animationPhase + 1) % 3
            }
        }
    }

    private func stopAnimation() {
        timer?.invalidate()
        timer = nil
        animationPhase = 0
    }
}

// MARK: - Conversation Bubble View
struct ConversationBubble: View {
    let item: ConversationItem

    var isUserQuestion: Bool {
        switch item.type {
        case .userQuestion:
            return true
        case .aiResponse:
            return false
        }
    }

    var body: some View {
        HStack {
            if isUserQuestion {
                Spacer()
            }

            VStack(alignment: isUserQuestion ? .trailing : .leading, spacing: 4) {
                if item.isLoading && !isUserQuestion {
                    // Show loading dots for AI responses that are being processed
                    HStack {
                        LoadingDotsView()
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                } else {
                    if isUserQuestion {
                        // User messages - plain text
                        Text(item.content)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.blue)
                            )
                            .foregroundColor(.white)
                            .textSelection(.enabled)
                    } else {
                        // AI messages - use markdown rendering
                        VStack(alignment: .leading, spacing: 0) {
                            FollowupMarkdownText(markdown: item.content)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                        .textSelection(.enabled)
                    }
                }

                Text(formatTime(item.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .opacity(0.7)
            }
            .frame(maxWidth: 280, alignment: isUserQuestion ? .trailing : .leading)

            if !isUserQuestion {
                Spacer()
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Full Size Image View
struct FullSizeImageView: View {
    let image: NSImage
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
            .padding()

            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

// MARK: - Enhanced Markdown Text Renderer (copied from TranslationResultWindow)
struct ImageMarkdownText: View {
    let markdown: String

    // Preprocess content to handle newlines properly
    private var processedText: String {
        var result = markdown

        // Handle escaped newlines if they exist
        if result.contains("\\n") {
            result = result.replacingOccurrences(of: "\\n", with: "\n")
        }

        // Normalize different line break formats to standard \n
        result = result.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "\n")

        // Normalize smart quotes to standard quotes
        result = result.replacingOccurrences(of: "\u{201C}", with: "\"")
        result = result.replacingOccurrences(of: "\u{201D}", with: "\"")
        result = result.replacingOccurrences(of: "\u{2018}", with: "'")
        result = result.replacingOccurrences(of: "\u{2019}", with: "'")

        return result
    }

    var body: some View {
        // Use custom rendering that properly handles newlines
        renderTextWithNewlines(processedText)
    }

    // Custom text renderer that properly handles markdown headers and formatting
    private func renderTextWithNewlines(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseMarkdownElements(text).enumerated()), id: \.offset) { index, element in
                Group {
                    switch element.type {
                    case .header:
                        Text(element.content)
                            .font(.headline)
                            .fontWeight(.bold)
                            .padding(.vertical, 4)
                    case .paragraph:
                        // Use custom text rendering with better bold formatting
                        renderFormattedText(element.content)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    case .listItem:
                        // Render list item with bullet point
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                                .padding(.top, 2)

                            renderFormattedText(element.content)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 2)
                    case .separator:
                        Divider()
                            .padding(.vertical, 4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Render text with proper bold formatting
    private func renderFormattedText(_ text: String) -> Text {
        // Parse bold text patterns manually for better control
        let parts = parseBoldText(text)

        if parts.count == 1 && !parts[0].isBold {
            // Simple case: no formatting needed
            return Text(parts[0].content)
        }

        // Build attributed text by combining parts
        var result = Text("")
        for part in parts {
            if part.isBold {
                result = result + Text(part.content).fontWeight(.bold)
            } else {
                result = result + Text(part.content)
            }
        }

        return result
    }

    // Parse text for bold formatting (** text **)
    private func parseBoldText(_ text: String) -> [TextPart] {
        var parts: [TextPart] = []
        var currentText = ""
        var i = text.startIndex

        while i < text.endIndex {
            if i < text.index(text.endIndex, offsetBy: -1) &&
               text[i] == "*" && text[text.index(after: i)] == "*" {

                // Found start of potential bold section
                if !currentText.isEmpty {
                    parts.append(TextPart(content: currentText, isBold: false))
                    currentText = ""
                }

                // Look for closing **
                let startIndex = text.index(i, offsetBy: 2)
                var endIndex = startIndex
                var foundClosing = false

                while endIndex < text.index(text.endIndex, offsetBy: -1) {
                    if text[endIndex] == "*" && text[text.index(after: endIndex)] == "*" {
                        foundClosing = true
                        break
                    }
                    endIndex = text.index(after: endIndex)
                }

                if foundClosing {
                    // Extract bold content
                    let boldContent = String(text[startIndex..<endIndex])
                    if !boldContent.isEmpty {
                        parts.append(TextPart(content: boldContent, isBold: true))
                    }
                    i = text.index(endIndex, offsetBy: 2) // Skip closing **
                } else {
                    // No closing **, treat as regular text
                    currentText.append(text[i])
                    i = text.index(after: i)
                }
            } else {
                currentText.append(text[i])
                i = text.index(after: i)
            }
        }

        // Add remaining text
        if !currentText.isEmpty {
            parts.append(TextPart(content: currentText, isBold: false))
        }

        return parts.isEmpty ? [TextPart(content: text, isBold: false)] : parts
    }

    // Parse text into markdown elements (headers, paragraphs, separators)
    private func parseMarkdownElements(_ text: String) -> [MarkdownElement] {
        var elements: [MarkdownElement] = []

        // Split by lines first to better handle headers followed by single newlines
        let lines = text.components(separatedBy: .newlines)
        var currentParagraph: [String] = []

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Check if it's a horizontal rule
            if trimmedLine == "---" {
                // Add any accumulated paragraph content first
                if !currentParagraph.isEmpty {
                    let paragraphContent = currentParagraph.joined(separator: "\n").trimmingCharacters(in: .whitespaces)
                    if !paragraphContent.isEmpty {
                        elements.append(MarkdownElement(type: .paragraph, content: paragraphContent))
                    }
                    currentParagraph.removeAll()
                }
                elements.append(MarkdownElement(type: .separator, content: ""))
                continue
            }

            // Check if it's a header (starts with #)
            if trimmedLine.hasPrefix("#") {
                // Add any accumulated paragraph content first
                if !currentParagraph.isEmpty {
                    let paragraphContent = currentParagraph.joined(separator: "\n").trimmingCharacters(in: .whitespaces)
                    if !paragraphContent.isEmpty {
                        elements.append(MarkdownElement(type: .paragraph, content: paragraphContent))
                    }
                    currentParagraph.removeAll()
                }

                // Extract header content (remove # characters and leading whitespace)
                var headerContent = trimmedLine
                while headerContent.hasPrefix("#") {
                    headerContent = String(headerContent.dropFirst())
                }
                headerContent = headerContent.trimmingCharacters(in: .whitespaces)

                if !headerContent.isEmpty {
                    elements.append(MarkdownElement(type: .header, content: headerContent))
                }
                continue
            }

            // Check if it's a list item (starts with -)
            if trimmedLine.hasPrefix("-") {
                // Add any accumulated paragraph content first
                if !currentParagraph.isEmpty {
                    let paragraphContent = currentParagraph.joined(separator: "\n").trimmingCharacters(in: .whitespaces)
                    if !paragraphContent.isEmpty {
                        elements.append(MarkdownElement(type: .paragraph, content: paragraphContent))
                    }
                    currentParagraph.removeAll()
                }

                // Extract list item content safely (remove - and leading whitespace)
                var listItemContent = ""
                if trimmedLine.hasPrefix("-") && trimmedLine.count > 1 {
                    listItemContent = String(trimmedLine.dropFirst()).trimmingCharacters(in: .whitespaces)
                }

                if !listItemContent.isEmpty {
                    elements.append(MarkdownElement(type: .listItem, content: listItemContent))
                }
                continue
            }

            // Handle empty lines
            if trimmedLine.isEmpty {
                // If we have accumulated content, finalize the current paragraph
                if !currentParagraph.isEmpty {
                    let paragraphContent = currentParagraph.joined(separator: "\n").trimmingCharacters(in: .whitespaces)
                    if !paragraphContent.isEmpty {
                        elements.append(MarkdownElement(type: .paragraph, content: paragraphContent))
                    }
                    currentParagraph.removeAll()
                }
                continue
            }

            // Regular line - add to current paragraph
            currentParagraph.append(line)
        }

        // Add any remaining paragraph content
        if !currentParagraph.isEmpty {
            let paragraphContent = currentParagraph.joined(separator: "\n").trimmingCharacters(in: .whitespaces)
            if !paragraphContent.isEmpty {
                elements.append(MarkdownElement(type: .paragraph, content: paragraphContent))
            }
        }

        return elements
    }

    // Helper structures for markdown parsing
    private struct MarkdownElement {
        enum ElementType {
            case header
            case paragraph
            case separator
            case listItem
        }

        let type: ElementType
        let content: String
    }

    // Helper structure for text formatting
    private struct TextPart {
        let content: String
        let isBold: Bool
    }
}

// MARK: - Follow-up Markdown Text Renderer (from TranslationResultWindow)
struct FollowupMarkdownText: View {
    let markdown: String

    // Preprocess content to handle newlines properly
    private var processedText: String {
        var result = markdown

        // Handle escaped newlines if they exist
        if result.contains("\\n") {
            result = result.replacingOccurrences(of: "\\n", with: "\n")
        }

        // Normalize different line break formats to standard \n
        result = result.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "\n")

        // Normalize smart quotes to standard quotes
        result = result.replacingOccurrences(of: "\u{201C}", with: "\"")
        result = result.replacingOccurrences(of: "\u{201D}", with: "\"")
        result = result.replacingOccurrences(of: "\u{2018}", with: "'")
        result = result.replacingOccurrences(of: "\u{2019}", with: "'")

        return result
    }

    var body: some View {
        // Use custom rendering that properly handles newlines, optimized for streaming
        renderTextWithNewlines(processedText)
    }

    // Custom text renderer that properly handles \n and \n\n
    private func renderTextWithNewlines(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(parseTextBlocks(text).enumerated()), id: \.offset) { index, block in
                switch block.type {
                case .paragraph:
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(0..<block.lines.count, id: \.self) { lineIndex in
                            let line = block.lines[lineIndex]
                            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                            if !trimmedLine.isEmpty {
                                // Check if this line is a list item
                                if trimmedLine.hasPrefix("-") {
                                    // Render as list item
                                    HStack(alignment: .top, spacing: 6) {
                                        Text("•")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.primary)
                                            .padding(.top, 1)

                                        // Extract list content safely
                                        let listContent = extractListContent(from: trimmedLine)

                                        if #available(macOS 12.0, *) {
                                            // Try to render with markdown for formatting
                                            if let attributedString = try? AttributedString(markdown: listContent) {
                                                Text(attributedString)
                                                    .font(.system(size: 13))
                                                    .multilineTextAlignment(.leading)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            } else {
                                                Text(listContent)
                                                    .font(.system(size: 13))
                                                    .multilineTextAlignment(.leading)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        } else {
                                            Text(listContent)
                                                .font(.system(size: 13))
                                                .multilineTextAlignment(.leading)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    .padding(.vertical, 1)
                                } else {
                                    // Render as regular line
                                    if #available(macOS 12.0, *) {
                                        // Try to render with markdown for formatting
                                        if let attributedString = try? AttributedString(markdown: line) {
                                            Text(attributedString)
                                                .font(.system(size: 13))
                                                .multilineTextAlignment(.leading)
                                                .fixedSize(horizontal: false, vertical: true)
                                        } else {
                                            Text(line)
                                                .font(.system(size: 13))
                                                .multilineTextAlignment(.leading)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    } else {
                                        Text(line)
                                            .font(.system(size: 13))
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, block.isLastParagraph ? 0 : 8) // Add spacing between paragraphs

                case .separator:
                    Divider()
                        .padding(.vertical, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Parse text into blocks handling \n and \n\n correctly
    private func parseTextBlocks(_ text: String) -> [FollowupTextBlock] {
        var blocks: [FollowupTextBlock] = []

        // Split by double newlines to get paragraphs
        let paragraphs = text.components(separatedBy: "\n\n")

        for (index, paragraph) in paragraphs.enumerated() {
            let trimmedParagraph = paragraph.trimmingCharacters(in: .whitespaces)

            if trimmedParagraph.isEmpty {
                continue
            }

            // Check if it's a horizontal rule
            if trimmedParagraph == "---" {
                blocks.append(FollowupTextBlock(type: .separator, lines: [], isLastParagraph: false))
            } else {
                // Split paragraph by single newlines to get lines
                let lines = paragraph.components(separatedBy: "\n")
                let isLast = (index == paragraphs.count - 1)
                blocks.append(FollowupTextBlock(type: .paragraph, lines: lines, isLastParagraph: isLast))
            }
        }

        return blocks
    }

    // Helper function to extract list content safely
    private func extractListContent(from line: String) -> String {
        if line.hasPrefix("-") && line.count > 1 {
            return String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    // Helper structures for text parsing
    private struct FollowupTextBlock {
        enum BlockType {
            case paragraph
            case separator
        }

        let type: BlockType
        let lines: [String]
        let isLastParagraph: Bool
    }
}