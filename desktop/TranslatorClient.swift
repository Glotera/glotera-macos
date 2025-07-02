import Foundation

// MARK: - Quota Information
struct QuotaInfo {
    let isFreeUser: Bool
    let remainingQuota: Int  // -1 for unlimited
    let isQuotaExceeded: Bool
    let isLowQuota: Bool
    let monthlyUsage: Int
    let monthlyLimit: Int?
    
    init(from json: [String: Any]) {
        self.isFreeUser = json["is_free_user"] as? Bool ?? true
        self.remainingQuota = json["remaining_quota"] as? Int ?? 0
        self.isQuotaExceeded = json["is_quota_exceeded"] as? Bool ?? false
        self.isLowQuota = json["is_low_quota"] as? Bool ?? false
        self.monthlyUsage = json["monthly_usage"] as? Int ?? 0
        self.monthlyLimit = json["monthly_limit"] as? Int
    }
    
    var quotaStatusMessage: String? {
        guard isFreeUser else { return nil }
        
        if isQuotaExceeded {
            return "翻译次数已用完，请升级到Pro版本以继续使用"
        } else if isLowQuota {
            return "翻译次数即将用完，剩余 \(remainingQuota) 次，建议升级到Pro版本"
        }
        return nil
    }
    
    var quotaDescription: String {
        if !isFreeUser {
            return "Pro用户 - 无限制翻译"
        } else if isQuotaExceeded {
            return "免费配额已用完 (\(monthlyUsage)/\(monthlyLimit ?? 200))"
        } else {
            return "免费用户 - 本月剩余 \(remainingQuota) 次"
        }
    }
}

// MARK: - Translation Result
struct TranslationResult {
    let translated: String
    let fromLanguage: String?
    let toLanguage: String?
    let quotaInfo: QuotaInfo?
    
    init(from json: [String: Any]) {
        self.translated = json["translated"] as? String ?? ""
        self.fromLanguage = json["from_lang"] as? String
        self.toLanguage = json["to_lang"] as? String
        
        if let quotaData = json["quota_info"] as? [String: Any] {
            self.quotaInfo = QuotaInfo(from: quotaData)
        } else {
            self.quotaInfo = nil
        }
    }
}

// MARK: - Translation Error
enum TranslationError: Error {
    case quotaExceeded(QuotaInfo)
    case networkError(String)
    case parseError(String)
    case serverError(Int, String)
    
    var localizedDescription: String {
        switch self {
        case .quotaExceeded(let quotaInfo):
            return quotaInfo.quotaStatusMessage ?? "翻译配额已用完"
        case .networkError(let message):
            return "网络错误: \(message)"
        case .parseError(let message):
            return "数据解析错误: \(message)"
        case .serverError(let code, let message):
            return "服务器错误 (\(code)): \(message)"
        }
    }
}

// MARK: - Environment Configuration
struct TranslatorEnvironment {
    let apiEndpoint: String
    let isProduction: Bool
    let timeoutInterval: TimeInterval
    let maxRetries: Int
    
    static let current: TranslatorEnvironment = {
        #if DEBUG
            return TranslatorEnvironment(
                apiEndpoint: "http://localhost:1145/api/translate",
                isProduction: false,
                timeoutInterval: 10.0,
                maxRetries: 2
            )
        #else
            return TranslatorEnvironment(
                apiEndpoint: "https://api.glotera.ai/translate", 
                isProduction: true,
                timeoutInterval: 30.0,
                maxRetries: 3
            )
        #endif
    }()
}

// MARK: - Quota Notification Delegate
protocol TranslatorQuotaDelegate: AnyObject {
    func didReceiveQuotaUpdate(_ quotaInfo: QuotaInfo)
    func didReceiveQuotaWarning(_ quotaInfo: QuotaInfo)
    func didReceiveQuotaExceededError(_ quotaInfo: QuotaInfo)
}

class TranslatorClient: NSObject {
    static let shared = TranslatorClient()
    
    // 配额委托
    weak var quotaDelegate: TranslatorQuotaDelegate?
    
    // 使用环境配置
    private let environment = TranslatorEnvironment.current
    private let translationSemaphore = DispatchSemaphore(value: 1)
    
    // 便捷访问属性
    var endpoint: String { environment.apiEndpoint }
    private var timeoutInterval: TimeInterval { environment.timeoutInterval }
    private var isProductionEnvironment: Bool { environment.isProduction }
    
    // 流式请求的会话和回调
    private var streamSession: URLSession?
    private var streamBuffer = ""
    private var streamCallbacks: StreamCallbacks?
    
    private struct StreamCallbacks {
        let onChunk: (String, String) -> Void
        let onComplete: (String?, QuotaInfo?) -> Void
        let onError: (String) -> Void
    }
    
    override init() {
        super.init()
        
        // 启动时输出当前环境配置信息
        Logger.info("TranslatorClient initialized")
        Logger.info("Environment: \(environment.isProduction ? "PRODUCTION" : "DEVELOPMENT")")
        Logger.info("API Endpoint: \(environment.apiEndpoint)")
        Logger.info("Timeout: \(environment.timeoutInterval)s, Max Retries: \(environment.maxRetries)")
        
        #if DEBUG
        Logger.info("🔧 Debug mode: Using local server for fast development")
        #else
        Logger.info("🚀 Release mode: Using production server")
        #endif
    }

    // 翻译文本 - 新方法，返回完整结果包含配额信息
    func translate(text: String, to language: String, completion: @escaping (Result<TranslationResult, TranslationError>) -> Void) {
        Logger.info("Starting translation: \(text) -> \(language)")
        
        // 使用信号量进行同步调用
        translationSemaphore.wait()
        
        Logger.info("Calling translation API")
        
        guard let url = URL(string: endpoint) else {
            Logger.error("Invalid API URL")
            translationSemaphore.signal()
            completion(.failure(.networkError("Invalid API URL")))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add authentication header if user is logged in
        if let authToken = SessionManager.shared.getAuthToken() {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
            Logger.info("Adding authentication header to translation request")
        } else {
            Logger.info("No authentication token - using anonymous mode")
        }
        
        // 构建包含环境信息的新请求体
        let environment = EnvironmentManager.shared.getEnvironmentInfo()
        // Use authenticated user ID if available, otherwise fall back to anonymous ID
        let userId = SessionManager.shared.getCurrentUser()?.userId ?? UserManager.shared.getUserId()
        
        let requestBody: [String: Any] = [
            "text": text,
            "to": language,
            "stream": false,
            "user_id": userId,
            "environment": environment
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
        } catch {
            Logger.error("Failed to serialize request body: \(error)")
            translationSemaphore.signal()
            completion(.failure(.parseError("Failed to serialize request")))
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            // 确保在退出时总是释放信号量
            defer { self.translationSemaphore.signal() }

            if let error = error {
                Logger.info("Translation API error: \(error.localizedDescription)")
                completion(.failure(.networkError(error.localizedDescription)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                Logger.info("Invalid response type")
                completion(.failure(.networkError("Invalid response type")))
                return
            }
            
            guard let data = data else {
                Logger.info("No data received from translation API")
                completion(.failure(.networkError("No data received")))
                return
            }
            
            // 处理HTTP状态码
            if httpResponse.statusCode == 429 {
                // 配额超限错误
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let quotaData = json["quota_info"] as? [String: Any] {
                        let quotaInfo = QuotaInfo(from: quotaData)
                        Logger.info("Quota exceeded for user")
                        
                        // 通知配额委托
                        DispatchQueue.main.async {
                            self.quotaDelegate?.didReceiveQuotaExceededError(quotaInfo)
                            TranslationStatusWindow.shared.hideStatus()
                        }
                        
                        completion(.failure(.quotaExceeded(quotaInfo)))
                        return
                    }
                } catch {
                    Logger.error("Failed to parse quota exceeded response: \(error)")
                }
                completion(.failure(.serverError(429, "Quota exceeded")))
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                Logger.info("Translation API HTTP error: \(httpResponse.statusCode)")
                completion(.failure(.serverError(httpResponse.statusCode, "Server error")))
                return
            }
            
            // 解析成功响应
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    Logger.info("Failed to parse translation response")
                    completion(.failure(.parseError("Invalid JSON response")))
                    return
                }
                
                let result = TranslationResult(from: json)
                
                if result.translated.isEmpty {
                    Logger.info("Empty translation result")
                    completion(.failure(.parseError("Empty translation result")))
                    return
                }
                
                Logger.info("Translation successful: \(result.translated)")
                
                // 处理配额信息通知
                if let quotaInfo = result.quotaInfo {
                    DispatchQueue.main.async {
                        self.quotaDelegate?.didReceiveQuotaUpdate(quotaInfo)
                        
                        // 如果配额较低，发送警告
                        if quotaInfo.isLowQuota {
                            self.quotaDelegate?.didReceiveQuotaWarning(quotaInfo)
                        }
                    }
                    
                    Logger.info("Quota info: \(quotaInfo.quotaDescription)")
                }
                
                completion(.success(result))
            } catch {
                Logger.info("Failed to parse JSON response: \(error)")
                completion(.failure(.parseError("JSON parsing failed")))
            }
        }
        task.resume()
    }
    
    // 便捷方法：只返回翻译文本（向后兼容）
    func translateText(text: String, to language: String, completion: @escaping (Result<String, Error>) -> Void) {
        translate(text: text, to: language) { result in
            switch result {
            case .success(let translationResult):
                completion(.success(translationResult.translated))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func translateStream(
        text: String, 
        to: String, 
        onChunk: @escaping (String, String) -> Void,  // (chunk, fullContent)
        onComplete: @escaping (String?, QuotaInfo?) -> Void,      // (finalResult, quotaInfo)
        onError: @escaping (String) -> Void          // errorMessage
    ) {
        Logger.info("Starting stream translation: text=\(text), to=\(to)")
        
        guard let url = URL(string: endpoint) else { 
            Logger.info("Invalid URL: \(endpoint)")
            DispatchQueue.main.async {
                onError("Invalid server URL")
            }
            return 
        }
        
        // 保存回调
        streamCallbacks = StreamCallbacks(onChunk: onChunk, onComplete: onComplete, onError: onError)
        streamBuffer = ""
        
        // 创建专用的流式会话
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutInterval
        config.timeoutIntervalForResource = timeoutInterval * 2
        
        // 根据环境配置网络参数
        if isProductionEnvironment {
            Logger.info("🌐 Configuring for production environment")
            config.httpMaximumConnectionsPerHost = 1
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            config.urlCache = nil
            config.httpShouldUsePipelining = false
            config.timeoutIntervalForRequest = 60.0  // 生产环境延长超时
        } else {
            Logger.info("🏠 Configuring for development environment")
            config.httpMaximumConnectionsPerHost = 5
            config.requestCachePolicy = .useProtocolCachePolicy
            config.httpShouldUsePipelining = true
            config.timeoutIntervalForRequest = 10.0  // 本地环境快速失败
        }
        
        // 创建高优先级队列来处理流式数据，避免串行阻塞
        let streamQueue = OperationQueue()
        streamQueue.qualityOfService = .userInteractive
        streamQueue.maxConcurrentOperationCount = 1 // 保持数据处理顺序
        streamQueue.name = "StreamProcessingQueue"
        
        streamSession = URLSession(configuration: config, delegate: self, delegateQueue: streamQueue)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeoutInterval
        
        // Add authentication header if user is logged in
        if let authToken = SessionManager.shared.getAuthToken() {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
            Logger.info("Adding authentication header to stream translation request")
        } else {
            Logger.info("No authentication token - using anonymous mode for stream")
        }
        
        // 添加流式相关的请求头
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        
        // Build the request body with environment info
        let environment = EnvironmentManager.shared.getEnvironmentInfo()
        // Use authenticated user ID if available, otherwise fall back to anonymous ID
        let userId = SessionManager.shared.getCurrentUser()?.userId ?? UserManager.shared.getUserId()
        
        let body: [String: Any] = [
            "text": text,
            "to": to,
            "stream": true,
            "user_id": userId,
            "environment": environment
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            Logger.info("Failed to serialize stream request body: \(error)")
            DispatchQueue.main.async {
                onError("Failed to prepare request")
            }
            return
        }
        
        let task = streamSession!.dataTask(with: request)
        task.resume()
        Logger.info("Stream translation request started")
    }
    
    // 便捷方法：流式翻译（向后兼容）
    func translateStreamText(
        text: String,
        to: String,
        onChunk: @escaping (String, String) -> Void,
        onComplete: @escaping (String?) -> Void,
        onError: @escaping (String) -> Void
    ) {
        translateStream(text: text, to: to, onChunk: onChunk) { result, quotaInfo in
            onComplete(result)
        } onError: { error in
            onError(error)
        }
    }
    
    // MARK: - Quota Management
    
    /// 获取用户配额信息（通过发送一个空的测试请求）
    func getUserQuota(completion: @escaping (Result<QuotaInfo, TranslationError>) -> Void) {
        // 使用一个很短的文本进行测试翻译来获取配额信息
        translate(text: ".", to: "en") { result in
            switch result {
            case .success(let translationResult):
                if let quotaInfo = translationResult.quotaInfo {
                    completion(.success(quotaInfo))
                } else {
                    completion(.failure(.parseError("No quota information available")))
                }
            case .failure(let error):
                // 即使配额超限，我们也可以从错误中获取配额信息
                if case .quotaExceeded(let quotaInfo) = error {
                    completion(.success(quotaInfo))
                } else {
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// 检查是否为免费用户
    func isFreeUser() -> Bool {
        let userId = UserManager.shared.getUserId()
        let uuidRegex = try! NSRegularExpression(pattern: "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", options: .caseInsensitive)
        let range = NSRange(location: 0, length: userId.utf16.count)
        return uuidRegex.firstMatch(in: userId, options: [], range: range) != nil || userId == "anonymous" || userId.isEmpty
    }
    
    // 异步处理流式数据，避免阻塞delegate队列
    private func processStreamData(_ dataString: String) {
        // 线程安全地更新缓冲区
        objc_sync_enter(self)
        streamBuffer += dataString
        let lines = streamBuffer.components(separatedBy: .newlines)
        
        if lines.count > 1 {
            streamBuffer = lines.last ?? ""
            let linesToProcess = Array(lines.dropLast())
            objc_sync_exit(self)
            
            // 处理完整的行
            var fullContent = ""
            for line in linesToProcess {
                processStreamLine(line, fullContent: &fullContent)
            }
        } else {
            objc_sync_exit(self)
        }
    }
    
    private func processStreamLine(_ line: String, fullContent: inout String) {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedLine.isEmpty || trimmedLine == "data: [DONE]" {
            Logger.debug("Skipping empty line or DONE marker")
            return
        }
        
        if trimmedLine.hasPrefix("data: ") {
            let jsonString = String(trimmedLine.dropFirst(6))
            
            do {
                guard let jsonData = jsonString.data(using: .utf8),
                      let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                      let type = json["type"] as? String else {
                    Logger.error("Failed to parse stream JSON: \(jsonString)")
                    return
                }
                
                switch type {
                case "connected", "heartbeat":
                    Logger.debug("Received \(type) event")
                    return
                    
                case "chunk":
                    if let content = json["content"] as? String,
                       let fullContentFromResponse = json["fullContent"] as? String {
                        fullContent = fullContentFromResponse
                        Logger.info("Stream chunk: '\(content)'")
                        
                        // 立即回调UI更新
                        DispatchQueue.main.async {
                            self.streamCallbacks?.onChunk(content, fullContentFromResponse)
                        }
                    } else {
                        Logger.error("Missing content or fullContent in chunk event")
                    }
                    
                case "end":
                    Logger.info("Processing end event")
                    let capturedCallbacks = self.streamCallbacks
                    let capturedFullContent = fullContent // 捕获值而非引用
                    
                    // 解析配额信息
                    var quotaInfo: QuotaInfo?
                    if let quotaData = json["quota_info"] as? [String: Any] {
                        quotaInfo = QuotaInfo(from: quotaData)
                        Logger.info("Stream quota info: \(quotaInfo!.quotaDescription)")
                        
                        // 通知配额委托
                        DispatchQueue.main.async {
                            self.quotaDelegate?.didReceiveQuotaUpdate(quotaInfo!)
                            
                            // 如果配额较低，发送警告
                            if quotaInfo!.isLowQuota {
                                self.quotaDelegate?.didReceiveQuotaWarning(quotaInfo!)
                            }
                        }
                    }
                    
                    if let result = json["result"] as? [String: Any],
                       let translated = result["translated"] as? String {
                        DispatchQueue.main.async {
                            capturedCallbacks?.onComplete(translated, quotaInfo)
                        }
                    } else {
                        DispatchQueue.main.async {
                            capturedCallbacks?.onComplete(capturedFullContent.isEmpty ? nil : capturedFullContent, quotaInfo)
                        }
                    }
                    return
                    
                case "error":
                    if let errorMessage = json["error"] as? String {
                        Logger.error("Stream translation error: \(errorMessage)")
                        DispatchQueue.main.async {
                            self.streamCallbacks?.onError(errorMessage)
                        }
                    }
                    return
                    
                default:
                    Logger.error("Unknown stream event type: \(type)")
                }
                
            } catch {
                Logger.error("Failed to parse stream JSON: \(error)")
            }
        }
    }
}

// MARK: - URLSessionDataDelegate
extension TranslatorClient: URLSessionDataDelegate {
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let httpResponse = response as? HTTPURLResponse else {
            Logger.info("Invalid stream response type")
            DispatchQueue.main.async {
                self.streamCallbacks?.onError("Invalid response format")
            }
            completionHandler(.cancel)
            return
        }
        
        if httpResponse.statusCode == 429 {
            Logger.info("Stream translation quota exceeded: \(httpResponse.statusCode)")
            
            // 对于429错误，需要继续接收数据以解析配额信息
            Logger.info("Allowing data reception to parse quota info from 429 response")
            completionHandler(.allow)
            return
        }
        
        guard httpResponse.statusCode == 200 else {
            Logger.info("Stream translation API HTTP error: \(httpResponse.statusCode)")
            DispatchQueue.main.async {
                self.streamCallbacks?.onError("Server error: \(httpResponse.statusCode)")
            }
            completionHandler(.cancel)
            return
        }
        
        Logger.info("Stream response started, status: \(httpResponse.statusCode)")
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let dataString = String(data: data, encoding: .utf8) else {
            Logger.error("Failed to decode stream data")
            return
        }
        
        Logger.info("Received stream data chunk: \(data.count) bytes")
        if isProductionEnvironment {
            Logger.info("Raw data: \(dataString.prefix(200))...") // 只显示前200字符
        }
        
        // 异步处理数据，避免阻塞delegate队列
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            self?.processStreamData(dataString)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { 
        
        if let error = error {
            Logger.error("Stream translation error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.streamCallbacks?.onError("Network error: \(error.localizedDescription)")
            }
        } else {
            // 检查HTTP状态码，特别是429配额耗尽的情况
            if let httpResponse = task.response as? HTTPURLResponse {
                if httpResponse.statusCode == 429 {
                    Logger.info("Processing 429 quota exceeded response with buffer: \(streamBuffer)")
                    
                    // 尝试解析缓冲区中的配额信息
                    if !streamBuffer.isEmpty {
                        do {
                            if let jsonData = streamBuffer.data(using: .utf8),
                               let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                                
                                // 解析配额信息
                                if let quotaData = json["quota_info"] as? [String: Any] {
                                    let quotaInfo = QuotaInfo(from: quotaData)
                                    Logger.info("Parsed quota info from 429 response: \(quotaInfo.quotaDescription)")
                                    
                                    // 通知配额委托配额耗尽
                                    DispatchQueue.main.async {
                                        self.quotaDelegate?.didReceiveQuotaExceededError(quotaInfo)
                                    }
                                } else {
                                    // 如果没有配额信息，创建一个默认的配额耗尽信息
                                    let defaultQuotaJson: [String: Any] = [
                                        "is_free_user": true,
                                        "remaining_quota": 0,
                                        "is_quota_exceeded": true,
                                        "is_low_quota": false,
                                        "monthly_usage": 200,
                                        "monthly_limit": 200
                                    ]
                                    let quotaInfo = QuotaInfo(from: defaultQuotaJson)
                                    Logger.info("Created default quota info for 429 response")
                                    
                                    DispatchQueue.main.async {
                                        self.quotaDelegate?.didReceiveQuotaExceededError(quotaInfo)
                                    }
                                }
                                
                                // 解析错误消息
                                let errorMessage = json["error"] as? String ?? "翻译次数已用完，请升级到Pro版本以继续使用"
                                DispatchQueue.main.async {
                                    self.streamCallbacks?.onError(errorMessage)
                                }
                            } else {
                                // JSON解析失败，使用默认处理
                                Logger.error("Failed to parse 429 response JSON, using default quota info")
                                let defaultQuotaJson: [String: Any] = [
                                    "is_free_user": true,
                                    "remaining_quota": 0,
                                    "is_quota_exceeded": true,
                                    "is_low_quota": false,
                                    "monthly_usage": 200,
                                    "monthly_limit": 200
                                ]
                                let quotaInfo = QuotaInfo(from: defaultQuotaJson)
                                
                                DispatchQueue.main.async {
                                    self.quotaDelegate?.didReceiveQuotaExceededError(quotaInfo)
                                    self.streamCallbacks?.onError("翻译次数已用完，请升级到Pro版本以继续使用")
                                }
                            }
                        } catch {
                            Logger.error("Error parsing 429 response: \(error)")
                            // 解析出错，使用默认处理
                            let defaultQuotaJson: [String: Any] = [
                                "is_free_user": true,
                                "remaining_quota": 0,
                                "is_quota_exceeded": true,
                                "is_low_quota": false,
                                "monthly_usage": 200,
                                "monthly_limit": 200
                            ]
                            let quotaInfo = QuotaInfo(from: defaultQuotaJson)
                            
                            DispatchQueue.main.async {
                                self.quotaDelegate?.didReceiveQuotaExceededError(quotaInfo)
                                self.streamCallbacks?.onError("翻译次数已用完，请升级到Pro版本以继续使用")
                            }
                        }
                    } else {
                        // 缓冲区为空，使用默认处理
                        Logger.info("Empty buffer for 429 response, using default quota info")
                        let defaultQuotaJson: [String: Any] = [
                            "is_free_user": true,
                            "remaining_quota": 0,
                            "is_quota_exceeded": true,
                            "is_low_quota": false,
                            "monthly_usage": 200,
                            "monthly_limit": 200
                        ]
                        let quotaInfo = QuotaInfo(from: defaultQuotaJson)
                        
                        DispatchQueue.main.async {
                            self.quotaDelegate?.didReceiveQuotaExceededError(quotaInfo)
                            self.streamCallbacks?.onError("翻译次数已用完，请升级到Pro版本以继续使用")
                        }
                    }
                    
                    // 清理并返回，不需要继续处理
                    streamSession?.invalidateAndCancel()
                    streamSession = nil
                    streamCallbacks = nil
                    streamBuffer = ""
                    return
                }
            }
            
            // 处理缓冲区中剩余的数据
            if !streamBuffer.isEmpty {
                var fullContent = ""
                processStreamLine(streamBuffer, fullContent: &fullContent)
            }
            Logger.info("Stream translation completed")
        }
         
        // 清理
        streamSession?.invalidateAndCancel()
        streamSession = nil
        streamCallbacks = nil
        streamBuffer = "" 
    }
} 
