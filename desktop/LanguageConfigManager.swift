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
    private var cachedConfigs: [LanguageConfig] = []
    private var isInitialized = false
    private let configLock = NSLock()  // 线程安全锁
    
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
        // 应用启动时初始化配置
        initializeConfigs()
    }
    
    // 初始化配置（应用启动时调用，只执行一次）
    private func initializeConfigs() {
        configLock.lock()
        defer { configLock.unlock() }
        
        guard !isInitialized else { return }
        
        Logger.info("Initializing language configurations...")
        cachedConfigs = loadConfigsFromDisk()
        isInitialized = true
        Logger.info("Language configurations initialized with \(cachedConfigs.count) configs")
    }
    
    // 获取语言配置（直接从缓存读取）
    func loadLanguageConfigs() -> [LanguageConfig] {
        configLock.lock()
        defer { configLock.unlock() }
        
        // 确保已初始化
        if !isInitialized {
            Logger.info("Configs not initialized yet, initializing now...")
            cachedConfigs = loadConfigsFromDisk()
            isInitialized = true
        }
        
        Logger.debug("Retrieved \(cachedConfigs.count) language configs from cache")
        return cachedConfigs
    }
    
    // 强制重新加载配置（仅在需要时调用）
    private func forceReloadConfigs() {
        configLock.lock()
        defer { configLock.unlock() }
        
        Logger.info("Force reloading language configurations from disk...")
        cachedConfigs = loadConfigsFromDisk()
        Logger.info("Configurations reloaded, cache updated with \(cachedConfigs.count) configs")
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
    
    // 保存用户配置并立即更新缓存
    func saveLanguageConfigs(_ configs: [LanguageConfig]) -> Bool {
        do {
            let data = try JSONEncoder().encode(configs)
            try data.write(to: configFileURL)
            Logger.info("Successfully saved language configs to: \(configFileURL.path)")
            
            // 立即更新缓存（这是关键性能优化）
            configLock.lock()
            cachedConfigs = configs
            configLock.unlock()
            
            Logger.info("Cache updated with \(configs.count) new configurations")
            return true
        } catch {
            Logger.error("Error saving language configs: \(error)")
            return false
        }
    }
    
    // 重置为默认配置并更新缓存
    func resetToDefaults() -> [LanguageConfig] {
        // 删除用户配置文件
        try? FileManager.default.removeItem(at: configFileURL)
        Logger.info("User config file deleted, resetting to defaults")
        
        // 立即重新加载并更新缓存
        forceReloadConfigs()
        
        return cachedConfigs
    }
    
    // 获取特定语言的触发器（高性能缓存读取）
    func getTriggersForLanguage(_ languageCode: String) -> [String] {
        configLock.lock()
        defer { configLock.unlock() }
        
        return cachedConfigs.first { $0.code == languageCode }?.triggers ?? []
    }
    
    // 获取所有支持的语言代码（高性能缓存读取）
    func getAllLanguageCodes() -> [String] {
        configLock.lock()
        defer { configLock.unlock() }
        
        return cachedConfigs.map { $0.code }
    }
    
    // 根据触发器查找语言代码（高性能缓存读取）
    func findLanguageCode(for trigger: String) -> String? {
        configLock.lock()
        defer { configLock.unlock() }
        
        return cachedConfigs.first { $0.triggers.contains(trigger) }?.code
    }
    
    // MARK: - 缓存管理方法
    
    // 手动刷新缓存（仅在必要时使用）
    func refreshCache() {
        Logger.info("Manually refreshing language config cache")
        forceReloadConfigs()
    }
    
    // 获取缓存状态信息（用于调试）
    func getCacheInfo() -> String {
        configLock.lock()
        defer { configLock.unlock() }
        
        var info = "Language Config Cache Info:\n"
        info += "- Cached configs count: \(cachedConfigs.count)\n"
        info += "- Is initialized: \(isInitialized)\n"
        info += "- Config file exists: \(FileManager.default.fileExists(atPath: configFileURL.path))\n"
        info += "- User config path: \(configFileURL.path)\n"
        
        if let defaultURL = defaultConfigFileURL {
            info += "- Default config path: \(defaultURL.path)\n"
        }
        
        return info
    }
    
    // 预热缓存（可选的公共方法，用于确保初始化完成）
    func warmUpCache() {
        if !isInitialized {
            Logger.info("Warming up language config cache...")
            _ = loadLanguageConfigs()
        }
    }
} 
