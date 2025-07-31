import SwiftUI
import Cocoa

// Configuration categories
enum ConfigCategory: String, CaseIterable {
    case languageTriggers = "Language Triggers"
    case keyboardSettings = "Keyboard Settings"
    case about = "About Glotera"
    
    var systemImage: String {
        switch self {
        case .languageTriggers: return "globe"
        case .keyboardSettings: return "keyboard"
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
                    
                    // Only show Save button for configurable categories
                    if selectedCategory != .about {
                        Button("Save") {
                            viewModel.saveConfigs()
                        }
                        .buttonStyle(.borderedProminent)
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
                    case .keyboardSettings:
                        KeyboardSettingsView(viewModel: viewModel)
                    case .about:
                        AboutView()
                    }
                }
                
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

// Keyboard Settings Configuration View
struct KeyboardSettingsView: View {
    @ObservedObject var viewModel: LanguageConfigViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Return Key Behavior")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Toggle("Enable Return Key Interception for Auto Translation", 
                                   isOn: $viewModel.isReturnKeyInterceptionEnabled)
                                .onChange(of: viewModel.isReturnKeyInterceptionEnabled) { newValue in
                                    viewModel.updateReturnKeyInterception(enabled: newValue)
                                }
                            
                            Spacer()
                        }
                        
                        Text("When enabled, pressing Return key in input fields will trigger automatic translation and send the translated text.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                }
                
                // Add more keyboard settings here in the future
                VStack(alignment: .leading, spacing: 12) {
                    Text("Additional Settings")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("More keyboard and input settings will be available in future updates.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                        .cornerRadius(8)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

// Single language configuration row
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
    @Published var isReturnKeyInterceptionEnabled: Bool = true
    
    private var originalConfigs: [LanguageConfig] = []
    private var originalReturnKeyInterception: Bool = true
    
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
                    configs = ConfigManager.shared.loadLanguageConfigs()
        originalConfigs = configs
        
        let appSettings = ConfigManager.shared.loadAppSettings()
        isReturnKeyInterceptionEnabled = appSettings.isReturnKeyInterceptionEnabled
        originalReturnKeyInterception = isReturnKeyInterceptionEnabled
        
        hasUnsavedChanges = false
        Logger.info("Loaded \(configs.count) language configurations and app settings for configuration window")
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
    
    func updateReturnKeyInterception(enabled: Bool) {
        isReturnKeyInterceptionEnabled = enabled
        checkForChanges()
    }
    
    func saveConfigs() {
        var success = true
        
        // Save language configurations
        if !areConfigsEqual(configs, originalConfigs) {
            success = ConfigManager.shared.saveLanguageConfigs(configs) && success
            if success {
                originalConfigs = configs
            }
        }
        
        // Save app settings
        if isReturnKeyInterceptionEnabled != originalReturnKeyInterception {
            let settings = AppSettings(isReturnKeyInterceptionEnabled: isReturnKeyInterceptionEnabled)
            success = ConfigManager.shared.saveAppSettings(settings) && success
            if success {
                originalReturnKeyInterception = isReturnKeyInterceptionEnabled
            }
        }
        
        if success {
            hasUnsavedChanges = false
            Logger.info("All configurations saved successfully")
            
            // Show save success notification
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Save Successful"
                alert.informativeText = "Configuration has been saved successfully"
                alert.alertStyle = .informational
                alert.icon = NSImage(named: NSImage.infoName) 
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        } else {
            Logger.info("Failed to save some configurations")
            
            // Show save failure notification
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Save Failed"
                alert.informativeText = "Unable to save configuration. Please check file permissions."
                alert.alertStyle = .warning
                alert.icon = NSImage(named: NSImage.cautionName) 
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
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
            originalConfigs = configs
            checkForChanges()
            Logger.info("Language configurations reset to defaults")
        }
    }
    
    private func checkForChanges() {
        hasUnsavedChanges = !areConfigsEqual(configs, originalConfigs) ||
                           isReturnKeyInterceptionEnabled != originalReturnKeyInterception
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