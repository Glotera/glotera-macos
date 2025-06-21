import Foundation

// 语言配置数据模型
struct LanguageConfig: Codable {
    let code: String
    let name: String
    let popular: Int
    var triggers: [String]
    
    enum CodingKeys: String, CodingKey {
        case code, name, popular, triggers
    }
}

// 语言配置管理器
class LanguageConfigManager {
    static let shared = LanguageConfigManager()
    
    private let configFileName = "language-triggers-config.json"
    private let defaultConfigFileName = "language-iso-639.json"
    
    private var configFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("Glotera")
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        
        return appFolder.appendingPathComponent(configFileName)
    }
    
    private var defaultConfigFileURL: URL? {
        return Bundle.main.url(forResource: "language-iso-639", withExtension: "json")
    }
    
    private init() {}
    
    // 加载语言配置
    func loadLanguageConfigs() -> [LanguageConfig] {
        Logger.info("Loading language configurations...")
        
        // 首先尝试加载用户自定义配置
        if let userConfigs = loadUserConfigs() {
            Logger.info("Loaded \(userConfigs.count) user-customized language configs")
            return userConfigs
        }
        
        // 如果没有用户配置，加载默认配置
        if let defaultConfigs = loadDefaultConfigs() {
            Logger.info("Loaded \(defaultConfigs.count) default language configs")
            return defaultConfigs
        }
        
        Logger.info("Failed to load any language configurations")
        return []
    }
    
    // 加载用户自定义配置
    private func loadUserConfigs() -> [LanguageConfig]? {
        guard FileManager.default.fileExists(atPath: configFileURL.path) else {
            Logger.info("User config file does not exist: \(configFileURL.path)")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: configFileURL)
            let configs = try JSONDecoder().decode([LanguageConfig].self, from: data)
            return configs
        } catch {
            Logger.info("Error loading user configs: \(error)")
            return nil
        }
    }
    
    // 加载默认配置
    private func loadDefaultConfigs() -> [LanguageConfig]? {
        guard let defaultURL = defaultConfigFileURL else {
            Logger.info("Default config file not found in bundle")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: defaultURL)
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
            
            // 按popular排序，然后按名称排序
            configs.sort { first, second in
                if first.popular != second.popular {
                    return first.popular < second.popular
                }
                return first.name < second.name
            }
            
            return configs
        } catch {
            Logger.info("Error loading default configs: \(error)")
            return nil
        }
    }
    
    // 保存用户配置
    func saveLanguageConfigs(_ configs: [LanguageConfig]) -> Bool {
        do {
            let data = try JSONEncoder().encode(configs)
            try data.write(to: configFileURL)
            Logger.info("Successfully saved language configs to: \(configFileURL.path)")
            return true
        } catch {
            Logger.info("Error saving language configs: \(error)")
            return false
        }
    }
    
    // 重置为默认配置
    func resetToDefaults() -> [LanguageConfig] {
        // 删除用户配置文件
        try? FileManager.default.removeItem(at: configFileURL)
        Logger.info("User config file deleted, loading defaults")
        
        return loadLanguageConfigs()
    }
    
    // 获取特定语言的触发器
    func getTriggersForLanguage(_ languageCode: String) -> [String] {
        let configs = loadLanguageConfigs()
        return configs.first { $0.code == languageCode }?.triggers ?? []
    }
    
    // 获取所有支持的语言代码
    func getAllLanguageCodes() -> [String] {
        return loadLanguageConfigs().map { $0.code }
    }
    
    // 根据触发器查找语言代码
    func findLanguageCode(for trigger: String) -> String? {
        let configs = loadLanguageConfigs()
        return configs.first { $0.triggers.contains(trigger) }?.code
    }
} 