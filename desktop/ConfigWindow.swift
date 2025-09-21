import SwiftUI
import Cocoa

// Simple language structure for picker
struct SimpleLanguage: Identifiable {
    let id = UUID()
    let code: String
    let name: String
}

// Configuration categories
enum ConfigCategory: String, CaseIterable {
    case languageTriggers = "Language Triggers"
    case favoriteSettings = "Favorite Settings"
    case about = "About Glotera"
    
    var systemImage: String {
        switch self {
        case .languageTriggers: return "globe"
        case .favoriteSettings: return "heart"
        case .about: return "info.circle"
        }
    }
}

// Language configuration window
class ConfigWindow: NSWindow {
    
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        self.title = "Glotera Configuration"
        self.center()
        self.isReleasedWhenClosed = false
        
        // Set minimum and maximum size to prevent unwanted resizing
        self.minSize = NSSize(width: 800, height: 500)
        self.maxSize = NSSize(width: 1200, height: 800)
        
        // Create SwiftUI view
        let contentView = LanguageConfigView { [weak self] in
            self?.close()
        }
        
        self.contentView = NSHostingView(rootView: contentView)
    }
    
    func show() {
        // 多重确保窗口显示在最前面
        self.makeKeyAndOrderFront(nil)
        self.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        
        // 确保窗口获得焦点
        DispatchQueue.main.async {
            self.makeKey()
        }
    }
}

// SwiftUI main view
struct LanguageConfigView: View {
    @StateObject private var viewModel = LanguageConfigViewModel()
    @State private var selectedCategory: ConfigCategory = .languageTriggers
    let onClose: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            // Left sidebar
            VStack(spacing: 0) {
                // Sidebar header
                HStack {
                    Text("Configuration")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // Category list
                VStack(spacing: 2) {
                    ForEach(ConfigCategory.allCases, id: \.self) { category in
                        Button(action: {
                            selectedCategory = category
                        }) {
                            HStack {
                                Image(systemName: category.systemImage)
                                    .foregroundColor(selectedCategory == category ? .white : .primary)
                                    .frame(width: 16)
                                
                                Text(category.rawValue)
                                    .foregroundColor(selectedCategory == category ? .white : .primary)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                selectedCategory == category ?
                                Color.accentColor :
                                Color.clear
                            )
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                    }
                    
                    Spacer()
                }
                .padding(.top, 8)
            }
            .frame(width: 200)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            // Right content area
            VStack(spacing: 0) {
                // Top toolbar
                HStack {
                    Text(selectedCategory.rawValue)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    // Action buttons based on category
                    if selectedCategory == .languageTriggers {
                        Button("Reset to Default") {
                            viewModel.resetToDefaults()
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Button("Close") {
                        onClose()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // Content area
                Group {
                    switch selectedCategory {
                    case .languageTriggers:
                        LanguageTriggersView(viewModel: viewModel)
                    case .favoriteSettings:
                        FavoriteSettingsView(viewModel: viewModel)
                    case .about:
                        AboutView()
                    }
                }
                
                // Bottom status bar
                HStack {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("Changes saved automatically")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if selectedCategory == .languageTriggers {
                        Text("\(viewModel.filteredConfigs.count) languages")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if selectedCategory == .about {
                        Text("System Information")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .onAppear {
            viewModel.loadConfigs()
        }
    }
}

// Language Triggers Configuration View
struct LanguageTriggersView: View {
    @ObservedObject var viewModel: LanguageConfigViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search languages...", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                
                if !viewModel.searchText.isEmpty {
                    Button("Clear") {
                        viewModel.searchText = ""
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            // Language list
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(viewModel.filteredConfigs, id: \.code) { config in
                        LanguageConfigRow(
                            config: config,
                            onTriggersChanged: { newTriggers in
                                viewModel.updateTriggers(for: config.code, triggers: newTriggers)
                            }
                        )
                        .background(Color(NSColor.controlBackgroundColor))
                    }
                }
            }
            .background(Color(NSColor.textBackgroundColor))
        }
    }
}

// Favorite Settings Configuration View
struct FavoriteSettingsView: View {
    @ObservedObject var viewModel: LanguageConfigViewModel
    @State private var newLanguageSearch: String = ""
    @State private var showingLanguagePicker: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Preferred Language Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Preferred Language")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 8) {
                         
                        Picker("Select Language", selection: $viewModel.preferredLanguage) {
                            ForEach(viewModel.availableLanguages, id: \.code) { language in
                                Text(language.name)
                                    .tag(language.code)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 200)
                        .onChange(of: viewModel.preferredLanguage) { newValue in
                            viewModel.updatePreferredLanguage(language: newValue)
                        }
                        
                        Text("The received message will be translated to your preferred language if it is not the same as yours")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                }
                
                                // Translation Rules Section
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto Translation Rules")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text("only for Pro and Max users")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        // Rule Type Selection
                        HStack {
                            Picker("", selection: $viewModel.translationRuleType) {
                                Text("Includes").tag("includes")
                                Text("Excludes").tag("excludes")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                            .onChange(of: viewModel.translationRuleType) { newValue in
                                viewModel.updateTranslationRuleType(newValue)
                            }
                            
                            Spacer()
                        }
                        
                        // Rule Description
                        Text(viewModel.translationRuleType == "includes" ? 
                             "Only translate content in the selected languages below." :
                             "Translate content in all languages except the selected ones below and your preferred language.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        // Language Search and Add
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("Search and add languages...", text: $newLanguageSearch)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit {
                                        addLanguageFromSearch()
                                    }
                                    .onChange(of: newLanguageSearch) { _ in
                                        viewModel.updateLanguageSuggestions(searchText: newLanguageSearch)
                                    }
                                
                                Button("Add") {
                                    addLanguageFromSearch()
                                }
                                .buttonStyle(.bordered)
                                .disabled(newLanguageSearch.isEmpty)
                            }
                            
                            // Language Suggestions Dropdown
                            if !viewModel.languageSuggestions.isEmpty && !newLanguageSearch.isEmpty {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(viewModel.languageSuggestions, id: \.code) { language in
                                        Button(action: {
                                            selectLanguageSuggestion(language)
                                        }) {
                                            HStack {
                                                Text(language.name)
                                                    .font(.system(size: 12))
                                                Spacer()
                                                Text(language.code)
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.secondary)
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 6)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .buttonStyle(.plain)
                                        .background(Color(NSColor.controlBackgroundColor))
                                        
                                        if language.code != viewModel.languageSuggestions.last?.code {
                                            Divider()
                                                .padding(.leading, 8)
                                        }
                                    }
                                }
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                            }
                        }
                        
                        // Selected Languages List
                        let currentLanguages = viewModel.translationRuleType == "includes" ? viewModel.translationRuleLanguagesIncludes : viewModel.translationRuleLanguagesExcludes
                        let displayLanguages = viewModel.translationRuleType == "excludes" ? 
                            currentLanguages + [viewModel.preferredLanguage] : currentLanguages
                        
                        if !displayLanguages.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Selected Languages for \(viewModel.translationRuleType.capitalized):")
                                    .font(.system(size: 13, weight: .medium))
                                
                                LazyVGrid(columns: [
                                    GridItem(.adaptive(minimum: 150))
                                ], spacing: 8) {
                                    ForEach(displayLanguages, id: \.self) { languageCode in
                                        HStack {
                                            Text(getLanguageName(for: languageCode))
                                                .font(.system(size: 12))
                                                .foregroundColor(languageCode == viewModel.preferredLanguage && viewModel.translationRuleType == "excludes" ? .secondary : .primary)
                                            
                                            Spacer()
                                            
                                            if languageCode != viewModel.preferredLanguage || viewModel.translationRuleType == "includes" {
                                                Button(action: {
                                                    removeLanguage(languageCode)
                                                }) {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .foregroundColor(.red)
                                                        .font(.system(size: 12))
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(languageCode == viewModel.preferredLanguage && viewModel.translationRuleType == "excludes" ? 
                                                   Color.green.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                                        .cornerRadius(6)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                }
                
                // Return Key Translation Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Return Key Interception")
                        .font(.headline)
                        .fontWeight(.semibold)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Toggle("With Trigger", isOn: $viewModel.returnKeyWithTrigger)
                                .onChange(of: viewModel.returnKeyWithTrigger) { newValue in
                                    viewModel.updateReturnKeyWithTrigger(enabled: newValue)
                                }

                            Spacer()
                        }

                        Text("When enabled, pressing Return key will automatically translate content when a trigger (like @zh) is detected in the input.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            Toggle("Without Trigger", isOn: $viewModel.returnKeyWithoutTrigger)
                                .onChange(of: viewModel.returnKeyWithoutTrigger) { newValue in
                                    viewModel.updateReturnKeyWithoutTrigger(enabled: newValue)
                                }

                            Spacer()
                        }
                        Text("Only for Pro and Max users")
                            .font(.caption)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("When enabled and the translation sidebar is open, pressing Return key will automatically translate content to sender's language without needing to type a trigger.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                }

                // Screenshot Hotkey Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Screenshot Translation Hotkey")
                        .font(.headline)
                        .fontWeight(.semibold)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Customize the hotkey combination to trigger screenshot translation")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        // Hotkey input field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Press keys to set hotkey:")
                                .font(.system(size: 13, weight: .medium))

                            HStack {
                                HotkeyInputField(
                                    currentHotkey: viewModel.currentHotkeyDescription,
                                    onHotkeyChanged: { keyString, modifiers in
                                        viewModel.setHotkeyFromInput(
                                            key: keyString,
                                            shift: modifiers.contains(.shift),
                                            option: modifiers.contains(.option),
                                            cmd: modifiers.contains(.command),
                                            control: modifiers.contains(.control)
                                        )
                                    }
                                )
                                .frame(width: 200, height: 32)

                                Button("Reset to Default") {
                                    viewModel.setHotkeyPreset(shift: true, option: true, cmd: false, control: false, key: "S")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            Text("Requirements: At least one modifier key (⌘/⌃/⌥/⇧) + one letter/number key")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            if !viewModel.hotkeyValidationMessage.isEmpty {
                                Text(viewModel.hotkeyValidationMessage)
                                    .font(.caption)
                                    .foregroundColor(viewModel.isCurrentHotkeyValid ? .green : .red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
    
    private func getLanguageName(for code: String) -> String {
        return viewModel.availableLanguages.first { $0.code == code }?.name ?? code
    }
    
    private func addLanguageFromSearch() {
        guard !newLanguageSearch.isEmpty else { return }
        
        // Search for matching language
        let searchTerm = newLanguageSearch.lowercased()
        if let language = viewModel.availableLanguages.first(where: { language in
            language.name.lowercased().contains(searchTerm) ||
            language.code.lowercased().contains(searchTerm)
        }) {
            // Don't add if it's the preferred language (it's automatically included in excludes mode)
            if language.code != viewModel.preferredLanguage {
                if viewModel.translationRuleType == "includes" {
                    // Don't add if already in the includes list
                    if !viewModel.translationRuleLanguagesIncludes.contains(language.code) {
                        var updatedLanguages = viewModel.translationRuleLanguagesIncludes
                        updatedLanguages.append(language.code)
                        viewModel.updateTranslationRuleLanguagesIncludes(updatedLanguages)
                    }
                } else {
                    // Don't add if already in the excludes list
                    if !viewModel.translationRuleLanguagesExcludes.contains(language.code) {
                        var updatedLanguages = viewModel.translationRuleLanguagesExcludes
                        updatedLanguages.append(language.code)
                        viewModel.updateTranslationRuleLanguagesExcludes(updatedLanguages)
                    }
                }
            } else if viewModel.translationRuleType == "excludes" {
                // Show a message that preferred language is automatically included
                Logger.info("Preferred language is automatically included in excludes mode")
            }
        }
        
        newLanguageSearch = ""
        viewModel.languageSuggestions = []
    }
    
    private func selectLanguageSuggestion(_ language: SimpleLanguage) {
        // Don't add if it's the preferred language (it's automatically included in excludes mode)
        if language.code != viewModel.preferredLanguage {
            if viewModel.translationRuleType == "includes" {
                // Don't add if already in the includes list
                if !viewModel.translationRuleLanguagesIncludes.contains(language.code) {
                    var updatedLanguages = viewModel.translationRuleLanguagesIncludes
                    updatedLanguages.append(language.code)
                    viewModel.updateTranslationRuleLanguagesIncludes(updatedLanguages)
                }
            } else {
                // Don't add if already in the excludes list
                if !viewModel.translationRuleLanguagesExcludes.contains(language.code) {
                    var updatedLanguages = viewModel.translationRuleLanguagesExcludes
                    updatedLanguages.append(language.code)
                    viewModel.updateTranslationRuleLanguagesExcludes(updatedLanguages)
                }
            }
        } else if viewModel.translationRuleType == "excludes" {
            // Show a message that preferred language is automatically included
            Logger.info("Preferred language is automatically included in excludes mode")
        }
        
        newLanguageSearch = ""
        viewModel.languageSuggestions = []
    }
    
    private func removeLanguage(_ languageCode: String) {
        // Don't allow removing preferred language in excludes mode
        if languageCode == viewModel.preferredLanguage && viewModel.translationRuleType == "excludes" {
            Logger.info("Cannot remove preferred language from excludes mode - it's automatically included")
            return
        }
        
        if viewModel.translationRuleType == "includes" {
            var updatedLanguages = viewModel.translationRuleLanguagesIncludes
            updatedLanguages.removeAll { $0 == languageCode }
            viewModel.updateTranslationRuleLanguagesIncludes(updatedLanguages)
        } else {
            var updatedLanguages = viewModel.translationRuleLanguagesExcludes
            updatedLanguages.removeAll { $0 == languageCode }
            viewModel.updateTranslationRuleLanguagesExcludes(updatedLanguages)
        }
    }
}

// Single language configuration row
struct LanguageConfigRow: View {
    let config: LanguageConfig
    let onTriggersChanged: ([String]) -> Void
    
    @State private var triggers: [String] = []
    @State private var newTrigger: String = ""
    @State private var isExpanded: Bool = false
    @State private var isLoading: Bool = true
    
    init(config: LanguageConfig, onTriggersChanged: @escaping ([String]) -> Void) {
        self.config = config
        self.onTriggersChanged = onTriggersChanged
    }
    
    private var popularityColor: Color {
        switch config.popular {
        case 1: return .green
        case 2: return .orange
        default: return .gray
        }
    }
    
    private var popularityText: String {
        switch config.popular {
        case 1: return "Popular"
        case 2: return "Common"
        default: return "Other"
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main row
            HStack {
                // Language information
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(config.name)
                            .font(.system(size: 14, weight: .medium))
                        
                        Text("(\(config.code))")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        // Popularity label
                        Text(popularityText)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(popularityColor.opacity(0.2))
                            .foregroundColor(popularityColor)
                            .cornerRadius(4)
                    }
                    
                    // Trigger preview
                    HStack {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.5)
                            Text("Loading triggers...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(Array(triggers.prefix(3)), id: \.self) { trigger in
                                Text(trigger)
                                    .font(.caption)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .cornerRadius(3)
                            }
                            
                            if triggers.count > 3 {
                                Text("...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            if triggers.isEmpty {
                                Text("No triggers")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                }
                
                // Expand/collapse button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }
            
            // Expanded editing area
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Trigger Settings")
                            .font(.system(size: 13, weight: .medium))
                        
                        // Existing triggers
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 80), spacing: 8)
                        ], spacing: 8) {
                            ForEach(Array(triggers.enumerated()), id: \.offset) { index, trigger in
                                HStack(spacing: 4) {
                                    Text(trigger)
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .cornerRadius(4)
                                    
                                    Button(action: {
                                        removeTrigger(at: index)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                            .font(.caption2)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        
                        // Add new trigger
                        HStack {
                            TextField("Add new trigger...", text: $newTrigger)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                                .onSubmit {
                                    addNewTrigger()
                                }
                            
                            Button("Add") {
                                addNewTrigger()
                            }
                            .buttonStyle(.bordered)
                            .disabled(newTrigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        
                        Text("Tip: Triggers usually start with @ or #, like @\(config.code), #\(config.code)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .bottom
        )
        .onAppear {
            loadTriggersFromDatabase()
        }
    }
    
    private func addNewTrigger() {
        let trimmedTrigger = newTrigger.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTrigger.isEmpty && !triggers.contains(trimmedTrigger) else { return }
        
        triggers.append(trimmedTrigger)
        newTrigger = ""
        onTriggersChanged(triggers)
    }
    
    private func removeTrigger(at index: Int) {
        guard index < triggers.count else { return }
        triggers.remove(at: index)
        onTriggersChanged(triggers)
    }
    
    private func loadTriggersFromDatabase() {
        isLoading = true
        
        // Load triggers from database on a background queue
        DispatchQueue.global(qos: .userInitiated).async {
            let loadedTriggers = ConfigManager.shared.loadLanguageTriggers(languageCode: config.code)
            
            // Update UI on main queue
            DispatchQueue.main.async {
                self.triggers = loadedTriggers
                self.isLoading = false
            }
        }
    }
}

// ViewModel
class LanguageConfigViewModel: ObservableObject {
    @Published var configs: [LanguageConfig] = []
    @Published var searchText: String = ""
    @Published var preferredLanguage: String = EnvironmentManager.shared.getSystemLanguage()
    @Published var translationRuleType: String = "excludes"
    @Published var translationRuleLanguagesIncludes: [String] = []
    @Published var translationRuleLanguagesExcludes: [String] = []
    @Published var returnKeyWithTrigger: Bool = true
    @Published var returnKeyWithoutTrigger: Bool = true
    @Published var languageSuggestions: [SimpleLanguage] = []

    // Screenshot hotkey settings
    @Published var screenshotHotkeyKey: String = "S"
    @Published var screenshotHotkeyUseCmd: Bool = false
    @Published var screenshotHotkeyUseShift: Bool = true
    @Published var screenshotHotkeyUseOption: Bool = true
    @Published var screenshotHotkeyUseControl: Bool = false
    @Published var hotkeyValidationMessage: String = ""
    @Published var isCurrentHotkeyValid: Bool = true
    
    // Available languages for picker
    var availableLanguages: [SimpleLanguage] {
        return configs.map { SimpleLanguage(code: $0.code, name: $0.name) }
            .sorted { $0.name < $1.name }
    }
    
    var filteredConfigs: [LanguageConfig] {
        if searchText.isEmpty {
            return configs
        } else {
            return configs.filter { config in
                config.name.localizedCaseInsensitiveContains(searchText) ||
                config.code.localizedCaseInsensitiveContains(searchText) ||
                config.triggers.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
    }

    // Current hotkey description for display
    var currentHotkeyDescription: String {
        var components: [String] = []
        if screenshotHotkeyUseControl { components.append("⌃") }
        if screenshotHotkeyUseOption { components.append("⌥") }
        if screenshotHotkeyUseShift { components.append("⇧") }
        if screenshotHotkeyUseCmd { components.append("⌘") }
        components.append(screenshotHotkeyKey)
        return components.joined(separator: "")
    }
    
    func loadConfigs() {
        configs = ConfigManager.shared.loadLanguageConfigs()

        let appSettings = ConfigManager.shared.loadAppSettings()
        preferredLanguage = appSettings.preferredLanguage
        translationRuleType = appSettings.translationRuleType
        translationRuleLanguagesIncludes = appSettings.translationRuleLanguagesIncludes
        translationRuleLanguagesExcludes = appSettings.translationRuleLanguagesExcludes
        returnKeyWithTrigger = appSettings.returnKeyWithTrigger
        returnKeyWithoutTrigger = appSettings.returnKeyWithoutTrigger

        // Load screenshot hotkey settings with defaults (Shift+Option+S)
        screenshotHotkeyKey = UserDefaults.standard.string(forKey: "screenshot_hotkey_key") ?? "S"
        screenshotHotkeyUseCmd = UserDefaults.standard.bool(forKey: "screenshot_hotkey_cmd")
        screenshotHotkeyUseShift = UserDefaults.standard.object(forKey: "screenshot_hotkey_shift") == nil ? true : UserDefaults.standard.bool(forKey: "screenshot_hotkey_shift")
        screenshotHotkeyUseOption = UserDefaults.standard.object(forKey: "screenshot_hotkey_option") == nil ? true : UserDefaults.standard.bool(forKey: "screenshot_hotkey_option")
        screenshotHotkeyUseControl = UserDefaults.standard.bool(forKey: "screenshot_hotkey_control")

        Logger.info("Loaded \(configs.count) language configurations and app settings for configuration window")
        Logger.info("Current screenshot hotkey: \(currentHotkeyDescription)")
    }
    
    func updateTriggers(for languageCode: String, triggers: [String]) {
        // Update immediately in database
        if ConfigManager.shared.updateLanguageTriggers(languageCode: languageCode, triggers: triggers) {
            // Update local cache on success
            if let index = configs.firstIndex(where: { $0.code == languageCode }) {
                configs[index] = LanguageConfig(
                    code: configs[index].code,
                    name: configs[index].name,
                    nativeName: configs[index].nativeName,
                    popular: configs[index].popular,
                    triggers: triggers
                )
            }
            Logger.info("Language triggers updated immediately for \(languageCode)")
        } else {
            Logger.error("Failed to update language triggers for \(languageCode)")
        }
    }
    
    func updateReturnKeyWithTrigger(enabled: Bool) {
        // Update immediately in database
        if ConfigManager.shared.setReturnKeyWithTriggerEnabled(enabled) {
            returnKeyWithTrigger = enabled
            Logger.info("Return key with trigger updated immediately to: \(enabled)")
        } else {
            Logger.error("Failed to update return key with trigger setting")
        }
    }
    
    func updateReturnKeyWithoutTrigger(enabled: Bool) {
        // Update immediately in database
        if ConfigManager.shared.setReturnKeyWithoutTriggerEnabled(enabled) {
            returnKeyWithoutTrigger = enabled
            Logger.info("Return key without trigger updated immediately to: \(enabled)")
        } else {
            Logger.error("Failed to update return key without trigger setting")
        }
    }
    
    func updatePreferredLanguage(language: String) {
        // Update immediately in database
        if ConfigManager.shared.setPreferredLanguage(language) {
            preferredLanguage = language
            Logger.info("Preferred language updated immediately to: \(language)")
        } else {
            Logger.error("Failed to update preferred language setting")
        }
    }
    
    func updateTranslationRuleType(_ ruleType: String) {
        // Update immediately in database
        if ConfigManager.shared.setTranslationRuleType(ruleType) {
            translationRuleType = ruleType
            Logger.info("Translation rule type updated immediately to: \(ruleType)")
        } else {
            Logger.error("Failed to update translation rule type setting")
        }
    }
    
    func updateLanguageSuggestions(searchText: String) {
        guard !searchText.isEmpty else {
            languageSuggestions = []
            return
        }
        
        let filtered = availableLanguages.filter { language in
            language.name.localizedCaseInsensitiveContains(searchText) ||
            language.code.localizedCaseInsensitiveContains(searchText)
        }
        
        // Limit to 10 suggestions for better performance
        languageSuggestions = Array(filtered.prefix(10))
    }
    
    func updateTranslationRuleLanguagesIncludes(_ languages: [String]) {
        // Update immediately in database
        if ConfigManager.shared.setTranslationRuleLanguagesIncludes(languages) {
            translationRuleLanguagesIncludes = languages
            Logger.info("Translation rule languages (includes) updated immediately to: \(languages)")
        } else {
            Logger.error("Failed to update translation rule languages (includes) setting")
        }
    }
    
    func updateTranslationRuleLanguagesExcludes(_ languages: [String]) {
        // Update immediately in database
        if ConfigManager.shared.setTranslationRuleLanguagesExcludes(languages) {
            translationRuleLanguagesExcludes = languages
            Logger.info("Translation rule languages (excludes) updated immediately to: \(languages)")
        } else {
            Logger.error("Failed to update translation rule languages (excludes) setting")
        }
    }

    // Screenshot hotkey methods
    func setHotkeyPreset(shift: Bool, option: Bool, cmd: Bool, control: Bool, key: String) {
        screenshotHotkeyUseShift = shift
        screenshotHotkeyUseOption = option
        screenshotHotkeyUseCmd = cmd
        screenshotHotkeyUseControl = control
        screenshotHotkeyKey = key

        hotkeyValidationMessage = "✅ Hotkey combination is valid"
        isCurrentHotkeyValid = true

        // Force UI update by triggering the computed property
        objectWillChange.send()

        // Save to UserDefaults immediately
        saveHotkeySettings()

        Logger.info("Screenshot hotkey preset applied: \(currentHotkeyDescription)")
    }

    func setHotkeyFromInput(key: String, shift: Bool, option: Bool, cmd: Bool, control: Bool) {
        // Validate the hotkey combination
        let hasModifier = shift || option || cmd || control
        let isValidKey = isValidHotkeyKey(key)

        if !hasModifier {
            hotkeyValidationMessage = "⚠️ At least one modifier key is required"
            isCurrentHotkeyValid = false
            return
        }

        if !isValidKey {
            hotkeyValidationMessage = "⚠️ Please use a letter (A-Z) or number (0-9) key"
            isCurrentHotkeyValid = false
            return
        }

        // Valid combination - update all properties
        screenshotHotkeyUseShift = shift
        screenshotHotkeyUseOption = option
        screenshotHotkeyUseCmd = cmd
        screenshotHotkeyUseControl = control
        screenshotHotkeyKey = key.uppercased()

        hotkeyValidationMessage = "✅ Hotkey combination is valid"
        isCurrentHotkeyValid = true

        // Force UI update by triggering the computed property
        objectWillChange.send()

        // Save to UserDefaults immediately
        saveHotkeySettings()

        Logger.info("Screenshot hotkey set from input: \(currentHotkeyDescription)")
    }

    private func isValidHotkeyKey(_ key: String) -> Bool {
        return KeyCodeMapper.isValidHotkeyKey(key)
    }

    private func saveHotkeySettings() {
        UserDefaults.standard.set(screenshotHotkeyKey, forKey: "screenshot_hotkey_key")
        UserDefaults.standard.set(screenshotHotkeyUseCmd, forKey: "screenshot_hotkey_cmd")
        UserDefaults.standard.set(screenshotHotkeyUseShift, forKey: "screenshot_hotkey_shift")
        UserDefaults.standard.set(screenshotHotkeyUseOption, forKey: "screenshot_hotkey_option")
        UserDefaults.standard.set(screenshotHotkeyUseControl, forKey: "screenshot_hotkey_control")

        // Update the screenshot manager with new hotkey settings
        ScreenshotTranslationManager.shared.reloadHotkeySettings()

        Logger.info("Screenshot hotkey settings saved and applied: \(currentHotkeyDescription)")
    }

    func resetToDefaults() {
        let alert = NSAlert()
        alert.messageText = "Reset to Default Configuration"
        alert.informativeText = "This will delete all custom language trigger configurations and restore default settings. This action cannot be undone."
        alert.alertStyle = .warning
        alert.icon = NSImage(named: NSImage.cautionName) 
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            configs = ConfigManager.shared.resetToDefaults()
            Logger.info("Language configurations reset to defaults")
        }
    }
    
}

// About View
struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // App Information
                VStack(alignment: .leading, spacing: 16) {
                    Text("Application Information")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        InfoRow(label: "App Name", value: getAppName())
                        InfoRow(label: "Version", value: getAppVersion())
                        InfoRow(label: "Build Number", value: getBuildNumber()) 
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                }
                
                // System Information
                VStack(alignment: .leading, spacing: 16) {
                    Text("System Information")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        InfoRow(label: "macOS Version", value: getSystemVersion())
                        InfoRow(label: "System Architecture", value: getSystemArchitecture())
                        InfoRow(label: "Chip Type", value: getChipType())
                        InfoRow(label: "Process ID", value: String(ProcessInfo.processInfo.processIdentifier))
                        InfoRow(label: "Uptime", value: getSystemUptime())
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
    
    // Helper functions to get system information
    private func getAppName() -> String {
        return Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Unknown"
    }
    
    private func getAppVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    private func getBuildNumber() -> String {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
    
    private func getBundleIdentifier() -> String {
        return Bundle.main.bundleIdentifier ?? "Unknown"
    }
    
    private func getSystemVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
    
    private func getSystemArchitecture() -> String {
        #if arch(x86_64)
        return "x86_64 (Intel)"
        #elseif arch(arm64)
        return "arm64 (Apple Silicon)"
        #else
        return "Unknown"
        #endif
    }
    
    private func getChipType() -> String {
        #if arch(arm64)
        // 使用 IOKit 获取更准确的芯片信息
        if let chipType = getAppleSiliconChipType() {
            return chipType
        }
        #endif
        
        // 回退到品牌字符串方法
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        
        if size > 0 {
            var cpuBrand = [CChar](repeating: 0, count: size)
            sysctlbyname("machdep.cpu.brand_string", &cpuBrand, &size, nil, 0)
            let brandString = String(cString: cpuBrand)
            
            #if arch(arm64)
            if brandString.contains("Apple") {
                return brandString
            }
            #else
            if brandString.contains("Intel") {
                if brandString.contains("Core") {
                    if brandString.contains("i3") {
                        return "Intel Core i3"
                    } else if brandString.contains("i5") {
                        return "Intel Core i5"
                    } else if brandString.contains("i7") {
                        return "Intel Core i7"
                    } else if brandString.contains("i9") {
                        return "Intel Core i9"
                    }
                    return "Intel Core"
                } else if brandString.contains("Xeon") {
                    return "Intel Xeon"
                }
                return "Intel Processor"
            }
            #endif
            
            return brandString
        }
        
        return getSystemArchitecture()
    }
    
    private func getAppleSiliconChipType() -> String? {
        // 方法1: 使用 sysctl 获取芯片标识符
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        
        if size > 0 {
            var cpuBrand = [CChar](repeating: 0, count: size)
            sysctlbyname("machdep.cpu.brand_string", &cpuBrand, &size, nil, 0)
            let brandString = String(cString: cpuBrand)
            
            // 直接返回品牌字符串，它通常包含完整的芯片信息
            if brandString.contains("Apple") {
                return brandString
            }
        }
        
        // 方法2: 使用平台标识符获取芯片信息
        if let platformInfo = getPlatformInfo() {
            return platformInfo
        }
        
        return nil
    }
    
    private func getPlatformInfo() -> String? {
        // 尝试获取平台标识符
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        
        if size > 0 {
            var machine = [CChar](repeating: 0, count: size)
            sysctlbyname("hw.machine", &machine, &size, nil, 0)
            let machineString = String(cString: machine)
            
            // 根据机器标识符判断芯片类型
            switch machineString {
            case let x where x.hasPrefix("Mac14,2"):
                return "Apple M2 Pro"
            case let x where x.hasPrefix("Mac14,3"):
                return "Apple M2 Max"
            case let x where x.hasPrefix("Mac14,5"):
                return "Apple M2"
            case let x where x.hasPrefix("Mac14,6"):
                return "Apple M2"
            case let x where x.hasPrefix("Mac14,7"):
                return "Apple M2 Pro"
            case let x where x.hasPrefix("Mac14,8"):
                return "Apple M2 Max"
            case let x where x.hasPrefix("Mac14,9"):
                return "Apple M2 Ultra"
            case let x where x.hasPrefix("Mac14,10"):
                return "Apple M2 Ultra"
            case let x where x.hasPrefix("Mac15,2"):
                return "Apple M3 Pro"
            case let x where x.hasPrefix("Mac15,3"):
                return "Apple M3 Max"
            case let x where x.hasPrefix("Mac15,4"):
                return "Apple M3"
            case let x where x.hasPrefix("Mac15,5"):
                return "Apple M3"
            case let x where x.hasPrefix("Mac15,6"):
                return "Apple M3 Pro"
            case let x where x.hasPrefix("Mac15,7"):
                return "Apple M3 Max"
            case let x where x.hasPrefix("Mac15,8"):
                return "Apple M3 Ultra"
            case let x where x.hasPrefix("Mac15,9"):
                return "Apple M3 Ultra"
            case let x where x.hasPrefix("Mac13,1"):
                return "Apple M1"
            case let x where x.hasPrefix("Mac13,2"):
                return "Apple M1 Pro"
            case let x where x.hasPrefix("Mac13,3"):
                return "Apple M1 Max"
            case let x where x.hasPrefix("Mac13,4"):
                return "Apple M1 Ultra"
            default:
                return nil
            }
        }
        
        return nil
    }
    
    private func getSystemUptime() -> String {
        let uptime = ProcessInfo.processInfo.systemUptime
        let hours = Int(uptime) / 3600
        let minutes = Int(uptime) % 3600 / 60
        return "\(hours)h \(minutes)m"
    }
    
    private func getLaunchTime() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: Date())
    }
    
    private func getMemoryUsage() -> String {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let usedMemoryMB = Double(info.resident_size) / 1024 / 1024
            return String(format: "%.1f MB", usedMemoryMB)
        } else {
            return "Unknown"
        }
    }
}

// Info Row Component
struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 120, alignment: .leading)

            Text(value)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .textSelection(.enabled)

            Spacer()
        }
    }
}

// MARK: - Hotkey Input Field
struct HotkeyInputField: NSViewRepresentable {
    let currentHotkey: String
    let onHotkeyChanged: (String, NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> HotkeyInputNSView {
        let view = HotkeyInputNSView()
        view.hotkeyDisplay = currentHotkey
        view.onHotkeyChanged = onHotkeyChanged
        return view
    }

    func updateNSView(_ nsView: HotkeyInputNSView, context: Context) {
        // Force update the display when the hotkey changes
        nsView.hotkeyDisplay = currentHotkey
        nsView.needsDisplay = true

        // If the view is currently capturing but we have a new hotkey, exit capture mode
        if nsView.isCapturing && !currentHotkey.isEmpty {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nil)
            }
        }
    }
}

class HotkeyInputNSView: NSView {
    var hotkeyDisplay: String = "" {
        didSet {
            needsDisplay = true
        }
    }
    var onHotkeyChanged: ((String, NSEvent.ModifierFlags) -> Void)?
    private(set) var isCapturing = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        self.layer?.borderColor = NSColor.controlColor.cgColor
        self.layer?.borderWidth = 1.0
        self.layer?.cornerRadius = 4.0
    }

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func becomeFirstResponder() -> Bool {
        isCapturing = true
        self.layer?.borderColor = NSColor.controlAccentColor.cgColor
        self.layer?.borderWidth = 2.0
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        isCapturing = false
        self.layer?.borderColor = NSColor.controlColor.cgColor
        self.layer?.borderWidth = 1.0
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        // Capture the key combination
        let keyCode = event.keyCode
        let modifierFlags = event.modifierFlags.intersection([.command, .shift, .control, .option])

        // Convert key code to string
        if let keyString = KeyCodeMapper.getKeyString(for: keyCode) {
            onHotkeyChanged?(keyString, modifierFlags)

            // Resign first responder after capturing the key to exit capture mode
            DispatchQueue.main.async { [weak self] in
                self?.window?.makeFirstResponder(nil)
            }
        }
    }

    override func flagsChanged(with event: NSEvent) {
        // Don't do anything on modifier-only changes
        // We only care about actual key presses with modifiers
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let displayText = isCapturing ? "Press keys..." : (hotkeyDisplay.isEmpty ? "Click to set" : hotkeyDisplay)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: isCapturing ? NSColor.controlAccentColor : NSColor.labelColor
        ]

        let attributedString = NSAttributedString(string: displayText, attributes: attributes)
        let textSize = attributedString.size()

        let textRect = NSRect(
            x: (bounds.width - textSize.width) / 2,
            y: (bounds.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )

        attributedString.draw(in: textRect)
    }

}