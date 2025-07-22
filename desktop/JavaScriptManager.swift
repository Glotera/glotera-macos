//
//  JavaScriptManager.swift
//  desktop
//
//  Created by Claude Code on 2025-01-20.
//  Copyright © 2025 Glotera AI. All rights reserved.
//

import Cocoa
import Foundation

// MARK: - JavaScript Pattern Caching

/// Browser-specific JavaScript pattern cache for lazy generation
class JavaScriptPatternCache {
    static let shared = JavaScriptPatternCache()
    
    private var patternCache: [String: String] = [:]  // bundleId -> generated JavaScript code
    private var triggerHashCache: [String: String] = [:] // bundleId -> trigger config hash
    private let cacheQueue = DispatchQueue(label: "jsPatternCache", attributes: .concurrent)
    private let cacheTTL: TimeInterval = 300.0 // 5 minutes cache TTL
    private var cacheTimestamps: [String: Date] = [:]
    
    private init() {}
    
    /// Get JavaScript pattern code for a specific browser, generating lazily if needed
    func getJavaScriptPatternCode(for bundleId: String) -> String {
        return cacheQueue.sync {
            let currentHash = calculateTriggerHash()
            let now = Date()
            
            // Check if cache is valid
            if let cachedCode = patternCache[bundleId],
               let cachedHash = triggerHashCache[bundleId],
               let timestamp = cacheTimestamps[bundleId],
               cachedHash == currentHash,
               now.timeIntervalSince(timestamp) < cacheTTL {
                Logger.debug("JSPatternCache: Cache hit for \(bundleId)")
                return cachedCode
            }
            
            // Generate fresh pattern code
            Logger.debug("JSPatternCache: Generating fresh patterns for \(bundleId)")
            let patterns = generateJavaScriptPatternsLazy()
            let jsCode = createJavaScriptCode(with: patterns)
            
            // Cache the results
            patternCache[bundleId] = jsCode
            triggerHashCache[bundleId] = currentHash
            cacheTimestamps[bundleId] = now
            
            Logger.info("JSPatternCache: Generated and cached \(patterns.count) patterns for \(bundleId)")
            return jsCode
        }
    }
    
    /// Clear cache for a specific browser or all browsers
    func clearCache(for bundleId: String? = nil) {
        cacheQueue.async(flags: .barrier) {
            if let bundleId = bundleId {
                self.patternCache.removeValue(forKey: bundleId)
                self.triggerHashCache.removeValue(forKey: bundleId)
                self.cacheTimestamps.removeValue(forKey: bundleId)
                Logger.debug("JSPatternCache: Cleared cache for \(bundleId)")
            } else {
                self.patternCache.removeAll()
                self.triggerHashCache.removeAll()
                self.cacheTimestamps.removeAll()
                Logger.debug("JSPatternCache: Cleared all cache")
            }
        }
    }
    
    /// Get cache statistics
    func getCacheStats() -> (cachedBrowsers: Int, totalSize: Int) {
        return cacheQueue.sync {
            let totalSize = patternCache.values.reduce(0) { $0 + $1.count }
            return (cachedBrowsers: patternCache.count, totalSize: totalSize)
        }
    }
    
    // MARK: - Private Methods
    
    private func generateJavaScriptPatternsLazy() -> [String] {
        let allTriggers = JavaScriptManager.shared.getAllTriggersFromTriggerManager()
        
        guard !allTriggers.isEmpty else {
            Logger.warn("JSPatternCache: No triggers configured, using minimal fallback")
            return ["(.*?)[@#](id|en|zh|ja|jp|ko|fr|de|es|ru|th)\\s*$"]
        }
        
        var patterns: [String] = []
        
        // Generate only essential patterns to reduce complexity
        for trigger in allTriggers.prefix(20) { // Limit to first 20 triggers for performance
            let escapedTrigger = escapeJavaScriptRegex(trigger)
            patterns.append("(.*?)" + escapedTrigger + "\\s*$")
        }
        
        Logger.debug("JSPatternCache: Generated \(patterns.count) lazy patterns from \(allTriggers.count) triggers")
        return patterns
    }
    
    private func createJavaScriptCode(with patterns: [String]) -> String {
        let languageCodes = extractLanguageCodes()
        let languageList = languageCodes.prefix(30).map { "'\($0)'" }.joined(separator: ",") // Limit languages
        
        let jsCode = """
            var languageCodes = [\(languageList)];
            var patterns = [
                new RegExp('(.*?)[@#](' + languageCodes.join('|') + ')\\\\s*$', 'i'),
                new RegExp('(.*?)\\\\s+[@#](' + languageCodes.join('|') + ')\\\\s*$', 'i')
            ];
        """
        
        return jsCode
    }
    
    private func escapeJavaScriptRegex(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "+", with: "\\+")
            .replacingOccurrences(of: "?", with: "\\?")
            .replacingOccurrences(of: "^", with: "\\^")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "{", with: "\\{")
            .replacingOccurrences(of: "}", with: "\\}")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
            .replacingOccurrences(of: "|", with: "\\|")
    }
    
    private func extractLanguageCodes() -> [String] {
        let allTriggers = JavaScriptManager.shared.getAllTriggersFromTriggerManager()
        let languageCodes = Set(allTriggers.compactMap { trigger in
            if trigger.hasPrefix("@") || trigger.hasPrefix("#") {
                return String(trigger.dropFirst())
            }
            return nil
        })
        
        if !languageCodes.isEmpty {
            return Array(languageCodes).sorted()
        }
        
        // Minimal fallback language set for better performance
        return ["ar", "bn", "de", "en", "es", "fa", "fr", "hi", "id", "it", "ja", "ko", "ms", "nl", "pl", "pt", "ro", "ru", "ta", "th", "tr", "uk", "ur", "vi", "zh"]
    }
    
    private func calculateTriggerHash() -> String {
        let allTriggers = JavaScriptManager.shared.getAllTriggersFromTriggerManager()
        let hashString = allTriggers.sorted().joined(separator: ",")
        return String(hashString.hashValue)
    }
}

// MARK: - JavaScript Manager Main Class

/// Central manager for JavaScript pattern generation and browser integration
class JavaScriptManager {
    static let shared = JavaScriptManager()
    
    private init() {}
    
    // MARK: - Public API
    
    /// Get JavaScript pattern code for a specific browser
    func getJavaScriptPatternCode(for bundleId: String) -> String {
        return JavaScriptPatternCache.shared.getJavaScriptPatternCode(for: bundleId)
    }
    
    /// Clear JavaScript cache for specific browser or all browsers
    func clearCache(for bundleId: String? = nil) {
        JavaScriptPatternCache.shared.clearCache(for: bundleId)
        Logger.info("JavaScriptManager: Cleared cache\(bundleId != nil ? " for \(bundleId!)" : "")")
    }
    
    /// Get cache statistics
    func getCacheStats() -> (cachedBrowsers: Int, totalSize: Int) {
        return JavaScriptPatternCache.shared.getCacheStats()
    }
    
    /// Force refresh of all JavaScript caches
    func refreshCaches() {
        JavaScriptPatternCache.shared.clearCache()
        Logger.info("JavaScriptManager: Refreshed all JavaScript caches")
    }
    
    // MARK: - Browser-Specific JavaScript Generation
    
    /// Generate JavaScript code for trigger detection in browsers
    func generateBrowserJavaScript(for bundleId: String, triggers: [String] = []) -> String {
        if triggers.isEmpty {
            // Use cached version for better performance
            return getJavaScriptPatternCode(for: bundleId)
        } else {
            // Generate custom JavaScript for specific triggers
            return generateCustomJavaScript(for: triggers)
        }
    }
    
    /// Generate custom JavaScript code for specific triggers
    func generateCustomJavaScript(for triggers: [String]) -> String {
        guard !triggers.isEmpty else {
            return generateFallbackJavaScript()
        }
        
        var patterns: [String] = []
        
        // Generate patterns for provided triggers
        for trigger in triggers.prefix(20) { // Limit for performance
            let escapedTrigger = escapeJavaScriptRegex(trigger)
            patterns.append("(.*?)" + escapedTrigger + "\\s*$")
        }
        
        let languageCodes = extractLanguageCodesFromTriggers(triggers)
        let languageList = languageCodes.map { "'\($0)'" }.joined(separator: ",")
        
        let jsCode = """
            var customLanguageCodes = [\(languageList)];
            var customPatterns = [
                new RegExp('(.*?)[@#](' + customLanguageCodes.join('|') + ')\\\\s*$', 'i'),
                new RegExp('(.*?)\\\\s+[@#](' + customLanguageCodes.join('|') + ')\\\\s*$', 'i')
            ];
        """
        
        Logger.debug("JavaScriptManager: Generated custom JavaScript with \(patterns.count) patterns")
        return jsCode
    }
    
    /// Generate minimal fallback JavaScript
    func generateFallbackJavaScript() -> String {
        let jsCode = """
            var fallbackLanguageCodes = ['en', 'zh', 'ja', 'ko', 'fr', 'de', 'es', 'ru', 'id'];
            var fallbackPatterns = [
                new RegExp('(.*?)[@#](' + fallbackLanguageCodes.join('|') + ')\\\\s*$', 'i'),
                new RegExp('(.*?)\\\\s+[@#](' + fallbackLanguageCodes.join('|') + ')\\\\s*$', 'i')
            ];
        """
        
        Logger.debug("JavaScriptManager: Generated fallback JavaScript patterns")
        return jsCode
    }
    
    // MARK: - Browser Detection Support
    
    /// Get optimized JavaScript for specific browser types
    func getOptimizedJavaScript(for browserType: BrowserType, bundleId: String) -> String {
        switch browserType {
        case .chrome:
            return getChromeOptimizedJavaScript(bundleId: bundleId)
        case .safari:
            return getSafariOptimizedJavaScript(bundleId: bundleId)
        case .firefox:
            return getFirefoxOptimizedJavaScript(bundleId: bundleId)
        case .edge:
            return getEdgeOptimizedJavaScript(bundleId: bundleId)
        case .other:
            return getJavaScriptPatternCode(for: bundleId)
        }
    }
    
    /// Browser types for optimization
    enum BrowserType {
        case chrome
        case safari
        case firefox
        case edge
        case other
    }
    
    // MARK: - Browser-Specific Optimizations
    
    private func getChromeOptimizedJavaScript(bundleId: String) -> String {
        let baseCode = getJavaScriptPatternCode(for: bundleId)
        let chromeOptimizations = """
            // Chrome-specific optimizations
            if (typeof chrome !== 'undefined' && chrome.runtime) {
                console.log('Glotera: Chrome environment detected');
            }
        """
        return baseCode + "\n" + chromeOptimizations
    }
    
    private func getSafariOptimizedJavaScript(bundleId: String) -> String {
        let baseCode = getJavaScriptPatternCode(for: bundleId)
        let safariOptimizations = """
            // Safari-specific optimizations
            if (typeof safari !== 'undefined' && safari.self) {
                console.log('Glotera: Safari environment detected');
            }
        """
        return baseCode + "\n" + safariOptimizations
    }
    
    private func getFirefoxOptimizedJavaScript(bundleId: String) -> String {
        let baseCode = getJavaScriptPatternCode(for: bundleId)
        let firefoxOptimizations = """
            // Firefox-specific optimizations
            if (typeof InstallTrigger !== 'undefined') {
                console.log('Glotera: Firefox environment detected');
            }
        """
        return baseCode + "\n" + firefoxOptimizations
    }
    
    private func getEdgeOptimizedJavaScript(bundleId: String) -> String {
        let baseCode = getJavaScriptPatternCode(for: bundleId)
        let edgeOptimizations = """
            // Edge-specific optimizations
            if (typeof edge !== 'undefined' || navigator.userAgent.includes('Edge')) {
                console.log('Glotera: Edge environment detected');
            }
        """
        return baseCode + "\n" + edgeOptimizations
    }
    
    // MARK: - Utility Methods
    
    /// Get all triggers from TriggerManager (internal use)
    func getAllTriggersFromTriggerManager() -> [String] {
        // This method provides access to TriggerManager for JavaScriptPatternCache
        // We'll update this to use the proper TriggerManager interface once we refactor
        return TriggerPatternCache.shared.getAllTriggers()
    }
    
    /// Escape JavaScript regex characters
    func escapeJavaScriptRegex(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "+", with: "\\+")
            .replacingOccurrences(of: "?", with: "\\?")
            .replacingOccurrences(of: "^", with: "\\^")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "{", with: "\\{")
            .replacingOccurrences(of: "}", with: "\\}")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
            .replacingOccurrences(of: "|", with: "\\|")
    }
    
    /// Extract language codes from trigger list
    func extractLanguageCodesFromTriggers(_ triggers: [String]) -> [String] {
        let languageCodes = Set(triggers.compactMap { trigger in
            if trigger.hasPrefix("@") || trigger.hasPrefix("#") {
                return String(trigger.dropFirst())
            }
            return nil
        })
        
        return Array(languageCodes).sorted()
    }
    
    /// Generate JavaScript pattern for a single trigger
    func generateJavaScriptPattern(for trigger: String) -> String {
        let escapedTrigger = escapeJavaScriptRegex(trigger)
        return "(.*?)" + escapedTrigger + "\\s*$"
    }
    
    /// Validate JavaScript code syntax (basic check)
    func validateJavaScriptSyntax(_ jsCode: String) -> Bool {
        // Basic validation - check for balanced braces and quotes
        let openBraces = jsCode.filter { $0 == "{" }.count
        let closeBraces = jsCode.filter { $0 == "}" }.count
        let singleQuotes = jsCode.filter { $0 == "'" }.count
        let doubleQuotes = jsCode.filter { $0 == "\"" }.count
        
        return openBraces == closeBraces && singleQuotes % 2 == 0 && doubleQuotes % 2 == 0
    }
    
    // MARK: - Performance Monitoring
    
    /// Get detailed performance metrics
    func getDetailedPerformanceMetrics() -> JavaScriptPerformanceMetrics {
        let cacheStats = getCacheStats()
        return JavaScriptPerformanceMetrics(
            cachedBrowsers: cacheStats.cachedBrowsers,
            totalCacheSize: cacheStats.totalSize,
            averageCacheSize: cacheStats.cachedBrowsers > 0 ? cacheStats.totalSize / cacheStats.cachedBrowsers : 0,
            cacheHitRatio: 0.0 // Would need to track hits/misses for actual ratio
        )
    }
    
    /// Performance metrics structure
    struct JavaScriptPerformanceMetrics {
        let cachedBrowsers: Int
        let totalCacheSize: Int
        let averageCacheSize: Int
        let cacheHitRatio: Double
    }
}

// MARK: - Browser Type Detection Helper

extension JavaScriptManager {
    /// Detect browser type from bundle identifier
    func detectBrowserType(from bundleId: String) -> BrowserType {
        let bundleIdLower = bundleId.lowercased()
        
        if bundleIdLower.contains("chrome") {
            return .chrome
        } else if bundleIdLower.contains("safari") {
            return .safari
        } else if bundleIdLower.contains("firefox") {
            return .firefox
        } else if bundleIdLower.contains("edge") {
            return .edge
        } else {
            return .other
        }
    }
    
    /// Get browser-specific performance optimizations
    func getBrowserOptimizations(for browserType: BrowserType) -> String {
        switch browserType {
        case .chrome:
            return """
                // Chrome performance optimizations
                if (document.readyState === 'complete') {
                    // Execute immediately
                } else {
                    window.addEventListener('load', function() {
                        // Execute after load
                    });
                }
            """
        case .safari:
            return """
                // Safari performance optimizations
                if (document.readyState !== 'loading') {
                    // Execute immediately
                } else {
                    document.addEventListener('DOMContentLoaded', function() {
                        // Execute after DOM ready
                    });
                }
            """
        case .firefox:
            return """
                // Firefox performance optimizations
                if (document.readyState === 'complete' || document.readyState === 'interactive') {
                    // Execute immediately
                } else {
                    document.addEventListener('DOMContentLoaded', function() {
                        // Execute after DOM ready
                    });
                }
            """
        case .edge:
            return """
                // Edge performance optimizations
                if (document.readyState === 'complete') {
                    // Execute immediately
                } else {
                    window.addEventListener('load', function() {
                        // Execute after load
                    });
                }
            """
        case .other:
            return """
                // Generic browser optimizations
                if (document.readyState !== 'loading') {
                    // Execute immediately
                } else {
                    document.addEventListener('DOMContentLoaded', function() {
                        // Execute after DOM ready
                    });
                }
            """
        }
    }
}