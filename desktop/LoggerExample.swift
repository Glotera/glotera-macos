import Foundation

/// Logger 使用示例
class LoggerExample {
    
    static func testBasicLogging() {
        print("=== Testing Basic Logging ===")
        
        // 测试不同级别的日志
        Logger.debug("This is a debug message")
        Logger.info("This is an info message")
        Logger.warn("This is a warning message")
        Logger.error("This is an error message")
        
        print("Basic logging test completed\n")
    }
    
    static func testFileLogging() {
        print("=== Testing File Logging ===")
        
        // 启用文件日志
        Logger.enableFileLogging(fileName: "test.log", maxFileSize: 1024 * 1024, maxFiles: 3)
        
        // 写入一些测试日志
        for i in 1...10 {
            Logger.info("Test log message \(i)")
        }
        
        // 显示日志信息
        let config = Logger.getConfiguration()
        print("Logger Configuration:")
        print(config)
        
        // 获取文件信息
        if let logPath = Logger.getLogFilePath() {
            print("Log file path: \(logPath)")
            print("Log file size: \(Logger.getLogFileSize()) bytes")
        }
        
        print("File logging test completed\n")
    }
    
    static func testLogLevels() {
        print("=== Testing Log Levels ===")
        
        // 测试不同日志级别
        Logger.setLogLevel(.debug)
        print("Log level set to DEBUG")
        
        Logger.debug("Debug message - should be visible")
        Logger.info("Info message - should be visible")
        Logger.warn("Warning message - should be visible")
        Logger.error("Error message - should be visible")
        
        Logger.setLogLevel(.warn)
        print("Log level set to WARN")
        
        Logger.debug("Debug message - should NOT be visible")
        Logger.info("Info message - should NOT be visible")
        Logger.warn("Warning message - should be visible")
        Logger.error("Error message - should be visible")
        
        Logger.setLogLevel(.info)
        print("Log level restored to INFO")
        
        print("Log levels test completed\n")
    }
    
    static func testCallStack() {
        print("=== Testing Call Stack ===")
        
        Logger.setLogLevel(.debug)
        
        // 测试调用栈信息
        functionA()
        
        Logger.setLogLevel(.info)
        print("Call stack test completed\n")
    }
    
    static func testFileRotation() {
        print("=== Testing File Rotation ===")
        
        // 启用小文件大小的日志以便测试轮转
        Logger.enableFileLogging(fileName: "rotation_test.log", maxFileSize: 1024, maxFiles: 3)
        
        // 写入大量日志来触发文件轮转
        for i in 1...100 {
            Logger.info("Rotation test message \(i) - " + String(repeating: "A", count: 50))
        }
        
        // 显示所有日志文件
        let logFiles = Logger.getAllLogFiles()
        print("Found \(logFiles.count) log files:")
        for file in logFiles {
            print("  - \(file.lastPathComponent)")
        }
        
        print("File rotation test completed\n")
    }
    
    static func testLogManagement() {
        print("=== Testing Log Management ===")
        
        // 测试日志管理功能
        Logger.info("Testing log management functions")
        
        // 获取日志信息
        let config = Logger.getConfiguration()
        print("Current configuration:")
        print(config)
        
        // 测试清空日志
        Logger.info("This message should be cleared")
        Logger.clearLogFile()
        Logger.info("This message should remain")
        
        print("Log management test completed\n")
    }
    
    // MARK: - Helper Functions
    
    private static func functionA() {
        Logger.debug("Function A called")
        functionB()
    }
    
    private static func functionB() {
        Logger.debug("Function B called")
        functionC()
    }
    
    private static func functionC() {
        Logger.debug("Function C called")
    }
    
    // MARK: - Main Test Function
    
    static func runAllTests() {
        print("🚀 Starting Logger Tests\n")
        
        testBasicLogging()
        testFileLogging()
        testLogLevels()
        testCallStack()
        testFileRotation()
        testLogManagement()
        
        print("✅ All Logger tests completed!")
        print("\n📁 Check the log files in ~/Documents/GloteraLogs/")
    }
} 