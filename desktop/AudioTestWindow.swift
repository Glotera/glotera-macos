import Cocoa
import SwiftUI
import AVFoundation

// MARK: - Audio Test Window
class AudioTestWindow: NSWindow {
    init() {
        let windowSize = NSSize(width: 500, height: 400)

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

        self.title = "Audio Test"
        self.level = .normal
        self.isReleasedWhenClosed = false

        let audioTestView = AudioTestView()
        self.contentView = NSHostingView(rootView: audioTestView)
    }
}

// MARK: - Audio Test Data Model
class AudioTestData: NSObject, ObservableObject {
    @Published var textToSpeak: String = "Hello, this is a test of the speech synthesis system."
    @Published var selectedLanguage: String = "en"
    @Published var isPlaying: Bool = false
    @Published var availableVoices: [NSSpeechSynthesizer.VoiceName] = []
    @Published var selectedVoice: NSSpeechSynthesizer.VoiceName?

    private var speechSynthesizer: NSSpeechSynthesizer?

    // Available languages for testing
    let languages = [
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

    override init() {
        super.init()
        loadAvailableVoices()
        setupSpeechSynthesizer()
    }

    private func loadAvailableVoices() {
        availableVoices = NSSpeechSynthesizer.availableVoices

        // Set default voice based on selected language
        updateVoiceForLanguage(selectedLanguage)
    }

    private func setupSpeechSynthesizer() {
        speechSynthesizer = NSSpeechSynthesizer()
        speechSynthesizer?.delegate = self

        if let voice = selectedVoice {
            speechSynthesizer?.setVoice(voice)
        }
    }

    func updateVoiceForLanguage(_ languageCode: String) {
        // Log all available voices for debugging
        Logger.info("=== Available voices for language: \(languageCode) ===")
        for voice in availableVoices {
            let attributes = NSSpeechSynthesizer.attributes(forVoice: voice)
            if let voiceLocale = attributes[.localeIdentifier] as? String,
               let voiceName = attributes[.name] as? String {
                if voiceLocale.lowercased().hasPrefix(languageCode.lowercased()) {
                    Logger.info("  - \(voice.rawValue) | Name: \(voiceName) | Locale: \(voiceLocale)")
                }
            }
        }

        // Map language codes to preferred voice names - Try multiple voices in order of preference
        let voiceMapping: [String: [String]] = [
            "en": [
                "com.apple.ttsbundle.siri_female_en-US_compact",  // Siri female voice (most natural)
                "com.apple.ttsbundle.siri_male_en-US_compact",    // Siri male voice
                "com.apple.speech.synthesis.voice.Alex",          // Alex (high quality male)
                "com.apple.voice.enhanced.en-US.Samantha",        // Enhanced Samantha
                "com.apple.speech.synthesis.voice.samantha",      // Basic Samantha
                "com.apple.speech.synthesis.voice.Victoria",      // Victoria
                "com.apple.speech.synthesis.voice.Fred"           // Fred
            ],
            "zh": ["com.apple.speech.synthesis.voice.Tingting", "com.apple.speech.synthesis.voice.Meijia"],
            "ja": ["com.apple.speech.synthesis.voice.Kyoko", "com.apple.speech.synthesis.voice.Otoya"],
            "ko": ["com.apple.speech.synthesis.voice.Yuna", "com.apple.speech.synthesis.voice.Sora"],
            "es": ["com.apple.voice.enhanced.es-ES.Monica", "com.apple.speech.synthesis.voice.Monica"],
            "fr": ["com.apple.voice.enhanced.fr-FR.Aurelie", "com.apple.speech.synthesis.voice.Amelie"],
            "de": ["com.apple.voice.enhanced.de-DE.Anna", "com.apple.speech.synthesis.voice.Anna"],
            "ru": ["com.apple.speech.synthesis.voice.Milena", "com.apple.speech.synthesis.voice.Yuri"],
            "pt": ["com.apple.speech.synthesis.voice.Luciana", "com.apple.speech.synthesis.voice.Felipe"],
            "it": ["com.apple.voice.enhanced.it-IT.Alice", "com.apple.speech.synthesis.voice.Alice"],
            "ar": ["com.apple.speech.synthesis.voice.Maged", "com.apple.speech.synthesis.voice.Laila"],
            "hi": ["com.apple.speech.synthesis.voice.Lekha", "com.apple.speech.synthesis.voice.Neel"]
        ]

        // Try to find the preferred voices in order
        if let preferredVoiceNames = voiceMapping[languageCode] {
            for voiceName in preferredVoiceNames {
                let preferredVoice = NSSpeechSynthesizer.VoiceName(rawValue: voiceName)
                if availableVoices.contains(preferredVoice) {
                    selectedVoice = preferredVoice
                    speechSynthesizer?.setVoice(preferredVoice)

                    // Get and log voice details
                    let attributes = NSSpeechSynthesizer.attributes(forVoice: preferredVoice)
                    let displayName = attributes[.name] as? String ?? "Unknown"
                    Logger.info("✅ Selected voice: \(displayName) (\(voiceName)) for language: \(languageCode)")
                    return
                }
            }
        }

        // Fallback: Find best available voice that matches the language code
        var candidateVoices: [(voice: NSSpeechSynthesizer.VoiceName, score: Int, name: String)] = []

        for voice in availableVoices {
            let voiceAttributes = NSSpeechSynthesizer.attributes(forVoice: voice)
            if let voiceLanguage = voiceAttributes[.localeIdentifier] as? String,
               let voiceName = voiceAttributes[.name] as? String {
                // Check if voice language starts with our language code
                if voiceLanguage.lowercased().hasPrefix(languageCode.lowercased()) {
                    var score = 0
                    let voiceId = voice.rawValue.lowercased()

                    // Scoring system for voice quality
                    if voiceId.contains("siri") {
                        score += 100  // Siri voices are highest quality
                    }
                    if voiceId.contains("enhanced") {
                        score += 50   // Enhanced voices are better
                    }
                    if voiceId.contains("premium") {
                        score += 40   // Premium voices
                    }
                    if voiceId.contains("alex") && languageCode == "en" {
                        score += 60   // Alex is particularly good for English
                    }
                    if voiceId.contains("compact") {
                        score -= 10   // Compact voices are smaller/lower quality
                    }

                    candidateVoices.append((voice: voice, score: score, name: voiceName))
                }
            }
        }

        // Select the best scoring voice
        if !candidateVoices.isEmpty {
            candidateVoices.sort { $0.score > $1.score }
            let bestVoice = candidateVoices[0]
            selectedVoice = bestVoice.voice
            speechSynthesizer?.setVoice(bestVoice.voice)
            Logger.info("✅ Selected best available voice: \(bestVoice.name) (score: \(bestVoice.score)) for language: \(languageCode)")
            return
        }

        // Use default voice if no match found
        let defaultVoice = NSSpeechSynthesizer.defaultVoice
        selectedVoice = defaultVoice
        speechSynthesizer?.setVoice(defaultVoice)
        Logger.info("⚠️ Using system default voice for language: \(languageCode)")
    }

    func togglePlayback() {
        if isPlaying {
            stopSpeaking()
        } else {
            startSpeaking()
        }
    }

    // Get sample text for language
    func getSampleText(for languageCode: String) -> String {
        switch languageCode {
        case "en":
            return "Hello, this is a test of the speech synthesis system."
        case "zh":
            return "你好，这是语音合成系统的测试。"
        case "ja":
            return "こんにちは、これは音声合成システムのテストです。"
        case "ko":
            return "안녕하세요, 이것은 음성 합성 시스템의 테스트입니다."
        case "es":
            return "Hola, esta es una prueba del sistema de síntesis de voz."
        case "fr":
            return "Bonjour, ceci est un test du système de synthèse vocale."
        case "de":
            return "Hallo, dies ist ein Test des Sprachsynthesesystems."
        case "ru":
            return "Привет, это тест системы синтеза речи."
        case "pt":
            return "Olá, este é um teste do sistema de síntese de voz."
        case "it":
            return "Ciao, questo è un test del sistema di sintesi vocale."
        case "ar":
            return "مرحبا، هذا اختبار لنظام تركيب الكلام."
        case "hi":
            return "नमस्ते, यह वाक् संश्लेषण प्रणाली का परीक्षण है।"
        default:
            return "Hello, this is a test of the speech synthesis system."
        }
    }

    private func startSpeaking() {
        guard !textToSpeak.isEmpty else { return }

        // Update voice for current language
        updateVoiceForLanguage(selectedLanguage)

        speechSynthesizer?.startSpeaking(textToSpeak)
        isPlaying = true
        Logger.info("Started speaking: \(textToSpeak.prefix(50))...")
    }

    private func stopSpeaking() {
        speechSynthesizer?.stopSpeaking()
        isPlaying = false
        Logger.info("Stopped speaking")
    }

    func getVoiceInfo() -> String {
        guard let voice = selectedVoice else { return "No voice selected" }

        let attributes = NSSpeechSynthesizer.attributes(forVoice: voice)
        var info = "Current Voice: \(attributes[.name] ?? "Unknown")\n"
        info += "Language: \(attributes[.localeIdentifier] ?? "Unknown")\n"
        info += "Identifier: \(voice.rawValue)\n"
        info += "\n--- Available Voices for \(selectedLanguage.uppercased()) ---\n"

        // List all available voices for current language
        var voicesForLanguage: [String] = []
        for availableVoice in availableVoices {
            let voiceAttrs = NSSpeechSynthesizer.attributes(forVoice: availableVoice)
            if let voiceLocale = voiceAttrs[.localeIdentifier] as? String,
               let voiceName = voiceAttrs[.name] as? String {
                if voiceLocale.lowercased().hasPrefix(selectedLanguage.lowercased()) {
                    let quality = getVoiceQuality(availableVoice.rawValue)
                    voicesForLanguage.append("\(voiceName) [\(quality)]")
                }
            }
        }

        if voicesForLanguage.isEmpty {
            info += "No specific voices found for \(selectedLanguage)"
        } else {
            info += voicesForLanguage.joined(separator: "\n")
        }

        return info
    }

    private func getVoiceQuality(_ voiceId: String) -> String {
        let id = voiceId.lowercased()
        if id.contains("siri") {
            return "Siri"
        } else if id.contains("enhanced") {
            return "Enhanced"
        } else if id.contains("premium") {
            return "Premium"
        } else if id.contains("compact") {
            return "Compact"
        } else {
            return "Standard"
        }
    }
}

// MARK: - NSSpeechSynthesizerDelegate
extension AudioTestData: NSSpeechSynthesizerDelegate {
    func speechSynthesizer(_ sender: NSSpeechSynthesizer, didFinishSpeaking finishedSpeaking: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            Logger.info("Speech synthesis completed")
        }
    }
}

// MARK: - Audio Test View
struct AudioTestView: View {
    @StateObject private var audioData = AudioTestData()

    var body: some View {
        VStack(spacing: 20) {
            Text("Audio Test")
                .font(.title)
                .fontWeight(.bold)

            // Text input area
            VStack(alignment: .leading, spacing: 8) {
                Text("Text to Speak:")
                    .font(.headline)

                TextEditor(text: $audioData.textToSpeak)
                    .font(.system(size: 14))
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }

            // Language selection
            HStack {
                Text("Language:")
                    .font(.headline)

                Picker("Language", selection: $audioData.selectedLanguage) {
                    ForEach(audioData.languages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 200)
                .onChange(of: audioData.selectedLanguage) { newValue in
                    audioData.updateVoiceForLanguage(newValue)
                    // Update text to sample text for the selected language
                    audioData.textToSpeak = audioData.getSampleText(for: newValue)
                }

                Spacer()
            }

            // Voice information
            VStack(alignment: .leading, spacing: 4) {
                Text("Voice Information:")
                    .font(.headline)

                Text(audioData.getVoiceInfo())
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
            }

            // Playback controls
            HStack(spacing: 20) {
                Button(action: {
                    audioData.togglePlayback()
                }) {
                    HStack {
                        Image(systemName: audioData.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title2)
                        Text(audioData.isPlaying ? "Stop" : "Play")
                            .font(.headline)
                    }
                    .frame(width: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if audioData.isPlaying {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Speaking...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding()
        .frame(width: 500, height: 400)
    }
}