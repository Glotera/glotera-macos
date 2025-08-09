import Foundation
import SQLite3

// MARK: - Language Configuration Models
struct LanguageConfig: Codable, Equatable {
    let code: String
    let name: String
    let popular: Int
    var triggers: [String]
}

// MARK: - App Settings Models
struct AppSettings: Codable {
    var preferredLanguage: String
    var translationRuleType: String // "includes" or "excludes"
    var translationRuleLanguagesIncludes: [String] // List of language codes for includes mode
    var translationRuleLanguagesExcludes: [String] // List of language codes for excludes mode
    var returnKeyWithTrigger: Bool // Auto translate when pressing return with trigger
    var returnKeyWithoutTrigger: Bool // Auto translate when pressing return without trigger (when sidebar is open)
    
    static let `default` = AppSettings(
        preferredLanguage: EnvironmentManager.shared.getSystemLanguage(),
        translationRuleType: "excludes",
        translationRuleLanguagesIncludes: [],
        translationRuleLanguagesExcludes: [EnvironmentManager.shared.getSystemLanguage()],
        returnKeyWithTrigger: true,
        returnKeyWithoutTrigger: true
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
        
        // Try to load from database first
        if loadLanguageConfigsFromDatabase() {
            Logger.info("Loaded \(cachedConfigs.count) language configurations from database")
            isConfigsLoaded = true
            return
        }
        
        // Try to load from user customizations
        if FileManager.default.fileExists(atPath: languageConfigURL.path) {
            do {
                let data = try Data(contentsOf: languageConfigURL)
                cachedConfigs = try JSONDecoder().decode([LanguageConfig].self, from: data)
                isConfigsLoaded = true
                Logger.info("Loaded \(cachedConfigs.count) language configurations from user file")
                // Save to database for future use
                _ = saveLanguageConfigsToDatabase(cachedConfigs)
                return
            } catch {
                Logger.error("Failed to load user language configurations: \(error)")
            }
        }
        
        // Fall back to JSON bundle file
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
            Logger.info("Loaded \(cachedConfigs.count) default language configurations from JSON")
            
            // Save to database for future use
            _ = saveLanguageConfigsToDatabase(cachedConfigs)
            
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
        
        // Save to database first
        if saveLanguageConfigsToDatabase(configs) {
            // Update cache
            cachedConfigs = configs
            Logger.info("Language configurations saved successfully to database")
            
            // Also save to JSON file as backup
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(configs)
            try data.write(to: languageConfigURL)
                Logger.info("Language configurations also saved to JSON file")
            } catch {
                Logger.warn("Failed to save language configurations to JSON file: \(error)")
            }
            
            return true
        } else {
            Logger.error("Failed to save language configurations to database")
            return false
        }
    }
    
    func resetToDefaults() -> [LanguageConfig] {
        configsLock.lock()
        defer { configsLock.unlock() }
        
        // Clear database configurations
        _ = clearLanguageConfigsFromDatabase()
        
        // Delete user customizations file
        try? FileManager.default.removeItem(at: languageConfigURL)
        
        // Reload from JSON bundle file
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
            
            // Save to database for future use
            _ = saveLanguageConfigsToDatabase(cachedConfigs)
            
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
    
    /// Update a specific language configuration immediately
    func updateLanguageConfig(_ config: LanguageConfig) -> Bool {
        configsLock.lock()
        defer { configsLock.unlock() }
        
        // Update in database first
        if updateLanguageConfigInDatabase(config) {
            // Update cache
            if let index = cachedConfigs.firstIndex(where: { $0.code == config.code }) {
                cachedConfigs[index] = config
            }
            Logger.info("Language configuration updated for \(config.code)")
            return true
        } else {
            Logger.error("Failed to update language configuration for \(config.code)")
            return false
        }
    }
    
    /// Update triggers for a specific language immediately
    func updateLanguageTriggers(languageCode: String, triggers: [String]) -> Bool {
        configsLock.lock()
        defer { configsLock.unlock() }
        
        // Update in database first
        if updateLanguageTriggersInDatabase(languageCode: languageCode, triggers: triggers) {
            // Update cache
            if let index = cachedConfigs.firstIndex(where: { $0.code == languageCode }) {
                var updatedConfig = cachedConfigs[index]
                updatedConfig.triggers = triggers
                cachedConfigs[index] = updatedConfig
            }
            Logger.info("Language triggers updated for \(languageCode)")
            return true
        } else {
            Logger.error("Failed to update language triggers for \(languageCode)")
            return false
        }
    }
    
    /// Load triggers for a specific language from database
    func loadLanguageTriggers(languageCode: String) -> [String] {
        configsLock.lock()
        defer { configsLock.unlock() }
        
        guard let db = DatabaseManager.shared.getDatabase() else {
            Logger.error("Database not available")
            return []
        }
        
        let querySQL = """
            SELECT triggers
            FROM language_configs 
            WHERE lang_iso639 = ?;
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK else {
            Logger.error("Failed to prepare language triggers query")
            return []
        }
        
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, (languageCode as NSString).utf8String, -1, nil)
        
        if sqlite3_step(statement) == SQLITE_ROW {
            guard let triggersPtr = sqlite3_column_text(statement, 0) else {
                return []
            }
            
            let triggersStr = String(cString: triggersPtr)
            
            // Parse triggers as comma-separated string
            let triggers = triggersStr.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            Logger.debug("Loaded \(triggers.count) triggers for \(languageCode): \(triggers)")
            return triggers
        }
        
        Logger.debug("No triggers found for language code: \(languageCode)")
        return []
    }
    
    // MARK: - App Settings Methods
    
    private func loadAppSettingsInternal() {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        
        // Try to load from database first
        if let dbSettings = loadAppSettingsFromDatabase() {
            cachedSettings = dbSettings
            Logger.info("Loaded app settings from database")
            return
        }
        
        // Try to load from JSON file
        if FileManager.default.fileExists(atPath: appSettingsURL.path) {
            do {
                let data = try Data(contentsOf: appSettingsURL)
                cachedSettings = try JSONDecoder().decode(AppSettings.self, from: data)
                Logger.info("Loaded app settings from file")
                // Save to database for future use
                _ = saveAppSettingsToDatabase(cachedSettings!)
                return
            } catch {
                Logger.error("Failed to load app settings: \(error)")
            }
        }
        
        // Use default settings
        cachedSettings = AppSettings.default
        Logger.info("Using default app settings")
        // Save defaults to database
        _ = saveAppSettingsToDatabase(cachedSettings!)
    }
    
    func loadAppSettings() -> AppSettings {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        return cachedSettings ?? AppSettings.default
    }
    
    func saveAppSettings(_ settings: AppSettings) -> Bool {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        
        // Save to database first
        if saveAppSettingsToDatabase(settings) {
            // Update cache
            cachedSettings = settings
            Logger.info("App settings saved successfully to database")
            
            // Also save to JSON file as backup
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(settings)
            try data.write(to: appSettingsURL)
                Logger.info("App settings also saved to JSON file")
            } catch {
                Logger.warn("Failed to save app settings to JSON file: \(error)")
            }
            
            return true
        } else {
            Logger.error("Failed to save app settings to database")
            return false
        }
    }
    
    func isReturnKeyWithTriggerEnabled() -> Bool {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        return cachedSettings?.returnKeyWithTrigger ?? AppSettings.default.returnKeyWithTrigger
    }
    
    func setReturnKeyWithTriggerEnabled(_ enabled: Bool) -> Bool {
        return updateAppSetting(key: "returnKeyWithTrigger", value: enabled ? "true" : "false") { [self] in
            var settings = cachedSettings ?? AppSettings.default
            settings.returnKeyWithTrigger = enabled
            cachedSettings = settings
        }
    }
    
    func isReturnKeyWithoutTriggerEnabled() -> Bool {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        return cachedSettings?.returnKeyWithoutTrigger ?? AppSettings.default.returnKeyWithoutTrigger
    }
    
    func setReturnKeyWithoutTriggerEnabled(_ enabled: Bool) -> Bool {
        return updateAppSetting(key: "returnKeyWithoutTrigger", value: enabled ? "true" : "false") { [self] in
            var settings = cachedSettings ?? AppSettings.default
            settings.returnKeyWithoutTrigger = enabled
            cachedSettings = settings
        }
    }
    
    /// Update preferred language immediately
    func setPreferredLanguage(_ language: String) -> Bool {
        return updateAppSetting(key: "preferredLanguage", value: language) { [self] in
            var settings = cachedSettings ?? AppSettings.default
            settings.preferredLanguage = language
            cachedSettings = settings
        }
    }
    
    /// Update translation rule type immediately
    func setTranslationRuleType(_ ruleType: String) -> Bool {
        return updateAppSetting(key: "translationRuleType", value: ruleType) { [self] in
            var settings = cachedSettings ?? AppSettings.default
            settings.translationRuleType = ruleType
            cachedSettings = settings
        }
    }
    
    /// Update translation rule languages for includes mode immediately
    func setTranslationRuleLanguagesIncludes(_ languages: [String]) -> Bool {
        let languagesStr = languages.joined(separator: ", ")
        return updateAppSetting(key: "translationRuleLanguagesIncludes", value: languagesStr) { [self] in
            var settings = cachedSettings ?? AppSettings.default
            settings.translationRuleLanguagesIncludes = languages
            cachedSettings = settings
        }
    }
    
    /// Update translation rule languages for excludes mode immediately
    func setTranslationRuleLanguagesExcludes(_ languages: [String]) -> Bool {
        let languagesStr = languages.joined(separator: ", ")
        return updateAppSetting(key: "translationRuleLanguagesExcludes", value: languagesStr) { [self] in
            var settings = cachedSettings ?? AppSettings.default
            settings.translationRuleLanguagesExcludes = languages
            cachedSettings = settings
        }
    }
    

    
    /// Generic method to update individual app settings immediately
    private func updateAppSetting(key: String, value: String, updateCache: @escaping () -> Void) -> Bool {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        
        // Update in database immediately
        if updateAppSettingInDatabase(key: key, value: value) {
            // Update cache
            updateCache()
            Logger.info("App setting '\(key)' updated to: \(value)")
            return true
        } else {
            Logger.error("Failed to update app setting '\(key)'")
            return false
        }
    }

       
    /// Get user's preferred language for translation
    func getUserPreferredLanguage() -> String {
        // Get user's preferred language from settings
        let appSettings = loadAppSettings()
        let preferredLanguage = appSettings.preferredLanguage
        
        Logger.debug("User preferred language from settings: \(preferredLanguage)")
        
        // Return the user's preferred language, or fallback to system language if not set
        if !preferredLanguage.isEmpty {
            return preferredLanguage
        }
        
        // Fallback to system locale if no preference is set
        let languageCode = EnvironmentManager.shared.getSystemLanguage()
        
        Logger.debug("Fallback to system language: \(languageCode)")
        
        return languageCode
    }
    
    // MARK: - Database Operations for Language Configurations
    
    /// Load language configurations from database
    private func loadLanguageConfigsFromDatabase() -> Bool {
        guard let db = DatabaseManager.shared.getDatabase() else {
            Logger.error("Database not available")
            return false
        }
        
        let querySQL = """
            SELECT lang_iso639, lang_name, popular, triggers
            FROM language_configs 
            ORDER BY popular ASC, lang_name ASC;
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK else {
            Logger.error("Failed to prepare language configs query")
            return false
        }
        
        defer { sqlite3_finalize(statement) }
        
        var configs: [LanguageConfig] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let codePtr = sqlite3_column_text(statement, 0),
                  let namePtr = sqlite3_column_text(statement, 1),
                  let triggersPtr = sqlite3_column_text(statement, 3) else {
                continue
            }
            
            let code = String(cString: codePtr)
            let name = String(cString: namePtr)
            let popular = Int(sqlite3_column_int(statement, 2))
            let triggersStr = String(cString: triggersPtr)
            
            // Parse triggers as comma-separated string
            let triggers = triggersStr.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            
            let config = LanguageConfig(
                code: code,
                name: name,
                popular: popular,
                triggers: triggers
            )
            configs.append(config)
        }
        
        if configs.isEmpty {
            return false
        }
        
        cachedConfigs = configs
        return true
    }
    
    /// Save language configurations to database
    private func saveLanguageConfigsToDatabase(_ configs: [LanguageConfig]) -> Bool {
        guard let db = DatabaseManager.shared.getDatabase() else {
            Logger.error("Database not available")
            return false
        }
        
        let insertOrReplaceSQL = """
            INSERT OR REPLACE INTO language_configs (lang_name, lang_native_name, lang_iso639, lang_bcp47, popular, triggers, updated_time)
            VALUES (?, ?, ?, ?, ?, ?, datetime('now'));
        """
        
        for config in configs {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, insertOrReplaceSQL, -1, &statement, nil) == SQLITE_OK else {
                Logger.error("Failed to prepare language config insert/replace")
                continue
            }
            
            defer { sqlite3_finalize(statement) }
            
            // Convert triggers to comma-separated string
            let triggersStr = config.triggers.joined(separator: ", ")
            
            sqlite3_bind_text(statement, 1, (config.name as NSString).utf8String, -1, nil) // lang_name
            sqlite3_bind_text(statement, 2, (config.name as NSString).utf8String, -1, nil) // lang_native_name
            sqlite3_bind_text(statement, 3, (config.code as NSString).utf8String, -1, nil) // lang_iso639
            sqlite3_bind_text(statement, 4, (config.code as NSString).utf8String, -1, nil) // lang_bcp47
            sqlite3_bind_int(statement, 5, Int32(config.popular))
            sqlite3_bind_text(statement, 6, (triggersStr as NSString).utf8String, -1, nil)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                let errorMsg = String(cString: sqlite3_errmsg(db))
                Logger.error("Failed to insert/replace language config \(config.code): \(errorMsg)")
            }
        }
        
        return true
    }
    
    /// Clear language configurations from database
    private func clearLanguageConfigsFromDatabase() -> Bool {
        guard let db = DatabaseManager.shared.getDatabase() else {
            Logger.error("Database not available")
            return false
        }
        
        let deleteSQL = "DELETE FROM language_configs;"
        let result = sqlite3_exec(db, deleteSQL, nil, nil, nil)
        
        if result == SQLITE_OK {
            Logger.info("Cleared language configurations from database")
            return true
        } else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            Logger.error("Failed to clear language configurations: \(errorMsg)")
            return false
        }
    }
    
    // MARK: - Database Operations for App Settings
    
    /// Load app settings from database
    private func loadAppSettingsFromDatabase() -> AppSettings? {
        guard let db = DatabaseManager.shared.getDatabase() else {
            Logger.error("Database not available")
            return nil
        }
        
        let querySQL = """
            SELECT config_key, config_value
            FROM configs 
            WHERE config_key IN ('preferredLanguage', 'translationRuleType', 'translationRuleLanguagesIncludes', 'translationRuleLanguagesExcludes', 'returnKeyWithTrigger', 'returnKeyWithoutTrigger');
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK else {
            Logger.error("Failed to prepare app settings query")
            return nil
        }
        
        defer { sqlite3_finalize(statement) }
        
        var settings = AppSettings.default
        var foundAny = false
        
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let keyPtr = sqlite3_column_text(statement, 0),
                  let valuePtr = sqlite3_column_text(statement, 1) else {
                continue
            }
            
            let key = String(cString: keyPtr)
            let value = String(cString: valuePtr)
            foundAny = true
            
            switch key {
            case "preferredLanguage":
                settings.preferredLanguage = value
            case "translationRuleType":
                settings.translationRuleType = value
            case "translationRuleLanguagesIncludes":
                settings.translationRuleLanguagesIncludes = value.isEmpty ? [] : value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            case "translationRuleLanguagesExcludes":
                settings.translationRuleLanguagesExcludes = value.isEmpty ? [] : value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            case "returnKeyWithTrigger":
                settings.returnKeyWithTrigger = value.lowercased() == "true"
            case "returnKeyWithoutTrigger":
                settings.returnKeyWithoutTrigger = value.lowercased() == "true"
            default:
                break
            }
        }
        
        return foundAny ? settings : nil
    }
    
    /// Save app settings to database
    private func saveAppSettingsToDatabase(_ settings: AppSettings) -> Bool {
        guard let db = DatabaseManager.shared.getDatabase() else {
            Logger.error("Database not available")
            return false
        }
        
        let settingsDict = [
            "preferredLanguage": settings.preferredLanguage,
            "translationRuleType": settings.translationRuleType,
            "translationRuleLanguagesIncludes": settings.translationRuleLanguagesIncludes.joined(separator: ","),
            "translationRuleLanguagesExcludes": settings.translationRuleLanguagesExcludes.joined(separator: ","),
            "returnKeyWithTrigger": settings.returnKeyWithTrigger ? "true" : "false",
            "returnKeyWithoutTrigger": settings.returnKeyWithoutTrigger ? "true" : "false"
        ]
        
        let insertOrUpdateSQL = """
            INSERT OR REPLACE INTO configs (config_key, config_value, updated_time)
            VALUES (?, ?, datetime('now'));
        """
        
        for (key, value) in settingsDict {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, insertOrUpdateSQL, -1, &statement, nil) == SQLITE_OK else {
                Logger.error("Failed to prepare config insert for \(key)")
                continue
            }
            
            defer { sqlite3_finalize(statement) }
            
            sqlite3_bind_text(statement, 1, (key as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (value as NSString).utf8String, -1, nil)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                let errorMsg = String(cString: sqlite3_errmsg(db))
                Logger.error("Failed to save config \(key): \(errorMsg)")
            }
        }
        
        return true
    }
    
    /// Update a single language configuration in database
    private func updateLanguageConfigInDatabase(_ config: LanguageConfig) -> Bool {
        guard let db = DatabaseManager.shared.getDatabase() else {
            Logger.error("Database not available")
            return false
        }
        
        let updateSQL = """
            UPDATE language_configs 
            SET lang_name = ?, popular = ?, triggers = ?, updated_time = datetime('now')
            WHERE lang_iso639 = ?;
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, updateSQL, -1, &statement, nil) == SQLITE_OK else {
            Logger.error("Failed to prepare language config update")
            return false
        }
        
        defer { sqlite3_finalize(statement) }
        
        // Convert triggers to comma-separated string
        let triggersStr = config.triggers.joined(separator: ", ")
        
        sqlite3_bind_text(statement, 1, (config.name as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 2, Int32(config.popular))
        sqlite3_bind_text(statement, 3, (triggersStr as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 4, (config.code as NSString).utf8String, -1, nil)
        
        if sqlite3_step(statement) == SQLITE_DONE {
            return true
        } else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            Logger.error("Failed to update language config \(config.code): \(errorMsg)")
            return false
        }
    }
    
    /// Update only triggers for a specific language in database
    private func updateLanguageTriggersInDatabase(languageCode: String, triggers: [String]) -> Bool {
        guard let db = DatabaseManager.shared.getDatabase() else {
            Logger.error("Database not available")
            return false
        }
        
        let updateSQL = """
            UPDATE language_configs 
            SET triggers = ?, updated_time = datetime('now')
            WHERE lang_iso639 = ?;
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, updateSQL, -1, &statement, nil) == SQLITE_OK else {
            Logger.error("Failed to prepare language triggers update")
            return false
        }
        
        defer { sqlite3_finalize(statement) }
        
        // Convert triggers to comma-separated string
        let triggersStr = triggers.joined(separator: ", ")
        
        sqlite3_bind_text(statement, 1, (triggersStr as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (languageCode as NSString).utf8String, -1, nil)
        
        if sqlite3_step(statement) == SQLITE_DONE {
            return true
        } else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            Logger.error("Failed to update language triggers for \(languageCode): \(errorMsg)")
            return false
        }
    }
    
    /// Update a single app setting in database
    private func updateAppSettingInDatabase(key: String, value: String) -> Bool {
        guard let db = DatabaseManager.shared.getDatabase() else {
            Logger.error("Database not available")
            return false
        }
        
        // First check if the key already exists
        let checkSQL = "SELECT COUNT(*) FROM configs WHERE config_key = ?;"
        var checkStatement: OpaquePointer?
        guard sqlite3_prepare_v2(db, checkSQL, -1, &checkStatement, nil) == SQLITE_OK else {
            Logger.error("Failed to prepare check statement for \(key)")
            return false
        }
        
        defer { sqlite3_finalize(checkStatement) }
        
        sqlite3_bind_text(checkStatement, 1, (key as NSString).utf8String, -1, nil)
        
        var exists = false
        if sqlite3_step(checkStatement) == SQLITE_ROW {
            exists = sqlite3_column_int(checkStatement, 0) > 0
        }
        
        Logger.debug("App setting '\(key)' exists in database: \(exists)")
        
        let insertOrUpdateSQL = """
            INSERT OR REPLACE INTO configs (config_key, config_value, updated_time)
            VALUES (?, ?, datetime('now'));
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertOrUpdateSQL, -1, &statement, nil) == SQLITE_OK else {
            Logger.error("Failed to prepare app setting update for \(key)")
            return false
        }
        
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, (key as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (value as NSString).utf8String, -1, nil)
        
        if sqlite3_step(statement) == SQLITE_DONE {
            Logger.info("App setting '\(key)' \(exists ? "updated" : "inserted") with value: \(value)")
            return true
        } else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            Logger.error("Failed to update app setting \(key): \(errorMsg)")
            return false
        }
    }
    
} 
