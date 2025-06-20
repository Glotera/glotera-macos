import Foundation

/// 日志等级枚举
public enum LogLevel: Int, CaseIterable, Comparable {
    case debug = 0
    case info = 1
    case warn = 2
    case error = 3
    
    /// 日志等级对应的 emoji 标记
    var emoji: String {
        switch self {
        case .debug: return "🐛"
        case .info: return ""
        case .warn: return "⚠️"
        case .error: return "❌"
        }
    }
    
    /// 日志等级名称
    var name: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warn: return "WARN"
        case .error: return "ERROR"
        }
    }
    
    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// 日志输出目标协议
public protocol LogDestination {
    func write(_ message: String, level: LogLevel)
}

/// 控制台日志输出
public class ConsoleLogDestination: LogDestination {
    public init() {}
    
    public func write(_ message: String, level: LogLevel) {
        print(message)
    }
}

/// 文件日志输出（预留扩展）
public class FileLogDestination: LogDestination {
    private let fileURL: URL
    private let fileManager = FileManager.default
    
    public init(fileURL: URL) {
        self.fileURL = fileURL
        createLogFileIfNeeded()
    }
    
    private func createLogFileIfNeeded() {
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
        }
    }
    
    public func write(_ message: String, level: LogLevel) {
        guard let data = (message + "\n").data(using: .utf8) else { return }
        
        if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
            fileHandle.closeFile()
        }
    }
}

/// UI 回调日志输出（预留扩展）
public class CallbackLogDestination: LogDestination {
    private let callback: (String, LogLevel) -> Void
    
    public init(callback: @escaping (String, LogLevel) -> Void) {
        self.callback = callback
    }
    
    public func write(_ message: String, level: LogLevel) {
        callback(message, level)
    }
}

/// 主要的日志工具类
public class Logger {
    /// 当前日志等级，只有等于或高于此等级的日志才会被输出
    public static var currentLevel: LogLevel = .info
    
    /// 日志输出目标列表
    private static var destinations: [LogDestination] = [ConsoleLogDestination()]
    
    /// 日期格式化器
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
    
    /// 最大调用栈深度
    public static var maxStackDepth: Int = 10
    
    /// 最大调用链长度
    public static var maxCallChainLength: Int = 5
    
    /// 是否显示详细的堆栈信息（除了调用链之外）
    public static var showDetailedStack: Bool = false
    
    /// 添加日志输出目标
    /// - Parameter destination: 日志输出目标
    public static func addDestination(_ destination: LogDestination) {
        destinations.append(destination)
    }
    
    /// 移除所有日志输出目标
    public static func removeAllDestinations() {
        destinations.removeAll()
    }
    
    /// 设置日志输出目标
    /// - Parameter destinations: 日志输出目标数组
    public static func setDestinations(_ destinations: [LogDestination]) {
        self.destinations = destinations
    }
    
    /// 主要的日志记录方法
    /// - Parameters:
    ///   - message: 日志消息
    ///   - level: 日志等级，默认为 .info
    ///   - file: 调用文件路径（自动获取）
    ///   - function: 调用函数名（自动获取）
    ///   - line: 调用行号（自动获取）
    public static func log(
        _ message: String,
        level: LogLevel = .info,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        // 检查日志等级
        guard level >= currentLevel else { return }
        
        // 提取文件名（不含路径）
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        
        // 格式化时间戳
        let timestamp = dateFormatter.string(from: Date())
        
        // 构建基础日志消息
        let logMessage = "\(level.emoji) [\(timestamp)] [\(level.name)] \(fileName):\(line) \(function) - \(message)"
        
        // 如果是 debug 等级，添加调用栈信息
        var finalMessage = logMessage
        if level == .debug {
            let callStack = Thread.callStackSymbols
            let stackTrace = formatCallStack(callStack)
            finalMessage += "\n" + stackTrace
        }
        
        // 输出到所有目标
        for destination in destinations {
            destination.write(finalMessage, level: level)
        }
    }
    
    // MARK: - 便捷方法
    
    /// Debug 日志
    /// - Parameters:
    ///   - message: 日志消息
    ///   - file: 调用文件路径（自动获取）
    ///   - function: 调用函数名（自动获取）
    ///   - line: 调用行号（自动获取）
    public static func debug(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .debug, file: file, function: function, line: line)
    }
    
    /// Info 日志
    /// - Parameters:
    ///   - message: 日志消息
    ///   - file: 调用文件路径（自动获取）
    ///   - function: 调用函数名（自动获取）
    ///   - line: 调用行号（自动获取）
    public static func info(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .info, file: file, function: function, line: line)
    }
    
    /// Warning 日志
    /// - Parameters:
    ///   - message: 日志消息
    ///   - file: 调用文件路径（自动获取）
    ///   - function: 调用函数名（自动获取）
    ///   - line: 调用行号（自动获取）
    public static func warn(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .warn, file: file, function: function, line: line)
    }
    
    /// Error 日志
    /// - Parameters:
    ///   - message: 日志消息
    ///   - file: 调用文件路径（自动获取）
    ///   - function: 调用函数名（自动获取）
    ///   - line: 调用行号（自动获取）
    public static func error(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .error, file: file, function: function, line: line)
    }
    
    /// 格式化调用栈为可读的函数调用链
    private static func formatCallStack(_ callStack: [String]) -> String {
        let relevantFrames = extractRelevantFrames(callStack)
        
        if relevantFrames.isEmpty {
            return "  📍 Call Chain: Unable to parse call stack"
        }
        
        // 创建调用链字符串 (A -> B -> C 格式)
        let callChain = relevantFrames.reversed().joined(separator: " -> ")
        
        var result = "  📍 Call Chain: \(callChain)"
        
        // 如果需要详细堆栈信息，也显示原始堆栈
        if showDetailedStack {
            result += "\n  📋 Detailed Stack:"
            for (index, frame) in callStack.prefix(maxStackDepth).enumerated() {
                result += "\n    \(index + 1)   \(frame)"
            }
        }
        
        return result
    }
    
    /// 从调用栈中提取相关的函数调用帧
    private static func extractRelevantFrames(_ callStack: [String]) -> [String] {
        var relevantFrames: [String] = []
        
        for frame in callStack {
            // 如果已经达到最大长度，停止处理
            if relevantFrames.count >= maxCallChainLength {
                break
            }
            
            // 跳过系统框架和 Logger 自身的调用
            if frame.contains("Foundation") || 
               frame.contains("CoreFoundation") ||
               frame.contains("libdispatch") ||
               frame.contains("Logger.swift") ||
               frame.contains("Logger.") ||
               frame.contains("__") || // 系统内部函数
               frame.contains("swift_once") ||
               frame.contains("dispatch_") ||
               frame.contains("_dispatch_") ||
               frame.contains("pthread_") {
                continue
            }
            
            // 只处理包含 desktop 相关的调用
            if !frame.contains("desktop") {
                continue
            }
            
            // 解析 Swift 符号
            if let functionName = parseSwiftSymbol(frame) {
                // 避免重复添加相同的函数
                if !relevantFrames.contains(functionName) {
                    relevantFrames.append(functionName)
                }
            }
        }
        
        return relevantFrames
    }
    
    /// 解析 Swift 符号，提取类名和函数名
    private static func parseSwiftSymbol(_ frame: String) -> String? {
        // 首先尝试从符号中提取可读信息
        if let readableName = extractReadableName(from: frame) {
            return readableName
        }
        
        // 如果包含已知的类名，尝试提取
        let knownClasses = ["AXController", "InputMonitor", "AppDelegate", "TranslationMenuWindow", "TranslationResultWindow", "MenuBarController", "TranslatorClient", "TranslateAgent", "LanguageConfigManager", "LanguageConfigWindow"]
        
        for className in knownClasses {
            if frame.contains(className) {
                // 尝试提取方法名
                if let methodName = extractMethodName(from: frame, className: className) {
                    return "\(className).\(methodName)()"
                } else {
                    return "\(className).unknownMethod()"
                }
            }
        }
        
        return nil
    }
    
    /// 提取方法名
    private static func extractMethodName(from frame: String, className: String) -> String? {
        // 常见的方法名模式
        let methodPatterns = [
            "getSelectedText", "hideMenuIfNoSelection", "checkForTextSelection", "startSelectionMonitoring",
            "handleSpaceKey", "setupEventMonitoring", "restartEventMonitoring",
            "applicationDidFinishLaunching", "applicationWillTerminate",
            "translate", "showTranslationMenu", "showTranslationResult",
            "testLoggerCallChain", "functionA", "functionB", "functionC"
        ]
        
        for method in methodPatterns {
            if frame.contains(method) {
                return method
            }
        }
        
        // 尝试从 Swift 符号中提取方法名
        // 匹配模式如: AXControllerC21checkForTextSelection
        let pattern = "\(className)C\\d+([A-Za-z][A-Za-z0-9]*)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: frame, options: [], range: NSRange(location: 0, length: frame.count)) {
            let methodName = extractString(from: frame, range: match.range(at: 1))
            if !methodName.isEmpty && methodName.count > 2 {
                return methodName
            }
        }
        
        return nil
    }
    
    /// 从复杂的 Swift 符号中提取可读的名称
    private static func extractReadableName(from symbol: String) -> String? {
        // 跳过 Logger 自身的调用
        if symbol.contains("Logger") {
            return nil
        }
        
        // 处理具体的已知方法
        let methodMappings = [
            "getSelectedText": "AXController.getSelectedText",
            "hideMenuIfNoSelection": "AXController.hideMenuIfNoSelection", 
            "checkForTextSelection": "AXController.checkForTextSelection",
            "startSelectionMonitoring": "AXController.startSelectionMonitoring",
            "handleSpaceKey": "InputMonitor.handleSpaceKey",
            "setupEventMonitoring": "AppDelegate.setupEventMonitoring",
            "restartEventMonitoring": "AppDelegate.restartEventMonitoring",
            "applicationDidFinishLaunching": "AppDelegate.applicationDidFinishLaunching",
            "testLoggerCallChain": "AppDelegate.testLoggerCallChain",
            "functionA": "AppDelegate.functionA",
            "functionB": "AppDelegate.functionB", 
            "functionC": "AppDelegate.functionC"
        ]
        
        for (method, fullName) in methodMappings {
            if symbol.contains(method) {
                return "\(fullName)()"
            }
        }
        
        // 尝试解析 Swift 符号中的类名和方法名
        // 模式：$s7desktop12AXControllerC21checkForTextSelection...
        if let regex = try? NSRegularExpression(pattern: "\\$s\\d+desktop\\d+([A-Za-z0-9_]+)C\\d+([A-Za-z0-9_]+)", options: []),
           let match = regex.firstMatch(in: symbol, options: [], range: NSRange(location: 0, length: symbol.count)) {
            
            let className = extractString(from: symbol, range: match.range(at: 1))
            let methodName = extractString(from: symbol, range: match.range(at: 2))
            
            if !className.isEmpty && !methodName.isEmpty && className.count > 2 && methodName.count > 2 {
                return "\(className).\(methodName)()"
            }
        }
        
        return nil
    }
    
    /// 从字符串中提取指定范围的子字符串
    private static func extractString(from string: String, range: NSRange) -> String {
        guard range.location != NSNotFound,
              let swiftRange = Range(range, in: string) else {
            return ""
        }
        return String(string[swiftRange])
    }
}

// MARK: - 使用示例和扩展功能

extension Logger {
    /// 配置文件日志输出
    /// - Parameter fileName: 日志文件名，默认为 "app.log"
    public static func enableFileLogging(fileName: String = "app.log") {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let logFileURL = documentsPath.appendingPathComponent(fileName)
        let fileDestination = FileLogDestination(fileURL: logFileURL)
        addDestination(fileDestination)
        
        info("File logging enabled at: \(logFileURL.path)")
    }
    
    /// 配置 UI 回调日志输出
    /// - Parameter callback: 日志回调函数
    public static func enableUICallback(_ callback: @escaping (String, LogLevel) -> Void) {
        let callbackDestination = CallbackLogDestination(callback: callback)
        addDestination(callbackDestination)
        
        info("UI callback logging enabled")
    }
    
    /// 获取当前日志配置信息
    public static func getConfiguration() -> String {
        return """
        📊 Logger Configuration:
        - Current Level: \(currentLevel.name) \(currentLevel.emoji)
        - Destinations: \(destinations.count)
        - Date Format: \(dateFormatter.dateFormat ?? "Unknown")
        """
    }
} 