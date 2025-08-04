import Foundation

// MARK: - Language Configuration Models
struct LanguageConfig: Codable, Equatable {
    let code: String
    let name: String
    let popular: Int
    var triggers: [String]
}

// MARK: - App Settings Models
struct AppSettings: Codable {
    var isReturnKeyInterceptionEnabled: Bool
    var preferredLanguage: String
    
    static let `default` = AppSettings(
        isReturnKeyInterceptionEnabled: true,
        preferredLanguage: Locale.current.language.languageCode?.identifier ?? "en"
    )
}

// MARK: - Configuration Manager
class ConfigManager {
    static let shared = ConfigManager()
    
    private let languageConfigFileName = "language_triggers.json"
    private let appSettingsFileName = "app_settings.json"
    
    private lazy var applicationSupportDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("Glotera")
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        
        return appFolder
    }()
    
    private lazy var languageConfigURL: URL = {
        return applicationSupportDirectory.appendingPathComponent(languageConfigFileName)
    }()
    
    private lazy var appSettingsURL: URL = {
        return applicationSupportDirectory.appendingPathComponent(appSettingsFileName)
    }()
    
    // Cache for language configurations
    private var cachedConfigs: [LanguageConfig] = []
    private var isConfigsLoaded = false
    private let configsLock = NSLock()
    
    // Cache for app settings
    private var cachedSettings: AppSettings?
    private let settingsLock = NSLock()
    
    private init() {
        // Load configurations on initialization
        loadLanguageConfigsInternal()
        loadAppSettingsInternal()
    }
    
    // MARK: - Language Configuration Methods
    
    private func loadLanguageConfigsInternal() {
        configsLock.lock()
        defer { configsLock.unlock() }
        
        // Try to load from user customizations first
        if FileManager.default.fileExists(atPath: languageConfigURL.path) {
            do {
                let data = try Data(contentsOf: languageConfigURL)
                cachedConfigs = try JSONDecoder().decode([LanguageConfig].self, from: data)
                isConfigsLoaded = true
                Logger.info("Loaded \(cachedConfigs.count) language configurations from user file")
                return
            } catch {
                Logger.error("Failed to load user language configurations: \(error)")
            }
        }
        
                 // Fall back to default configurations
         guard let bundleURL = Bundle.main.url(forResource: "language-iso-639", withExtension: "json") else {
             Logger.error("Default language configuration file not found in bundle")
             cachedConfigs = []
             isConfigsLoaded = true
             return
         }
         
         do {
             let data = try Data(contentsOf: bundleURL)
             // Parse the dictionary format from language-iso-639.json
             let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
             
             var configs: [LanguageConfig] = []
             
             for (code, value) in jsonObject ?? [:] {
                 if let langData = value as? [String: Any],
                    let name = langData["name"] as? String,
                    let popular = langData["popular"] as? Int,
                    let triggers = langData["triggers"] as? [String] {
                     
                     let config = LanguageConfig(
                         code: code,
                         name: name,
                         popular: popular,
                         triggers: triggers
                     )
                     configs.append(config)
                 }
             }
             
             // Sort by popular level, then by name
             configs.sort { first, second in
                 if first.popular != second.popular {
                     return first.popular < second.popular
                 }
                 return first.name < second.name
             }
             
             cachedConfigs = configs
             isConfigsLoaded = true
             Logger.info("Loaded \(cachedConfigs.count) default language configurations")
         } catch {
             Logger.error("Failed to load default language configurations: \(error)")
             cachedConfigs = []
             isConfigsLoaded = true
         }
    }
    
    func loadLanguageConfigs() -> [LanguageConfig] {
        configsLock.lock()
        defer { configsLock.unlock() }
        return cachedConfigs
    }
    
    func saveLanguageConfigs(_ configs: [LanguageConfig]) -> Bool {
        configsLock.lock()
        defer { configsLock.unlock() }
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(configs)
            try data.write(to: languageConfigURL)
            
            // Update cache
            cachedConfigs = configs
            
            Logger.info("Language configurations saved successfully to \(languageConfigURL.path)")
            return true
        } catch {
            Logger.error("Failed to save language configurations: \(error)")
            return false
        }
    }
    
    func resetToDefaults() -> [LanguageConfig] {
        configsLock.lock()
        defer { configsLock.unlock() }
        
        // Delete user customizations file
        try? FileManager.default.removeItem(at: languageConfigURL)
        
                 // Reload from default
         guard let bundleURL = Bundle.main.url(forResource: "language-iso-639", withExtension: "json") else {
             Logger.error("Default language configuration file not found in bundle")
             cachedConfigs = []
             return cachedConfigs
         }
         
         do {
             let data = try Data(contentsOf: bundleURL)
             // Parse the dictionary format from language-iso-639.json
             let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
             
             var configs: [LanguageConfig] = []
             
             for (code, value) in jsonObject ?? [:] {
                 if let langData = value as? [String: Any],
                    let name = langData["name"] as? String,
                    let popular = langData["popular"] as? Int,
                    let triggers = langData["triggers"] as? [String] {
                     
                     let config = LanguageConfig(
                         code: code,
                         name: name,
                         popular: popular,
                         triggers: triggers
                     )
                     configs.append(config)
                 }
             }
             
             // Sort by popular level, then by name
             configs.sort { first, second in
                 if first.popular != second.popular {
                     return first.popular < second.popular
                 }
                 return first.name < second.name
             }
             
             cachedConfigs = configs
             Logger.info("Reset to default language configurations")
             return cachedConfigs
         } catch {
             Logger.error("Failed to load default language configurations during reset: \(error)")
             cachedConfigs = []
             return cachedConfigs
         }
    }
    
    func findLanguageConfig(withTrigger trigger: String) -> LanguageConfig? {
        configsLock.lock()
        defer { configsLock.unlock() }
        return cachedConfigs.first { $0.triggers.contains(trigger) }
    }
    
    func getAllTriggers() -> [String] {
        configsLock.lock()
        defer { configsLock.unlock() }
        return cachedConfigs.flatMap { $0.triggers }
    }
    
    // MARK: - App Settings Methods
    
    private func loadAppSettingsInternal() {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        
        if FileManager.default.fileExists(atPath: appSettingsURL.path) {
            do {
                let data = try Data(contentsOf: appSettingsURL)
                cachedSettings = try JSONDecoder().decode(AppSettings.self, from: data)
                Logger.info("Loaded app settings from file")
            } catch {
                Logger.error("Failed to load app settings: \(error)")
                cachedSettings = AppSettings.default
            }
        } else {
            cachedSettings = AppSettings.default
            Logger.info("Using default app settings")
        }
    }
    
    func loadAppSettings() -> AppSettings {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        return cachedSettings ?? AppSettings.default
    }
    
    func saveAppSettings(_ settings: AppSettings) -> Bool {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(settings)
            try data.write(to: appSettingsURL)
            
            // Update cache
            cachedSettings = settings
            
            Logger.info("App settings saved successfully to \(appSettingsURL.path)")
            return true
        } catch {
            Logger.error("Failed to save app settings: \(error)")
            return false
        }
    }
    
    func isReturnKeyInterceptionEnabled() -> Bool {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        return cachedSettings?.isReturnKeyInterceptionEnabled ?? AppSettings.default.isReturnKeyInterceptionEnabled
    }
    
    func setReturnKeyInterceptionEnabled(_ enabled: Bool) -> Bool {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        
        var settings = cachedSettings ?? AppSettings.default
        settings.isReturnKeyInterceptionEnabled = enabled
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(settings)
            try data.write(to: appSettingsURL)
            
            // Update cache
            cachedSettings = settings
            
            Logger.info("Return key interception setting updated to: \(enabled)")
            return true
        } catch {
            Logger.error("Failed to save return key interception setting: \(error)")
            return false
        }
    }
} 
