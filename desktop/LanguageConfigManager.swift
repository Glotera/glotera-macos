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
    
    // 缓存相关属性
    private var cachedConfigs: [LanguageConfig]?
    private var lastLoadTime: Date?
    private var configFileModificationDate: Date?
    
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
    
    private init() {
        // 应用启动时预加载配置
        preloadConfigs()
    }
    
    // 预加载配置（应用启动时调用）
    private func preloadConfigs() {
        Logger.info("Preloading language configurations...")
        _ = loadLanguageConfigs()
    }
    
    // 加载语言配置（使用缓存）
    func loadLanguageConfigs() -> [LanguageConfig] {
        // 检查是否需要重新加载
        if shouldReloadConfigs() {
            Logger.info("Reloading language configurations...")
            cachedConfigs = loadConfigsFromDisk()
            lastLoadTime = Date()
            updateConfigFileModificationDate()
        } else if let cached = cachedConfigs {
            Logger.debug("Using cached language configurations (\(cached.count) configs)")
            return cached
        }
        
        // 如果缓存为空，强制加载
        if cachedConfigs == nil {
            Logger.info("No cached configs, loading from disk...")
            cachedConfigs = loadConfigsFromDisk()
            lastLoadTime = Date()
            updateConfigFileModificationDate()
        }
        
        return cachedConfigs ?? []
    }
    
    // 检查是否需要重新加载配置
    private func shouldReloadConfigs() -> Bool {
        // 如果从未加载过，需要加载
        guard let lastLoad = lastLoadTime else {
            return true
        }
        
        // 检查配置文件是否被修改
        if hasConfigFileChanged() {
            Logger.info("Config file has been modified, reloading...")
            return true
        }
        
        // 如果缓存超过5分钟，重新加载（可选的安全机制）
        // if Date().timeIntervalSince(lastLoad) > 300 {
        //     Logger.info("Cache is older than 5 minutes, reloading...")
        //     return true
        // }
        
        return false
    }
    
    // 检查配置文件是否已更改
    private func hasConfigFileChanged() -> Bool {
        let currentModificationDate = getConfigFileModificationDate()
        
        if let lastModDate = configFileModificationDate {
            return currentModificationDate != lastModDate
        }
        
        return currentModificationDate != nil
    }
    
    // 获取配置文件的修改时间
    private func getConfigFileModificationDate() -> Date? {
        // 优先检查用户配置文件
        if FileManager.default.fileExists(atPath: configFileURL.path) {
            return try? FileManager.default.attributesOfItem(atPath: configFileURL.path)[.modificationDate] as? Date
        }
        
        // 检查默认配置文件
        if let defaultURL = defaultConfigFileURL {
            return try? FileManager.default.attributesOfItem(atPath: defaultURL.path)[.modificationDate] as? Date
        }
        
        return nil
    }
    
    // 更新配置文件修改时间记录
    private func updateConfigFileModificationDate() {
        configFileModificationDate = getConfigFileModificationDate()
    }
    
    // 从磁盘加载配置
    private func loadConfigsFromDisk() -> [LanguageConfig] {
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
        
        Logger.warn("Failed to load any language configurations")
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
            
            // 更新缓存
            cachedConfigs = configs
            lastLoadTime = Date()
            updateConfigFileModificationDate()
            
            return true
        } catch {
            Logger.error("Error saving language configs: \(error)")
            return false
        }
    }
    
    // 重置为默认配置
    func resetToDefaults() -> [LanguageConfig] {
        // 删除用户配置文件
        try? FileManager.default.removeItem(at: configFileURL)
        Logger.info("User config file deleted, loading defaults")
        
        // 清除缓存，强制重新加载
        invalidateCache()
        
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
    
    // MARK: - 缓存管理方法
    
    // 手动刷新缓存
    func refreshCache() {
        Logger.info("Manually refreshing language config cache")
        invalidateCache()
        _ = loadLanguageConfigs()
    }
    
    // 清除缓存
    func invalidateCache() {
        cachedConfigs = nil
        lastLoadTime = nil
        configFileModificationDate = nil
        Logger.info("Language config cache invalidated")
    }
    
    // 获取缓存状态信息
    func getCacheInfo() -> String {
        var info = "Language Config Cache Info:\n"
        info += "- Cached configs count: \(cachedConfigs?.count ?? 0)\n"
        info += "- Last load time: \(lastLoadTime?.description ?? "Never")\n"
        info += "- Config file modification date: \(configFileModificationDate?.description ?? "Unknown")\n"
        info += "- Cache age: "
        
        if let lastLoad = lastLoadTime {
            let age = Date().timeIntervalSince(lastLoad)
            info += "\(Int(age)) seconds\n"
        } else {
            info += "N/A\n"
        }
        
        info += "- Config file exists: \(FileManager.default.fileExists(atPath: configFileURL.path))\n"
        info += "- User config path: \(configFileURL.path)\n"
        
        if let defaultURL = defaultConfigFileURL {
            info += "- Default config path: \(defaultURL.path)\n"
        }
        
        return info
    }
} 
