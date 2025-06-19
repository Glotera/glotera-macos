import SwiftUI
import Cocoa

// 语言配置窗口
class LanguageConfigWindow: NSWindow {
    
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        self.title = "Language Trigger Configuration"
        self.center()
        self.isReleasedWhenClosed = false
        
        // 创建SwiftUI视图
        let contentView = LanguageConfigView { [weak self] in
            self?.close()
        }
        
        self.contentView = NSHostingView(rootView: contentView)
    }
    
    func show() {
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// SwiftUI主视图
struct LanguageConfigView: View {
    @StateObject private var viewModel = LanguageConfigViewModel()
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar
            HStack {
                Text("Language Trigger Configuration")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Reset to Default") {
                    viewModel.resetToDefaults()
                }
                .buttonStyle(.bordered)
                
                Button("Save") {
                    viewModel.saveConfigs()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Close") {
                    onClose()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
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
            
            // Bottom status bar
            HStack {
                if viewModel.hasUnsavedChanges {
                    HStack {
                        Image(systemName: "circle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text("Unsaved changes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("All changes saved")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Text("\(viewModel.filteredConfigs.count) languages")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .onAppear {
            viewModel.loadConfigs()
        }
    }
}

// 单个语言配置行
struct LanguageConfigRow: View {
    let config: LanguageConfig
    let onTriggersChanged: ([String]) -> Void
    
    @State private var triggers: [String]
    @State private var newTrigger: String = ""
    @State private var isExpanded: Bool = false
    
    init(config: LanguageConfig, onTriggersChanged: @escaping ([String]) -> Void) {
        self.config = config
        self.onTriggersChanged = onTriggersChanged
        self._triggers = State(initialValue: config.triggers)
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
}

// ViewModel
class LanguageConfigViewModel: ObservableObject {
    @Published var configs: [LanguageConfig] = []
    @Published var searchText: String = ""
    @Published var hasUnsavedChanges: Bool = false
    
    private var originalConfigs: [LanguageConfig] = []
    
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
    
    func loadConfigs() {
        configs = LanguageConfigManager.shared.loadLanguageConfigs()
        originalConfigs = configs
        hasUnsavedChanges = false
        print("[LOG] Loaded \(configs.count) language configurations for menu bar")
    }
    
    func updateTriggers(for languageCode: String, triggers: [String]) {
        if let index = configs.firstIndex(where: { $0.code == languageCode }) {
            configs[index] = LanguageConfig(
                code: configs[index].code,
                name: configs[index].name,
                popular: configs[index].popular,
                triggers: triggers
            )
            checkForChanges()
        }
    }
    
    func saveConfigs() {
        let success = LanguageConfigManager.shared.saveLanguageConfigs(configs)
        if success {
            originalConfigs = configs
            hasUnsavedChanges = false
            print("[LOG] Language configurations saved successfully")
            
            // Show save success notification
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Save Successful"
                alert.informativeText = "Language trigger configuration has been saved"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        } else {
            print("[LOG] Failed to save language configurations")
            
            // Show save failure notification
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Save Failed"
                alert.informativeText = "Unable to save language trigger configuration. Please check file permissions."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
    
    func resetToDefaults() {
        let alert = NSAlert()
        alert.messageText = "Reset to Default Configuration"
        alert.informativeText = "This will delete all custom configurations and restore default settings. This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            configs = LanguageConfigManager.shared.resetToDefaults()
            originalConfigs = configs
            hasUnsavedChanges = false
            print("[LOG] Language configurations reset to defaults")
        }
    }
    
    private func checkForChanges() {
        hasUnsavedChanges = !areConfigsEqual(configs, originalConfigs)
    }
    
    private func areConfigsEqual(_ configs1: [LanguageConfig], _ configs2: [LanguageConfig]) -> Bool {
        guard configs1.count == configs2.count else { return false }
        
        for config1 in configs1 {
            guard let config2 = configs2.first(where: { $0.code == config1.code }) else { return false }
            if config1.triggers != config2.triggers { return false }
        }
        
        return true
    }
} 