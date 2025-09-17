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
    @Published var selectedTargetLanguage: String = "en"
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

    init(image: NSImage, base64Data: String, savedImageURL: URL?) {
        self.image = image
        self.base64Data = base64Data
        self.savedImageURL = savedImageURL

        // Load user's preferred language from settings
        self.selectedTargetLanguage = ConfigManager.shared.getUserPreferredLanguage()

        Logger.info("ImageTranslationData initialized with target language: \(selectedTargetLanguage)")
    }

    func startTranslation() {
        guard !isTranslating else { return }

        Logger.info("Starting image translation to: \(selectedTargetLanguage)")
        isTranslating = true
        errorMessage = nil
        translationResult = ""

        // Use streaming translation for better user experience
        TranslatorClient.shared.translateImageStream(
            base64Data: base64Data,
            to: selectedTargetLanguage,
            onChunk: { [weak self] chunk, fullContent in
                Logger.info("📝 Image translation chunk received: chunk='\(chunk.prefix(50))...', fullContent length=\(fullContent.count)")
                DispatchQueue.main.async {
                    Logger.info("🔄 Updating UI with fullContent length: \(fullContent.count)")
                    self?.translationResult = fullContent
                }
            },
            onComplete: { [weak self] result, quotaInfo in
                DispatchQueue.main.async {
                    self?.isTranslating = false
                    if let result = result, !result.isEmpty {
                        self?.translationResult = result
                        Logger.info("Image translation completed successfully")
                    } else {
                        self?.errorMessage = "Translation completed but no result received"
                    }
                }
            },
            onError: { [weak self] error in
                DispatchQueue.main.async {
                    self?.isTranslating = false
                    self?.errorMessage = error
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

        // Add temporary AI response for streaming updates
        let aiResponse = ConversationItem(type: .aiResponse, content: "")
        conversationHistory.append(aiResponse)
        let aiResponseIndex = conversationHistory.count - 1
        Logger.info("🤖 Added empty AI response at index \(aiResponseIndex). Total items: \(conversationHistory.count)")

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
                            Logger.info("✅ Follow-up question completed successfully")
                        }

                    case .failure(let error):
                        // Update the AI response with error message
                        if let strongSelf = self, aiResponseIndex < strongSelf.conversationHistory.count {
                            strongSelf.conversationHistory[aiResponseIndex].content = "Sorry, I encountered an error: \(error.localizedDescription)"
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
            // Left side - Image and controls
            VStack(spacing: 16) {
                // Image preview
                VStack {
                    Text("Screenshot")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Button(action: {
                        showImageFullSize = true
                    }) {
                        Image(nsImage: data.image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 300, maxHeight: 200)
                            .cornerRadius(8)
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Click to view full size")
                }

                // Language selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Translate to:")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Picker("Target Language", selection: $data.selectedTargetLanguage) {
                        ForEach(data.availableLanguages, id: \.0) { code, name in
                            Text(name).tag(code)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .disabled(data.isTranslating)
                }

                // Action buttons
                VStack(spacing: 8) {
                    Button(action: {
                        data.startTranslation()
                    }) {
                        HStack {
                            if data.isTranslating {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text(data.isTranslating ? "Translating..." : "Translate Image")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(data.isTranslating)

                    if data.errorMessage != nil {
                        Button("Retry") {
                            data.retryTranslation()
                        }
                        .buttonStyle(.bordered)
                    }

                    if data.savedImageURL != nil {
                        Button("Show in Finder") {
                            data.openImageInFinder()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Spacer()
            }
            .padding()
            .frame(minWidth: 350, maxWidth: 400)

            // Right side - Translation results and conversation
            VStack(spacing: 0) {
                // Translation result area
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
                            } else if data.isTranslating {
                                // Loading state
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
                            } else if !data.translationResult.isEmpty {
                                // Translation result with markdown rendering
                                ImageMarkdownText(data.translationResult)
                                    .textSelection(.enabled)
                                    .padding()
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(8)
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

                                    Text("Click 'Translate Image' to get started")
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                            }
                        }
                        .padding()
                    }
                    .frame(maxHeight: 300)
                }

                Divider()

                // Conversation area for follow-up questions
                if !data.translationResult.isEmpty && data.errorMessage == nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Follow-up Questions")
                            .font(.headline)
                            .foregroundColor(.primary)

                        // Conversation history
                        if !data.conversationHistory.isEmpty {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 12) {
                                    ForEach(data.conversationHistory) { item in
                                        ConversationBubble(item: item)
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .frame(maxHeight: 200)
                        }

                        // Input area
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
                    }
                    .padding()
                }

                Spacer()
            }
            .frame(minWidth: 400)
        }
        .sheet(isPresented: $showImageFullSize) {
            FullSizeImageView(image: data.image)
        }
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
                Text(item.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isUserQuestion ?
                                  Color.blue : Color(NSColor.controlBackgroundColor))
                    )
                    .foregroundColor(isUserQuestion ? .white : .primary)
                    .textSelection(.enabled)

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

// MARK: - Image Translation Markdown Text View
struct ImageMarkdownText: View {
    let content: String

    init(_ content: String) {
        self.content = content
    }

    var body: some View {
        // Basic markdown rendering - this can be enhanced with a proper markdown library
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parseMarkdown(content), id: \.0) { index, section in
                Text(section.text)
                    .font(section.font)
                    .fontWeight(section.fontWeight)
                    .foregroundColor(section.color)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func parseMarkdown(_ text: String) -> [(Int, MarkdownSection)] {
        let lines = text.components(separatedBy: .newlines)
        var sections: [(Int, MarkdownSection)] = []

        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedLine.hasPrefix("# ") {
                // H1
                let text = String(trimmedLine.dropFirst(2))
                sections.append((index, MarkdownSection(text: text, font: .title, fontWeight: .bold, color: .primary)))
            } else if trimmedLine.hasPrefix("## ") {
                // H2
                let text = String(trimmedLine.dropFirst(3))
                sections.append((index, MarkdownSection(text: text, font: .title2, fontWeight: .semibold, color: .primary)))
            } else if trimmedLine.hasPrefix("### ") {
                // H3
                let text = String(trimmedLine.dropFirst(4))
                sections.append((index, MarkdownSection(text: text, font: .title3, fontWeight: .medium, color: .primary)))
            } else if trimmedLine.hasPrefix("**") && trimmedLine.hasSuffix("**") && trimmedLine.count > 4 {
                // Bold
                let text = String(trimmedLine.dropFirst(2).dropLast(2))
                sections.append((index, MarkdownSection(text: text, font: .body, fontWeight: .bold, color: .primary)))
            } else if !trimmedLine.isEmpty {
                // Regular text
                sections.append((index, MarkdownSection(text: trimmedLine, font: .body, fontWeight: .regular, color: .primary)))
            }
        }

        return sections
    }
}

struct MarkdownSection {
    let text: String
    let font: Font
    let fontWeight: Font.Weight
    let color: Color
}