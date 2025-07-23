//
//  TriggerManager.swift
//  Manages trigger detection and pattern management.
//
//  Created by Claude Code on 2025-07-20.
//  Copyright © 2025 Glotera AI. All rights reserved.
//

import Cocoa
import Foundation

// MARK: - Trigger Cache Optimization

/// Compiled regex pattern with metadata for efficient trigger detection
struct CompiledTriggerPattern {
    let regex: NSRegularExpression
    let trigger: String
    let languageCode: String
    let patternType: PatternType
    
    enum PatternType: String, CaseIterable {
        case standard = "standard"           // (.*?)trigger\s*$
        case strictStart = "strictStart"     // ^(.*?)trigger\s*$  
        case spaceDelimited = "spaceDelimited" // (.*?)\s+trigger\s*$
        case multiline = "multiline"         // (?s)(.*?)trigger\s*$
    }
}

/// High-performance trigger cache for compiled regex patterns
class TriggerPatternCache {
    static let shared = TriggerPatternCache()
    
    private var compiledPatterns: [String: [CompiledTriggerPattern]] = [:]
    private var triggerToLanguageMap: [String: String] = [:]
    private var lastConfigurationHash: String = ""
    private let cacheQueue = DispatchQueue(label: "triggerCache", attributes: .concurrent)
    
    // Performance metrics
    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0
    
    private init() {
        refreshCache()
    }
    
    func detectTrigger(in content: String) -> (text: String, lang: String)? {
        let timer = PerformanceTelemetry.shared.startTiming("trigger.detection")
        timer.addContext("content_length", content.count)
        
        let result = cacheQueue.sync { () -> (text: String, lang: String)? in
            // Check if cache needs refresh
            let currentHash = calculateConfigurationHash()
            if currentHash != lastConfigurationHash {
                Logger.info("Configuration changed, refreshing trigger cache")
                refreshCacheInternal()
            }
            
            // Performance optimization: use simple content optimization
            let optimizedContent = getSimpleContentOptimization(content)
            timer.addContext("optimized_length", optimizedContent.count)
            
            // Fast path: try cached patterns for each trigger
            for (_, patterns) in compiledPatterns {
                if let result = checkPatternsForTrigger(patterns, in: optimizedContent) {
                    cacheHits += 1
                    recordPerformanceCounter("trigger.cache.hit")
                    timer.addContext("cache_hit", true)
                    return result
                }
            }
            
            cacheMisses += 1
            recordPerformanceCounter("trigger.cache.miss")
            timer.addContext("cache_hit", false)
            return nil
        }
        
        _ = timer.finish(success: result != nil)
        if let result = result {
            timer.addContext("detected_language", result.lang)
            recordPerformanceCounter("trigger.detection.success")
        } else {
            recordPerformanceCounter("trigger.detection.failure")
        }
        
        return result
    }
    
    func getAllTriggers() -> [String] {
        return cacheQueue.sync {
            return Array(triggerToLanguageMap.keys)
        }
    }
    
    func refreshCache() {
        cacheQueue.async(flags: .barrier) {
            self.refreshCacheInternal()
        }
    }
    
    func getPerformanceMetrics() -> (hits: Int, misses: Int, hitRatio: Double) {
        return cacheQueue.sync {
            let total = cacheHits + cacheMisses
            let hitRatio = total > 0 ? Double(cacheHits) / Double(total) : 0.0
            return (cacheHits, cacheMisses, hitRatio)
        }
    }
    
    private func refreshCacheInternal() {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        compiledPatterns.removeAll()
        triggerToLanguageMap.removeAll()
        
        let configs = ConfigManager.shared.loadLanguageConfigs()
        var patternCount = 0
        
        for config in configs {
            for trigger in config.triggers {
                triggerToLanguageMap[trigger] = config.code
                let patterns = compileAllPatterns(for: trigger, languageCode: config.code)
                compiledPatterns[trigger] = patterns
                patternCount += patterns.count
            }
        }
        
        lastConfigurationHash = calculateConfigurationHash()
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let compilationTime = (endTime - startTime) * 1000
        
        Logger.info("TriggerCache: Compiled \(patternCount) patterns for \(triggerToLanguageMap.count) triggers in \(String(format: "%.2f", compilationTime))ms")
    }
    
    private func compileAllPatterns(for trigger: String, languageCode: String) -> [CompiledTriggerPattern] {
        let escapedTrigger = NSRegularExpression.escapedPattern(for: trigger)
        var patterns: [CompiledTriggerPattern] = []
        
        let patternTemplates: [(String, CompiledTriggerPattern.PatternType)] = [
            (#"(.*?)"# + escapedTrigger + #"\s*$"#, .standard),
            (#"^(.*?)"# + escapedTrigger + #"\s*$"#, .strictStart),
            (#"(.*?)\s+"# + escapedTrigger + #"\s*$"#, .spaceDelimited),
            (#"(?s)(.*?)"# + escapedTrigger + #"\s*$"#, .multiline)
        ]
        
        for (patternString, patternType) in patternTemplates {
            do {
                let regex = try NSRegularExpression(
                    pattern: patternString,
                    options: [.caseInsensitive, .dotMatchesLineSeparators]
                )
                
                let compiledPattern = CompiledTriggerPattern(
                    regex: regex,
                    trigger: trigger,
                    languageCode: languageCode,
                    patternType: patternType
                )
                
                patterns.append(compiledPattern)
            } catch {
                Logger.error("Failed to compile pattern for trigger '\(trigger)': \(error)")
            }
        }
        
        return patterns
    }
    
    private func checkPatternsForTrigger(_ patterns: [CompiledTriggerPattern], in content: String) -> (text: String, lang: String)? {
        let nsContent = content as NSString
        let range = NSRange(location: 0, length: nsContent.length)
        
        for pattern in patterns {
            let matches = pattern.regex.matches(in: content, options: [], range: range)
            
            if let match = matches.first, match.numberOfRanges >= 2 {
                let textRange = match.range(at: 1)
                
                if textRange.location != NSNotFound {
                    let rawText = nsContent.substring(with: textRange)
                    let text = rawText.trimmingCharacters(in: .whitespaces)
                    
                    if !text.isEmpty {
                        return (text: text, lang: pattern.languageCode)
                    }
                }
            }
        }
        
        return nil
    }
    
    private func calculateConfigurationHash() -> String {
        let configs = ConfigManager.shared.loadLanguageConfigs()
        var hashString = ""
        
        for config in configs.sorted(by: { $0.code < $1.code }) {
            hashString += config.code
            hashString += config.triggers.sorted().joined(separator: ",")
        }
        
        return String(hashString.hashValue)
    }
    
    // Simple content optimization for trigger detection
    private func getSimpleContentOptimization(_ content: String) -> String {
        // Performance optimization: only check the last portion of content
        let maxCheckLength = 50 // 只检查最后50个字符
        
        if content.count <= maxCheckLength {
            return content
        }
        
        // 从末尾开始截取
        let startIndex = max(content.count - maxCheckLength, 0)
        return String(content.suffix(from: content.index(content.startIndex, offsetBy: startIndex)))
    }
}

// MARK: - JavaScript Management (now handled by JavaScriptManager)

// MARK: - Trigger Manager Main Class

/// Central manager for trigger detection and pattern management
class TriggerManager {
    static let shared = TriggerManager()
    
    private init() {}
    
    // MARK: - Public API
    
    /// Detect trigger in content and return extracted text and language
    func detectTrigger(in content: String) -> (text: String, lang: String)? {
        return TriggerPatternCache.shared.detectTrigger(in: content)
    }
    
    /// Get all configured triggers
    func getAllTriggers() -> [String] {
        return TriggerPatternCache.shared.getAllTriggers()
    }
    
    /// Refresh all trigger caches when configuration changes
    func refreshCaches() {
        TriggerPatternCache.shared.refreshCache()
        JavaScriptManager.shared.refreshCaches()
        Logger.info("TriggerManager: Refreshed all pattern caches")
    }
    
    /// Get JavaScript pattern code for browser
    func getJavaScriptPatternCode(for bundleId: String) -> String {
        return JavaScriptManager.shared.getJavaScriptPatternCode(for: bundleId)
    }
    
    /// Clear JavaScript cache for specific browser or all browsers
    func clearJavaScriptCache(for bundleId: String? = nil) {
        JavaScriptManager.shared.clearCache(for: bundleId)
    }
    
    /// Get performance metrics for trigger detection
    func getPerformanceMetrics() -> (triggerCache: (hits: Int, misses: Int, hitRatio: Double), jsCache: (cachedBrowsers: Int, totalSize: Int)) {
        let triggerMetrics = TriggerPatternCache.shared.getPerformanceMetrics()
        let jsMetrics = JavaScriptManager.shared.getCacheStats()
        return (triggerCache: triggerMetrics, jsCache: jsMetrics)
    }
    
    // MARK: - Pattern Generation Utilities
    
    /// Generate Swift patterns for triggers (used for fallback processing)
    func generateSwiftPatterns(for triggers: [String]) -> [String] {
        guard !triggers.isEmpty else {
            // 如果没有配置的触发器，返回默认模式
            return [
                #"(.*?)[@#](id|en|zh|ja|jp|ko|fr|de|es|ru|th)\s*$"#,
                #"^(.*?)[@#](id|en|zh|ja|jp|ko|fr|de|es|ru|th)\s*$"#,
                #"(.*?)\s+[@#](id|en|zh|ja|jp|ko|fr|de|es|ru|th)\s*$"#
            ]
        }
        
        var patterns: [String] = []
        
        // 为每个触发器生成模式
        for trigger in triggers {
            // 转义Swift正则表达式中的特殊字符
            let escapedTrigger = NSRegularExpression.escapedPattern(for: trigger)
            
            // 生成不同的匹配模式
            patterns.append("(.*?)" + escapedTrigger + "\\s*$")      // 标准模式
            patterns.append("^(.*?)" + escapedTrigger + "\\s*$")     // 严格开头模式
            patterns.append("(.*?)\\s+" + escapedTrigger + "\\s*$")  // 空格分隔
        }
        
        return patterns
    }
    
    /// Process content with default triggers as fallback
    func processContentWithDefaultTriggers(_ content: String) -> (text: String, lang: String)? {
        Logger.info("TriggerManager: Using fallback default trigger processing")
        
        // 默认触发器模式
        let patterns = [
            #"(.*?)[@#](id|en|zh|ja|jp|ko|fr|de|es|ru|th)\s*$"#,      // 标准模式
            #"^(.*?)[@#](id|en|zh|ja|jp|ko|fr|de|es|ru|th)\s*$"#,     // 严格开头模式
            #"(.*?)\s+[@#](id|en|zh|ja|jp|ko|fr|de|es|ru|th)\s*$"#,   // 空格分隔
            #"(?s)(.*?)[@#](id|en|zh|ja|jp|ko|fr|de|es|ru|th)\s*$"#   // 多行支持
        ]
        
        for (index, pattern) in patterns.enumerated() {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let nsValue = content as NSString
                let results = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsValue.length))
                
                if let match = results.first, match.numberOfRanges >= 3 {
                    let textRange = match.range(at: 1)
                    let langRange = match.range(at: 2)
                    
                    if textRange.location != NSNotFound && langRange.location != NSNotFound {
                        let rawText = nsValue.substring(with: textRange)
                        let text = rawText.trimmingCharacters(in: .whitespaces)
                        var lang = nsValue.substring(with: langRange).lowercased()
                        
                        // 转换 jp 为 ja
                        if lang == "jp" { lang = "ja" }
                        
                        if !text.isEmpty {
                            Logger.info("TriggerManager: Default trigger found using pattern \(index + 1): text='\(text)', lang='\(lang)'")
                            return (text: text, lang: lang)
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    /// Remove trigger from text and return cleaned text
    func removeTriggerFromText(_ fullText: String, detectedText: String, lang: String) -> String {
        Logger.debug("TriggerManager: Removing trigger from text: '\(fullText)', detected text: '\(detectedText)', lang: '\(lang)'")
        
        // 注意：这里的 detectedText 参数实际上是检测到的文本内容，不是触发指令
        // 我们需要从原始文本中移除触发指令部分，保留检测到的文本内容
        
        // 构建触发指令模式（如 #en, @zh 等）
        let triggerPatterns = [
            "#" + lang,  // #en, #zh, #ja 等
            "@" + lang,  // @en, @zh, @ja 等
        ]
        
        // 尝试多种模式来移除触发指令
        let regexPatterns = [
            // 标准模式：文本 + 触发指令
            "^(.*?)\\s*([@#]" + NSRegularExpression.escapedPattern(for: lang) + ")\\s*$",
            // 严格模式：文本 + 触发指令（无额外空格）
            "^(.*?)([@#]" + NSRegularExpression.escapedPattern(for: lang) + ")\\s*$",
            // 宽松模式：文本 + 触发指令（可能有其他字符）
            "^(.*?)\\s*([@#]" + NSRegularExpression.escapedPattern(for: lang) + ").*$"
        ]
        
        for pattern in regexPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let nsText = fullText as NSString
                let range = NSRange(location: 0, length: nsText.length)
                let matches = regex.matches(in: fullText, options: [], range: range)
                
                if let match = matches.first, match.numberOfRanges >= 3 {
                    let textRange = match.range(at: 1)
                    if textRange.location != NSNotFound {
                        let cleanedText = nsText.substring(with: textRange).trimmingCharacters(in: .whitespaces)
                        Logger.debug("TriggerManager: Successfully removed trigger via regex, cleaned text: '\(cleanedText)'")
                        return cleanedText
                    }
                }
            }
        }
        
        // 如果正则表达式匹配失败，尝试简单的字符串替换
        var cleanedText = fullText
        
        // 移除所有可能的触发指令
        for triggerPattern in triggerPatterns {
            cleanedText = cleanedText.replacingOccurrences(of: triggerPattern, with: "", options: .caseInsensitive)
        }
        
        // 清理多余的空白字符
        cleanedText = cleanedText.trimmingCharacters(in: .whitespaces)
        
        Logger.debug("TriggerManager: Used string replacement, cleaned text: '\(cleanedText)'")
        return cleanedText
    }
    
    /// Get context around trigger for debugging
    func getContextAroundTrigger(_ content: String, trigger: String) -> String {
        let lowercased = content.lowercased()
        if let range = lowercased.range(of: trigger) {
            let start = max(content.startIndex, content.index(range.lowerBound, offsetBy: -20, limitedBy: content.startIndex) ?? content.startIndex)
            let end = min(content.endIndex, content.index(range.upperBound, offsetBy: 20, limitedBy: content.endIndex) ?? content.endIndex)
            return String(content[start..<end])
        }
        return ""
    }
}