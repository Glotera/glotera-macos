import Foundation
import AppKit

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

/// 文件日志输出
public class FileLogDestination: LogDestination {
    private let fileURL: URL
    private let fileManager = FileManager.default
    private let maxFileSize: UInt64 // 最大文件大小（字节）
    private let maxFiles: Int // 最大文件数量
    private let logQueue = DispatchQueue(label: "com.glotera.logger.file", qos: .utility)
    
    public init(fileURL: URL, maxFileSize: UInt64 = 10 * 1024 * 1024, maxFiles: Int = 5) {
        self.fileURL = fileURL
        self.maxFileSize = maxFileSize
        self.maxFiles = maxFiles
        createLogFileIfNeeded()
    }
    
    private func createLogFileIfNeeded() {
        let directory = fileURL.deletingLastPathComponent()
        
        // 创建目录（如果不存在）
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        
        // 创建日志文件（如果不存在）
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
        }
    }
    
    public func write(_ message: String, level: LogLevel) {
        logQueue.async {
            self.writeToFile(message)
        }
    }
    
    private func writeToFile(_ message: String) {
        guard let data = (message + "\n").data(using: .utf8) else { return }
        
        // 检查文件大小，如果超过限制则轮转
        checkAndRotateFile()
        
        // 写入日志
        if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
            fileHandle.closeFile()
        }
    }
    
    private func checkAndRotateFile() {
        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let fileSize = attributes[.size] as? UInt64 else { return }
        
        if fileSize > maxFileSize {
            rotateLogFile()
        }
    }
    
    private func rotateLogFile() {
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let fileExtension = fileURL.pathExtension.isEmpty ? "log" : fileURL.pathExtension
        
        // 删除最旧的文件
        for i in stride(from: maxFiles - 1, through: 1, by: -1) {
            let oldFile = fileURL.deletingLastPathComponent()
                .appendingPathComponent("\(baseName).\(i).\(fileExtension)")
            try? fileManager.removeItem(at: oldFile)
        }
        
        // 重命名现有文件
        for i in stride(from: maxFiles - 2, through: 0, by: -1) {
            let oldFile = fileURL.deletingLastPathComponent()
                .appendingPathComponent("\(baseName).\(i).\(fileExtension)")
            let newFile = fileURL.deletingLastPathComponent()
                .appendingPathComponent("\(baseName).\(i + 1).\(fileExtension)")
            try? fileManager.moveItem(at: oldFile, to: newFile)
        }
        
        // 重命名当前文件
        let rotatedFile = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(baseName).1.\(fileExtension)")
        try? fileManager.moveItem(at: fileURL, to: rotatedFile)
        
        // 创建新的日志文件
        createLogFileIfNeeded()
    }
    
    /// 获取日志文件路径
    public func getLogFilePath() -> String {
        return fileURL.path
    }
    
    /// 获取日志文件大小
    public func getLogFileSize() -> UInt64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let fileSize = attributes[.size] as? UInt64 else { return 0 }
        return fileSize
    }
    
    /// 清空日志文件
    public func clearLogFile() {
        try? "".write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    /// 获取所有日志文件
    public func getAllLogFiles() -> [URL] {
        let directory = fileURL.deletingLastPathComponent()
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let fileExtension = fileURL.pathExtension.isEmpty ? "log" : fileURL.pathExtension
        
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey], options: []) else {
            return []
        }
        
        return files.filter { file in
            file.lastPathComponent.hasPrefix(baseName) && file.lastPathComponent.hasSuffix(fileExtension)
        }.sorted { file1, file2 in
            let date1 = try? file1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
            let date2 = try? file2.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
            return date1! > date2!
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
         let finalMessage = logMessage
        // if level == .debug {
        //     let callStack = Thread.callStackSymbols
        //     let stackTrace = formatCallStack(callStack)
        //     finalMessage += "\n" + stackTrace
        // }
        
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
        let knownClasses = ["AXController", "InputMonitor", "AppDelegate", "TranslationMenuWindow", "TranslationResultWindow", "MenuBarController", "TranslatorClient", "TranslateAgent", "ConfigManager", "ConfigWindow"]
        
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
    /// - Parameters:
    ///   - fileName: 日志文件名，默认为 "glotera.log"
    ///   - maxFileSize: 最大文件大小（字节），默认 10MB
    ///   - maxFiles: 最大文件数量，默认 5 个
    public static func enableFileLogging(fileName: String = "glotera.log", maxFileSize: UInt64 = 10 * 1024 * 1024, maxFiles: Int = 5) {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let logsDirectory = documentsPath.appendingPathComponent("GloteraLogs")
        let logFileURL = logsDirectory.appendingPathComponent(fileName)
        
        let fileDestination = FileLogDestination(fileURL: logFileURL, maxFileSize: maxFileSize, maxFiles: maxFiles)
        addDestination(fileDestination)
        
        info("File logging enabled at: \(logFileURL.path)")
        info("Max file size: \(formatFileSize(maxFileSize)), Max files: \(maxFiles)")
    }
    
    /// 配置自定义路径的文件日志输出
    /// - Parameters:
    ///   - filePath: 完整的文件路径
    ///   - maxFileSize: 最大文件大小（字节），默认 10MB
    ///   - maxFiles: 最大文件数量，默认 5 个
    public static func enableFileLoggingAtPath(_ filePath: String, maxFileSize: UInt64 = 10 * 1024 * 1024, maxFiles: Int = 5) {
        let logFileURL = URL(fileURLWithPath: filePath)
        let fileDestination = FileLogDestination(fileURL: logFileURL, maxFileSize: maxFileSize, maxFiles: maxFiles)
        addDestination(fileDestination)
        
        info("File logging enabled at: \(logFileURL.path)")
        info("Max file size: \(formatFileSize(maxFileSize)), Max files: \(maxFiles)")
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
        var config = """
        📊 Logger Configuration:
        - Current Level: \(currentLevel.name) \(currentLevel.emoji)
        - Destinations: \(destinations.count)
        - Date Format: \(dateFormatter.dateFormat ?? "Unknown")
        """
        
        // 添加文件日志信息
        for destination in destinations {
            if let fileDestination = destination as? FileLogDestination {
                config += "\n- File Log: \(fileDestination.getLogFilePath())"
                config += "\n- File Size: \(formatFileSize(fileDestination.getLogFileSize()))"
            }
        }
        
        return config
    }
    
    /// 获取文件日志目标
    public static func getFileDestination() -> FileLogDestination? {
        return destinations.first { $0 is FileLogDestination } as? FileLogDestination
    }
    
    /// 获取日志文件路径
    public static func getLogFilePath() -> String? {
        return getFileDestination()?.getLogFilePath()
    }
    
    /// 获取日志文件大小
    public static func getLogFileSize() -> UInt64 {
        return getFileDestination()?.getLogFileSize() ?? 0
    }
    
    /// 清空日志文件
    public static func clearLogFile() {
        getFileDestination()?.clearLogFile()
        info("Log file cleared")
    }
    
    /// 获取所有日志文件
    public static func getAllLogFiles() -> [URL] {
        return getFileDestination()?.getAllLogFiles() ?? []
    }
    
    /// 打开日志文件所在目录
    public static func openLogsDirectory() {
        guard let fileDestination = getFileDestination() else {
            warn("No file destination configured")
            return
        }
        
        let logsDirectory = URL(fileURLWithPath: fileDestination.getLogFilePath()).deletingLastPathComponent()
        NSWorkspace.shared.open(logsDirectory)
        info("Opened logs directory: \(logsDirectory.path)")
    }
    
    /// 格式化文件大小
    private static func formatFileSize(_ size: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
    
    /// 导出日志到指定文件
    /// - Parameter exportPath: 导出路径
    public static func exportLogs(to exportPath: String) {
        guard let fileDestination = getFileDestination() else {
            warn("No file destination configured")
            return
        }
        
        let exportURL = URL(fileURLWithPath: exportPath)
        let logFiles = fileDestination.getAllLogFiles()
        
        do {
            var combinedContent = ""
            
            for logFile in logFiles.reversed() { // 从最新的开始
                if let content = try? String(contentsOf: logFile, encoding: .utf8) {
                    combinedContent += "=== \(logFile.lastPathComponent) ===\n"
                    combinedContent += content
                    combinedContent += "\n\n"
                }
            }
            
            try combinedContent.write(to: exportURL, atomically: true, encoding: .utf8)
            info("Logs exported to: \(exportPath)")
        } catch let exportError {
            error("Failed to export logs: \(exportError.localizedDescription)")
        }
    }
    
    /// 设置日志级别
    /// - Parameter level: 新的日志级别
    public static func setLogLevel(_ level: LogLevel) {
        currentLevel = level
        info("Log level changed to: \(level.name)")
    }
    
    /// 移除所有日志目标
    public static func removeAllLogDestinations() {
        removeAllDestinations()
        info("All log destinations removed")
    }
    
    /// 移除文件日志目标
    public static func removeFileLogging() {
        destinations.removeAll { $0 is FileLogDestination }
        info("File logging disabled")
    }
} 
