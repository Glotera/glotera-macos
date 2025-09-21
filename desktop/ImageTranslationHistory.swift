import Foundation
import Cocoa

// MARK: - Image Translation History Manager
class ImageTranslationHistoryManager: ObservableObject {
    static let shared = ImageTranslationHistoryManager()

    @Published var imageTranslations: [ImageTranslationRecord] = []
    private let maxHistoryCount = 50

    private init() {
        loadHistory()
    }

    func addImageTranslation(image: NSImage, originalBase64: String, translationResult: String, targetLanguage: String, savedImageURL: URL?) {
        let record = ImageTranslationRecord(
            id: UUID(),
            image: image,
            originalBase64: originalBase64,
            translationResult: translationResult,
            targetLanguage: targetLanguage,
            savedImageURL: savedImageURL,
            timestamp: Date()
        )

        DispatchQueue.main.async { [weak self] in
            self?.imageTranslations.insert(record, at: 0) // Insert at beginning for newest first

            // Keep only the most recent translations
            if let self = self, self.imageTranslations.count > self.maxHistoryCount {
                self.imageTranslations = Array(self.imageTranslations.prefix(self.maxHistoryCount))
            }

            self?.saveHistory()
        }

        Logger.info("Added image translation to history: \(translationResult.prefix(50))...")
    }

    func removeImageTranslation(withId id: UUID) {
        DispatchQueue.main.async { [weak self] in
            self?.imageTranslations.removeAll { $0.id == id }
            self?.saveHistory()
        }
    }

    func clearHistory() {
        DispatchQueue.main.async { [weak self] in
            self?.imageTranslations.removeAll()
            self?.saveHistory()
        }
    }

    private func saveHistory() {
        // Save to UserDefaults (lightweight approach)
        let encoder = JSONEncoder()
        do {
            // Only save metadata, not the actual images (too large)
            let metadata = imageTranslations.map { record in
                ImageTranslationMetadata(
                    id: record.id,
                    translationResult: record.translationResult,
                    targetLanguage: record.targetLanguage,
                    savedImageURL: record.savedImageURL,
                    timestamp: record.timestamp
                )
            }

            let data = try encoder.encode(metadata)
            UserDefaults.standard.set(data, forKey: "image_translation_history")
            Logger.debug("Saved image translation history: \(metadata.count) items")
        } catch {
            Logger.error("Failed to save image translation history: \(error)")
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: "image_translation_history") else {
            Logger.debug("No existing image translation history found")
            return
        }

        let decoder = JSONDecoder()
        do {
            let metadata = try decoder.decode([ImageTranslationMetadata].self, from: data)

            // Only load metadata, not images (they would be too large to persist)
            // Images will be loaded from savedImageURL when needed
            var loadedRecords: [ImageTranslationRecord] = []

            for meta in metadata {
                // Try to load image from saved URL if available
                var image: NSImage?
                if let savedURL = meta.savedImageURL,
                   let loadedImage = NSImage(contentsOf: savedURL) {
                    image = loadedImage
                } else {
                    // Create a placeholder image if original is not available
                    image = createPlaceholderImage()
                }

                let record = ImageTranslationRecord(
                    id: meta.id,
                    image: image ?? createPlaceholderImage(),
                    originalBase64: "", // Not persisted
                    translationResult: meta.translationResult,
                    targetLanguage: meta.targetLanguage,
                    savedImageURL: meta.savedImageURL,
                    timestamp: meta.timestamp
                )

                loadedRecords.append(record)
            }

            imageTranslations = loadedRecords
            Logger.info("Loaded image translation history: \(loadedRecords.count) items")
        } catch {
            Logger.error("Failed to load image translation history: \(error)")
        }
    }

    private func createPlaceholderImage() -> NSImage {
        let size = NSSize(width: 100, height: 100)
        let image = NSImage(size: size)

        image.lockFocus()

        // Draw a simple placeholder
        NSColor.lightGray.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        // Draw icon
        let iconRect = NSRect(x: 30, y: 30, width: 40, height: 40)
        NSColor.gray.setFill()
        let iconPath = NSBezierPath(ovalIn: iconRect)
        iconPath.fill()

        image.unlockFocus()
        return image
    }
}

// MARK: - Data Models
struct ImageTranslationRecord: Identifiable {
    let id: UUID
    let image: NSImage
    let originalBase64: String
    let translationResult: String
    let targetLanguage: String
    let savedImageURL: URL?
    let timestamp: Date
}

struct ImageTranslationMetadata: Codable {
    let id: UUID
    let translationResult: String
    let targetLanguage: String
    let savedImageURL: URL?
    let timestamp: Date
}

// MARK: - Extended ChatMessage for Image Support
extension ChatMessage {
    // Add image support to existing ChatMessage structure
    static func createImageMessage(
        image: NSImage,
        translationResult: String,
        targetLanguage: String,
        savedImageURL: URL?
    ) -> ChatMessage {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)

        var message = ChatMessage(
            messageType: "image",
            content: "[Image Translation]",
            sender: "Image Translation",
            timestamp: timestamp,
            isFromMe: false
        )

        // Set translation fields
        message.contentTranslation = translationResult
        message.contentLanguage = nil
        message.contentTranslationLanguage = targetLanguage
        message.contentHash = UUID().uuidString

        return message
    }
}

// MARK: - Image Translation History View
import SwiftUI

struct ImageTranslationHistoryView: View {
    @StateObject private var historyManager = ImageTranslationHistoryManager.shared
    @State private var selectedRecord: ImageTranslationRecord?

    var body: some View {
        NavigationView {
            VStack {
                if historyManager.imageTranslations.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text("No image translations yet")
                            .font(.title3)
                            .foregroundColor(.secondary)

                        Text("Use Shift+Option+S to capture and translate screenshots")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(historyManager.imageTranslations) { record in
                        ImageTranslationRow(record: record) {
                            selectedRecord = record
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("Image Translations")
            .toolbar {
                if !historyManager.imageTranslations.isEmpty {
                    Button("Clear All") {
                        historyManager.clearHistory()
                    }
                }
            }
        }
        .sheet(item: $selectedRecord) { record in
            ImageTranslationDetailView(record: record)
        }
    }
}

struct ImageTranslationRow: View {
    let record: ImageTranslationRecord
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            Image(nsImage: record.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 60, height: 60)
                .clipped()
                .cornerRadius(8)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(record.translationResult)
                    .font(.body)
                    .lineLimit(2)
                    .foregroundColor(.primary)

                HStack {
                    Text("→ \(languageName(for: record.targetLanguage))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(formatTimestamp(record.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }

    private func languageName(for code: String) -> String {
        let languages = [
            "en": "English", "zh": "Chinese", "ja": "Japanese", "ko": "Korean",
            "es": "Spanish", "fr": "French", "de": "German", "ru": "Russian"
        ]
        return languages[code] ?? code
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct ImageTranslationDetailView: View {
    let record: ImageTranslationRecord
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Image Translation Detail")
                    .font(.headline)

                Spacer()

                Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
            .padding()

            ScrollView {
                VStack(spacing: 20) {
                    // Image
                    Image(nsImage: record.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 300)
                        .cornerRadius(12)
                        .shadow(radius: 4)

                    // Translation
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Translation")
                            .font(.headline)

                        Text(record.translationResult)
                            .textSelection(.enabled)
                            .padding()
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                    }

                    // Metadata
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Translate To:")
                            Spacer()
                            Text(languageName(for: record.targetLanguage))
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Timestamp:")
                            Spacer()
                            Text(DateFormatter.localizedString(from: record.timestamp, dateStyle: .medium, timeStyle: .short))
                                .foregroundColor(.secondary)
                        }

                        if record.savedImageURL != nil {
                            Button("Show in Finder") {
                                if let url = record.savedImageURL {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                .padding()
            }
        }
        .frame(width: 600, height: 700)
    }

    private func languageName(for code: String) -> String {
        let languages = [
            "en": "English", "zh": "Chinese", "ja": "Japanese", "ko": "Korean",
            "es": "Spanish", "fr": "French", "de": "German", "ru": "Russian"
        ]
        return languages[code] ?? code
    }
}