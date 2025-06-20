import Foundation

/// Logger 使用示例
class LoggerExample {
    
    /// 基础使用示例
    static func basicUsageExample() {
        // 基本用法 - 使用默认 info 等级
        Logger.log("Application started successfully")
        
        // 指定日志等级
        Logger.log("Debug information", level: .debug)
        Logger.log("Important information", level: .info)
        Logger.log("Warning message", level: .warn)
        Logger.log("Error occurred", level: .error)
        
        // 使用便捷方法
        Logger.debug("This is debug message with call stack")
        Logger.info("This is info message")
        Logger.warn("This is warning message")
        Logger.error("This is error message")
    }
    
    /// 配置示例
    static func configurationExample() {
        // 设置日志等级 - 只显示 warn 及以上等级的日志
        Logger.currentLevel = .warn
        Logger.info("This info message will not be shown")
        Logger.warn("This warning message will be shown")
        
        // 重置为 debug 等级 - 显示所有日志
        Logger.currentLevel = .debug
        Logger.debug("Now debug messages are visible")
        
        // 查看配置信息
        print(Logger.getConfiguration())
    }
    
    /// 文件日志示例
    static func fileLoggingExample() {
        // 启用文件日志
        Logger.enableFileLogging(fileName: "glotera.log")
        
        Logger.info("This message will be saved to file")
        Logger.error("Error messages are also saved to file")
    }
    
    /// UI 回调示例
    static func uiCallbackExample() {
        // 启用 UI 回调，可用于在 UI 中显示日志
        Logger.enableUICallback { message, level in
            // 这里可以将日志发送到 UI 控件
            DispatchQueue.main.async {
                // 例如：更新 UI 中的日志显示
                print("UI Callback - \(level.name): \(message)")
            }
        }
        
        Logger.info("This message will trigger UI callback")
    }
    
    /// 自定义日志目标示例
    static func customDestinationExample() {
        // 创建自定义日志目标
        class NetworkLogDestination: LogDestination {
            func write(_ message: String, level: LogLevel) {
                // 这里可以实现网络日志发送
                print("📡 Network Log: \(message)")
            }
        }
        
        // 添加自定义目标
        Logger.addDestination(NetworkLogDestination())
        Logger.info("This message will go to all destinations")
    }
    
    /// 在实际函数中的使用示例
    static func simulateTranslationProcess() {
        Logger.info("Starting translation process")
        
        do {
            Logger.debug("Checking input parameters")
            // 模拟一些处理
            Thread.sleep(forTimeInterval: 0.1)
            
            Logger.info("Translation completed successfully")
        } catch {
            Logger.error("Translation failed: \(error.localizedDescription)")
        }
    }
    
    /// 错误处理示例
    static func errorHandlingExample() {
        enum TranslationError: Error, LocalizedError {
            case invalidInput
            case networkFailure
            
            var errorDescription: String? {
                switch self {
                case .invalidInput: return "Invalid input provided"
                case .networkFailure: return "Network connection failed"
                }
            }
        }
        
        func processTranslation() throws {
            Logger.debug("Processing translation request")
            
            // 模拟错误
            throw TranslationError.networkFailure
        }
        
        do {
            try processTranslation()
        } catch {
            Logger.error("Translation error: \(error.localizedDescription)")
        }
    }
    
    /// 测试调用链显示
    static func testCallChain() {
        print("\n🔗 测试调用链显示:")
        
        // 设置显示调用链
        Logger.currentLevel = .debug
        Logger.showDetailedStack = false // 只显示调用链，不显示详细堆栈
        
        // 创建一个调用链: testCallChain -> functionA -> functionB -> functionC
        functionA()
    }
    
    static func functionA() {
        Logger.info("进入 functionA")
        functionB()
    }
    
    static func functionB() {
        Logger.warn("进入 functionB")
        functionC()
    }
    
    static func functionC() {
        Logger.debug("在 functionC 中记录调试信息 - 这里应该显示调用链")
        Logger.error("在 functionC 中记录错误信息")
    }
    
    /// 测试详细堆栈显示
    static func testDetailedStack() {
        print("\n📋 测试详细堆栈显示:")
        
        Logger.showDetailedStack = true // 显示详细堆栈
        Logger.debug("这条消息会显示完整的调用链和详细堆栈")
        Logger.showDetailedStack = false // 恢复默认设置
    }
    
    /// 运行所有测试
    static func runAllTests() {
        print("🧪 开始 Logger 功能测试...")
        print(String(repeating: "=", count: 50))
        
        testBasicLogging()
        testLogLevels()
        testDebugCallStack()
        testCallChain()
        testDetailedStack()
        testFileLogging()
        testConfiguration()
        
        print(String(repeating: "=", count: 50))
        print("✅ Logger 测试完成!")
    }
    
    /// 测试基本日志功能
    static func testBasicLogging() {
        print("\n📝 测试基本日志功能:")
        
        Logger.info("这是一条信息日志")
        Logger.warn("这是一条警告日志")
        Logger.error("这是一条错误日志")
        Logger.debug("这是一条调试日志")
    }
    
    /// 测试日志等级过滤
    static func testLogLevels() {
        print("\n🎚️ 测试日志等级过滤:")
        
        // 设置为 warn 等级
        Logger.currentLevel = .warn
        print("设置日志等级为 WARN，以下 info 和 debug 消息不会显示:")
        
        Logger.debug("这条 debug 消息不会显示")
        Logger.info("这条 info 消息不会显示")
        Logger.warn("这条 warn 消息会显示")
        Logger.error("这条 error 消息会显示")
        
        // 恢复默认等级
        Logger.currentLevel = .info
        print("恢复日志等级为 INFO")
    }
    
    /// 测试调试调用栈
    static func testDebugCallStack() {
        print("\n🐛 测试调试调用栈:")
        
        Logger.currentLevel = .debug
        Logger.debug("这条消息会显示调用栈信息")
    }
    
    /// 测试文件日志
    static func testFileLogging() {
        print("\n📁 测试文件日志:")
        
        // 启用文件日志
        Logger.enableFileLogging()
        Logger.info("这条消息会同时写入控制台和文件")
        Logger.warn("文件日志已启用")
        
        print("文件日志已启用，日志文件位置请查看控制台输出")
    }
    
    /// 测试配置
    static func testConfiguration() {
        print("\n⚙️ 测试配置:")
        
        print("当前日志等级: \(Logger.currentLevel)")
        print("最大调用栈深度: \(Logger.maxStackDepth)")
        print("最大调用链长度: \(Logger.maxCallChainLength)")
        print("显示详细堆栈: \(Logger.showDetailedStack)")
        
        // 测试配置修改
        Logger.maxCallChainLength = 3
        Logger.showDetailedStack = true
        Logger.debug("测试修改配置后的调试输出")
        
        // 恢复默认设置
        Logger.maxCallChainLength = 5
        Logger.showDetailedStack = false
    }
}

// MARK: - 在现有代码中集成 Logger 的示例

extension LoggerExample {
    /// 展示如何在现有的 Glotera 代码中使用 Logger
    static func gloteraPracticalExample() {
        // 替换现有的 print("[LOG] ...") 调用
        
        // 原来的代码：
        // print("[LOG] Space key event detected")
        
        // 新的代码：
        Logger.info("Space key event detected")
        
        // 原来的代码：
        // print("[LOG] ERROR: No focused element found")
        
        // 新的代码：
        Logger.error("No focused element found")
        
        // 原来的代码：
        // print("[LOG] Translation result: \(translated)")
        
        // 新的代码（假设 translated 是变量）:
        let translated = "Hello World"
        Logger.info("Translation result: \(translated)")
        
        // 调试信息：
        Logger.debug("Detailed debugging information with call stack")
        
        // 警告信息：
        Logger.warn("Accessibility permissions may be required")
    }
} 