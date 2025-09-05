import Foundation
import AppKit

// MARK: - Authentication Optimization

class AuthenticationHelper {
    static let shared = AuthenticationHelper()
    private init() {}
    
    private let authQueue = DispatchQueue(label: "authHelper", attributes: .concurrent)
    private var pendingAuthRequests: [String: [(Bool) -> Void]] = [:]
    
    /// Batch authentication check for translation requests
    func ensureAuthenticated(completion: @escaping (Bool) -> Void) {
        // Fast path: check cached authentication
        if SessionManager.shared.isAuthenticated {
            completion(true)
            return
        }
        
        // Use cached token validation with batching
        SessionManager.shared.validateTokenCached { isValid in
            completion(isValid)
        }
    }
    
    /// Get authenticated request headers (cached)
    func getAuthenticatedHeaders(completion: @escaping ([String: String]?) -> Void) {
        SessionManager.shared.getValidatedAuthToken { token in
            guard let token = token else {
                completion(nil)
                return
            }
            
            let headers = [
                "Content-Type": "application/json",
                "Authorization": "Bearer \(token)"
            ]
            completion(headers)
        }
    }
}

// MARK: - Rate Limiting and Connection Management

class RateLimiter {
    private let maxConcurrentRequests: Int
    private let requestsPerSecond: Double
    private let concurrentQueue = DispatchQueue(label: "rateLimiter", attributes: .concurrent)
    private let semaphore: DispatchSemaphore
    private var lastRequestTime: TimeInterval = 0
    private let minInterval: TimeInterval
    
    init(maxConcurrentRequests: Int, requestsPerSecond: Double) {
        self.maxConcurrentRequests = maxConcurrentRequests
        self.requestsPerSecond = requestsPerSecond
        self.semaphore = DispatchSemaphore(value: maxConcurrentRequests)
        self.minInterval = 1.0 / requestsPerSecond
    }
    
    func execute(_ block: @escaping () -> Void) {
        concurrentQueue.async {
            self.semaphore.wait()
            
            // Rate limiting: ensure minimum interval between requests
            let now = Date().timeIntervalSince1970
            let timeSinceLastRequest = now - self.lastRequestTime
            
            if timeSinceLastRequest < self.minInterval {
                let delay = self.minInterval - timeSinceLastRequest
                Thread.sleep(forTimeInterval: delay)
            }
            
            self.lastRequestTime = Date().timeIntervalSince1970
            
            // Execute the actual request
            block()
            
            // Release the semaphore when done
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.1) {
                self.semaphore.signal()
            }
        }
    }
}

class ConnectionPool {
    private let maxConnections: Int
    private var sessions: [URLSession] = []
    private let sessionQueue = DispatchQueue(label: "connectionPool", attributes: .concurrent)
    private var currentIndex = 0
    
    init(maxConnections: Int) {
        self.maxConnections = maxConnections
        createSessions()
    }
    
    private func createSessions() {
        for _ in 0..<maxConnections {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30.0
            config.timeoutIntervalForResource = 60.0
            config.httpMaximumConnectionsPerHost = 2
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            
            let session = URLSession(configuration: config)
            sessions.append(session)
        }
    }
    
    func getSession() -> URLSession {
        return sessionQueue.sync {
            let session = sessions[currentIndex]
            currentIndex = (currentIndex + 1) % maxConnections
            return session
        }
    }
}

// MARK: - Quota Information
struct QuotaInfo {
    let isFreeUser: Bool
    let userType: String
    let remainingQuota: Int  // -1 for unlimited
    let isQuotaExceeded: Bool
    let isLowQuota: Bool
    let monthlyUsage: Int
    let monthlyLimit: Int?
    
    init(from json: [String: Any]) {
        self.isFreeUser = json["is_free_user"] as? Bool ?? true
        self.userType = json["user_type"] as? String ?? "free"
        self.remainingQuota = json["remaining_quota"] as? Int ?? 0
        self.isQuotaExceeded = json["is_quota_exceeded"] as? Bool ?? false
        self.isLowQuota = json["is_low_quota"] as? Bool ?? false
        self.monthlyUsage = json["monthly_usage"] as? Int ?? 0
        self.monthlyLimit = json["monthly_limit"] as? Int
    }
    
    var quotaStatusMessage: String? {
        if isFreeUser {
            if isQuotaExceeded {
                return "Translation quota exhausted. Please upgrade to Pro (\(QuotaLimits.PRO_MONTHLY_LIMIT)/month) or Max (unlimited) to continue"
            } else if isLowQuota {
                return "Translation quota running low. \(remainingQuota) remaining. Consider upgrading to Pro (\(QuotaLimits.PRO_MONTHLY_LIMIT)/month) or Max (unlimited)"
            }
        } else {
            // Pro users with quota limits
            if remainingQuota != QuotaLimits.MAX_MONTHLY_LIMIT { // Not unlimited
                if isQuotaExceeded {
                    return "Pro quota exhausted. Please upgrade to Max for unlimited translations"
                } else if isLowQuota {
                    return "Pro quota running low. \(remainingQuota) remaining. Consider upgrading to Max"
                }
            }
        }
        return nil
    }
    
    var quotaDescription: String {
        if !isFreeUser {
            // Check if it's Max user or Pro user based on remaining quota
            if remainingQuota == QuotaLimits.MAX_MONTHLY_LIMIT {
                return "Max - Unlimited"
            } else {
                return "Pro - \(remainingQuota) / \(monthlyLimit ?? QuotaLimits.PRO_MONTHLY_LIMIT)"
            }
        } else {
            return "Free - \(remainingQuota)/\(monthlyLimit ?? QuotaLimits.FREE_MONTHLY_LIMIT)"
        }
    }
    
    var isUnlimitedUser: Bool{
        return "max" == userType.lowercased()
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
    case authenticationRequired(String)
    
    var localizedDescription: String {
        switch self {
        case .quotaExceeded(let quotaInfo):
            return quotaInfo.quotaStatusMessage ?? "Translation quota exceeded"
        case .networkError(let message):
            return "Network error: \(message)"
        case .parseError(let message):
            return "Data parsing error: \(message)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .authenticationRequired(let message):
            return "Login required: \(message)"
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
        let translateURL = EnvironmentManager.shared.translateURL
        #if DEBUG
            return TranslatorEnvironment(
                apiEndpoint: translateURL,
                isProduction: false,
                timeoutInterval: 30.0,
                maxRetries: 2
            )
        #else
            return TranslatorEnvironment(
                apiEndpoint: translateURL, 
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
    
    // Track last known quota info for client-side validation
    private var lastKnownQuotaInfo: QuotaInfo?
    private let quotaCacheQueue = DispatchQueue(label: "quotaCache", attributes: .concurrent)
    
    // Track recent quota dialog to prevent duplicates within same request
    private var recentQuotaDialogTime: Date?
    
    // 错误通知管理器
    private let errorNotificationManager = ErrorNotificationManager.shared
    
    // 使用环境配置
    private let environment = TranslatorEnvironment.current
    
    // Rate limiting and connection management
    private let rateLimiter = RateLimiter(maxConcurrentRequests: 3, requestsPerSecond: 5)
    private let connectionPool = ConnectionPool(maxConnections: 5)
    private let translationQueue = OperationQueue()
    
    // 便捷访问属性
    var endpoint: String { environment.apiEndpoint }
    private var timeoutInterval: TimeInterval { environment.timeoutInterval }
    private var isProductionEnvironment: Bool { environment.isProduction }
    
    // 流式请求的会话和回调
    private var streamSession: URLSession?
    private var streamBuffer = ""
    private var streamCallbacks: StreamCallbacks?
    private var streamProcessor: StreamBatchProcessor?
    
    private struct StreamCallbacks {
        let onChunk: (String, String) -> Void
        let onComplete: (String?, QuotaInfo?) -> Void
        let onError: (String) -> Void
    }
    
    override init() {
        super.init()
        
        // Configure translation queue for optimal performance
        translationQueue.maxConcurrentOperationCount = 3
        translationQueue.qualityOfService = .userInitiated
        translationQueue.name = "TranslationQueue"
        
        // 启动时输出当前环境配置信息
        Logger.debug("TranslatorClient initialized with rate limiting")
        Logger.debug("Environment: \(environment.isProduction ? "PRODUCTION" : "DEVELOPMENT")")
        Logger.debug("API Endpoint: \(environment.apiEndpoint)")
        Logger.debug("Timeout: \(environment.timeoutInterval)s, Max Retries: \(environment.maxRetries)")
        Logger.debug("Rate Limiting: 3 concurrent, 5 req/sec")
        
        #if DEBUG
        Logger.info("🔧 Debug mode: Using local server for fast development")
        #else
        Logger.info("🚀 Release mode: Using production server")
        #endif
        
        // 监听重试通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRetryNotification),
            name: .retryTranslation,
            object: nil
        )
    }

    // 翻译文本 - 新方法，返回完整结果包含配额信息
    func translate(text: String, to language: String, mousePoint: CGPoint? = nil, completion: @escaping (Result<TranslationResult, TranslationError>) -> Void) {
        // Validate input text is not empty
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty {
            Logger.error("Translation attempted with empty text, ignoring API call")
            recordPerformanceCounter("translation.empty_text_rejected")
            completion(.failure(.parseError("Empty text cannot be translated")))
            return
        }
        
        Logger.debug("Starting translation: \(text) -> \(language)")
        
        // Record translation attempt
        recordPerformanceCounter("translation.attempt")
        recordPerformanceCounter("translation.text_length", value: Double(trimmedText.count))
        
        let timer = PerformanceTelemetry.shared.startTiming("translation.total")
        timer.addContext("text_length", trimmedText.count)
        timer.addContext("target_language", language)
        
        // Use rate limiter instead of blocking semaphore
        rateLimiter.execute {
            self.performTranslation(text: text, to: language) { result in
                switch result {
                case .success(let translationResult):
                    timer.addContext("result_length", translationResult.translated.count)
                    timer.finish(success: true)
                    recordPerformanceCounter("translation.success")
                case .failure(let error):
                    timer.addContext("error_type", String(describing: error))
                    timer.finish(success: false)
                    recordPerformanceCounter("translation.failure")
                    
                    // 显示用户友好的错误提醒
                    self.handleTranslationError(error)
                    
                    // 同时更新状态窗口
                    self.updateStatusWindowForError(error, near: mousePoint)
                }
                completion(result)
            }
        }
    }
    
    // Actual translation implementation
    private func performTranslation(text: String, to language: String, completion: @escaping (Result<TranslationResult, TranslationError>) -> Void) {
        // Client-side quota validation with server verification before making API call
        validateQuotaBeforeTranslation { [weak self] quotaError in
            if let quotaError = quotaError {
                Logger.info("Translation blocked by quota validation (cache + server verified)")
                completion(.failure(quotaError))
                return
            }
            
            // Quota validation passed, proceed with translation
            self?.performActualTranslation(text: text, to: language, completion: completion)
        }
    }
    
    // Separated actual translation logic to be called after quota validation
    private func performActualTranslation(text: String, to language: String, completion: @escaping (Result<TranslationResult, TranslationError>) -> Void) {
        
        // Record start time for API call timing
        let startTime = CFAbsoluteTimeGetCurrent()
        Logger.info("🚀 Starting translation API call to \(endpoint)")
        
        guard let url = URL(string: endpoint) else {
            Logger.error("Invalid API URL")
            completion(.failure(.networkError("Invalid API URL")))
            return
        }
        
        // Use cached authentication helper
        AuthenticationHelper.shared.getAuthenticatedHeaders { [weak self] headers in
            guard let self = self, let headers = headers else {
                Logger.error("No valid authentication headers available - translation requires login")
                completion(.failure(.authenticationRequired("Authentication required")))
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            
            // Set headers from authentication helper
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
            
            Logger.debug("Adding cached authentication header to translation request")
            
            // 构建包含环境信息的新请求体
            let environment = EnvironmentManager.shared.getEnvironmentInfo()
            // Use authenticated user ID (guaranteed to exist due to authentication check above)
            guard let userId = SessionManager.shared.getCurrentUser()?.userId else {
                Logger.error("No authenticated user available")
                completion(.failure(.authenticationRequired("No authenticated user")))
                return
            }
        
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
            completion(.failure(.parseError("Failed to serialize request")))
            return
        }
        
        // Use connection pool for better performance
        let session = connectionPool.getSession()
        let task = session.dataTask(with: request) { data, response, error in
            // Calculate API call duration
            let endTime = CFAbsoluteTimeGetCurrent()
            let duration = endTime - startTime

            if let error = error {
                Logger.info("❌ Translation API error after \(String(format: "%.3f", duration * 1000))ms: \(error.localizedDescription)")
                completion(.failure(.networkError(error.localizedDescription)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                Logger.info("❌ Invalid response type after \(String(format: "%.3f", duration * 1000))ms")
                completion(.failure(.networkError("Invalid response type")))
                return
            }
            
            guard let data = data else {
                Logger.info("❌ No data received from translation API after \(String(format: "%.3f", duration * 1000))ms")
                completion(.failure(.networkError("No data received")))
                return
            }
            
            // 处理HTTP状态码
            if httpResponse.statusCode == 429 {
                // 配额超限错误
                Logger.warn("⚠️ Quota exceeded after \(String(format: "%.3f", duration * 1000))ms")
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let quotaData = json["quota_info"] as? [String: Any] {
                        let quotaInfo = QuotaInfo(from: quotaData)
                        Logger.warn("Quota exceeded for user")
                        
                        // Update cached quota info for client-side validation
                        self.updateCachedQuotaInfo(quotaInfo)
                        
                        // 通知配额委托 (only if we haven't shown dialog recently)
                        let shouldShowDialog: Bool
                        if let lastDialogTime = self.recentQuotaDialogTime {
                            shouldShowDialog = Date().timeIntervalSince(lastDialogTime) > 3.0
                        } else {
                            shouldShowDialog = true
                        }
                        
                        DispatchQueue.main.async {
                            if shouldShowDialog {
                                self.quotaDelegate?.didReceiveQuotaExceededError(quotaInfo)
                                self.recentQuotaDialogTime = Date()
                            } else {
                                Logger.info("Quota dialog recently shown, skipping duplicate from API response")
                            }
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
                Logger.info("❌ Translation API HTTP error \(httpResponse.statusCode) after \(String(format: "%.3f", duration * 1000))ms")
                completion(.failure(.serverError(httpResponse.statusCode, "Server error")))
                return
            }
            
            // 解析成功响应
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    Logger.info("❌ Failed to parse translation response after \(String(format: "%.3f", duration * 1000))ms")
                    completion(.failure(.parseError("Invalid JSON response")))
                    return
                }
                
                let result = TranslationResult(from: json)
                
                if result.translated.isEmpty {
                    Logger.info("❌ Empty translation result after \(String(format: "%.3f", duration * 1000))ms")
                    completion(.failure(.parseError("Empty translation result")))
                    return
                }
                
                Logger.info("✅ Translation successful after \(String(format: "%.3f", duration * 1000))ms: \(result.translated)")
                
                // 处理配额信息通知
                if let quotaInfo = result.quotaInfo {
                    // Update cached quota info for client-side validation
                    self.updateCachedQuotaInfo(quotaInfo)
                    
                    DispatchQueue.main.async {
                        self.quotaDelegate?.didReceiveQuotaUpdate(quotaInfo)
                        
                        // 如果配额较低，发送警告
                        if quotaInfo.isLowQuota {
                            self.quotaDelegate?.didReceiveQuotaWarning(quotaInfo)
                        }
                    }
                    
                    Logger.debug("Quota info: \(quotaInfo.quotaDescription)")
                }
                
                completion(.success(result))
            } catch {
                Logger.info("❌ Failed to parse JSON response after \(String(format: "%.3f", duration * 1000))ms: \(error)")
                completion(.failure(.parseError("JSON parsing failed")))
            }
        }
        task.resume()
        }  // Close authentication callback
    }
    
    // 便捷方法：只返回翻译文本（向后兼容）
    func translateText(text: String, to language: String, completion: @escaping (Result<String, Error>) -> Void) {
        // Empty text validation is handled by the main translate method
        translate(text: text, to: language) { result in
            switch result {
            case .success(let translationResult):
                completion(.success(translationResult.translated))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // 向后兼容的translate方法（不带mousePoint）
    func translate(text: String, to language: String, completion: @escaping (Result<TranslationResult, TranslationError>) -> Void) {
        translate(text: text, to: language, mousePoint: nil, completion: completion)
    }
    
    func translateStream(
        text: String, 
        to: String,
        mousePoint: CGPoint? = nil,
        onChunk: @escaping (String, String) -> Void,  // (chunk, fullContent)
        onComplete: @escaping (String?, QuotaInfo?) -> Void,      // (finalResult, quotaInfo)
        onError: @escaping (String) -> Void          // errorMessage
    ) {
        // Validate input text is not empty
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty {
            Logger.error("Stream translation attempted with empty text, ignoring API call")
            recordPerformanceCounter("translation.stream.empty_text_rejected")
            DispatchQueue.main.async {
                onError("Empty text cannot be translated")
            }
            return
        }
        
        // Client-side quota validation with server verification before making API call
        validateQuotaBeforeTranslation { [weak self] quotaError in
            if let quotaError = quotaError {
                Logger.info("Stream translation blocked by quota validation (cache + server verified)")
                
                // Show immediate status feedback
                DispatchQueue.main.async {
                    TranslationStatusWindow.shared.showFailure()
                }
                
                DispatchQueue.main.async {
                    if case .quotaExceeded(let quotaInfo) = quotaError {
                        onError(quotaInfo.quotaStatusMessage ?? "Translation quota exceeded - please upgrade")
                    } else {
                        onError("Translation quota exceeded - please upgrade")
                    }
                }
                return
            }
            
            // Quota validation passed, proceed with stream translation
            self?.performActualStreamTranslation(text: text, to: to, mousePoint: mousePoint, onChunk: onChunk, onComplete: onComplete, onError: onError)
        }
    }
    
    // Separated actual stream translation logic to be called after quota validation
    private func performActualStreamTranslation(
        text: String, 
        to: String,
        mousePoint: CGPoint?,
        onChunk: @escaping (String, String) -> Void,
        onComplete: @escaping (String?, QuotaInfo?) -> Void,
        onError: @escaping (String) -> Void
    ) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        Logger.info("Starting stream translation: text=\(text), to=\(to)")
        
        // Record stream translation attempt
        recordPerformanceCounter("translation.stream.attempt")
        recordPerformanceCounter("translation.stream.text_length", value: Double(trimmedText.count))
        
        let timer = PerformanceTelemetry.shared.startTiming("translation.stream.total")
        timer.addContext("text_length", trimmedText.count)
        timer.addContext("target_language", to)
        
        // Check authentication first using cached validation
        AuthenticationHelper.shared.ensureAuthenticated { isAuthenticated in
            guard isAuthenticated else {
                Logger.warn("Stream translation attempted without authentication - requiring login")
                timer.finish(success: false)
                recordPerformanceCounter("translation.stream.auth_failure")
                DispatchQueue.main.async {
                    onError("Authentication required - please sign in to use translation features")
                }
                return
            }
            
            self.performStreamTranslation(text: text, to: to, 
                onChunk: onChunk, 
                onComplete: { result, quotaInfo in
                    timer.finish(success: true)
                    recordPerformanceCounter("translation.stream.success")
                    onComplete(result, quotaInfo)
                }, 
                onError: { error in
                    timer.finish(success: false)
                    recordPerformanceCounter("translation.stream.failure")
                    
                    // Handle stream translation errors, create corresponding TranslationError
                    let translationError: TranslationError
                    if error.contains("Network") || error.contains("network") {
                        translationError = .networkError(error)
                    } else if error.contains("Server") || error.contains("server") {
                        translationError = .serverError(500, error)
                    } else if error.contains("Authentication") || error.contains("authentication") {
                        translationError = .authenticationRequired(error)
                    } else {
                        translationError = .parseError(error)
                    }
                    
                    // Show friendly error reminders
                    self.handleTranslationError(translationError)
                    
                    onError(error)
                })
        }
    }
    
    private func performStreamTranslation(
        text: String,
        to: String,
        onChunk: @escaping (String, String) -> Void,
        onComplete: @escaping (String?, QuotaInfo?) -> Void,
        onError: @escaping (String) -> Void
    ) {
        // Record start time for stream translation API call timing
        let startTime = CFAbsoluteTimeGetCurrent()
        Logger.info("🚀 Starting stream translation API call at \(Date())")
        
        guard let url = URL(string: endpoint) else { 
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            Logger.info("❌ Invalid URL after \(String(format: "%.3f", duration * 1000))ms: \(endpoint)")
            DispatchQueue.main.async {
                onError("Invalid server URL")
            }
            return 
        }
        
        // 保存回调
        streamCallbacks = StreamCallbacks(onChunk: onChunk, onComplete: onComplete, onError: onError)
        streamBuffer = ""
        
        // Initialize stream processor with callbacks
        streamProcessor = StreamBatchProcessor()
        streamProcessor?.setCallbacks(
            StreamProcessorCallbacks(
                onChunk: onChunk,
                onComplete: onComplete,
                onError: onError
            ),
            quotaDelegate: quotaDelegate
        )
        
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
        
        // Add authentication header using cached token
        guard let authToken = SessionManager.shared.getAuthToken() else {
            Logger.error("No authentication token available - stream translation requires login")
            DispatchQueue.main.async {
                onError("Authentication required")
            }
            return
        }
        
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        Logger.debug("Adding cached authentication header to stream translation request")
        
        // 添加流式相关的请求头
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        
        // Build the request body with environment info
        let environment = EnvironmentManager.shared.getEnvironmentInfo()
        // Use authenticated user ID (guaranteed to exist due to authentication check above)
        guard let userId = SessionManager.shared.getCurrentUser()?.userId else {
            Logger.error("No authenticated user available for stream translation")
            DispatchQueue.main.async {
                onError("Authentication required")
            }
            return
        }
        
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
        Logger.info("📡 Stream translation request started - waiting for response...")
        
        // Store startTime in the task for later reference in delegate methods
        // We'll use objc_setAssociatedObject to attach timing info to the task
        objc_setAssociatedObject(task, "streamStartTime", startTime, .OBJC_ASSOCIATION_RETAIN)
    }
    
    // 便捷方法：流式翻译（向后兼容）
    func translateStreamText(
        text: String,
        to: String,
        onChunk: @escaping (String, String) -> Void,
        onComplete: @escaping (String?) -> Void,
        onError: @escaping (String) -> Void
    ) {
        // Empty text validation is handled by the main translateStream method
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
    
    // MARK: - Error Handling
    
    /// Handle translation errors and show user-friendly reminders
    private func handleTranslationError(_ error: TranslationError) {
        Logger.debug("Handling translation error: \(error.localizedDescription)")
        
        // For authentication and quota errors, let existing handling mechanisms handle them
        switch error {
        case .authenticationRequired:
            // Authentication errors are handled by LoginManager and UserManager
            return
        case .quotaExceeded(let quotaInfo):
            // Quota errors are handled by QuotaAlertWindow, but also show immediate feedback
            DispatchQueue.main.async {
                // Note: Don't call quotaDelegate here as it may have already been called during validation
                // The QuotaAlertWindow has cooldown logic to prevent duplicate dialogs
                
                // Show brief status message for immediate user feedback
                TranslationStatusWindow.shared.showFailure()
            }
            return
        case .networkError, .serverError, .parseError:
            // Network and server errors show friendly reminders
            DispatchQueue.main.async {
                self.errorNotificationManager.showErrorNotification(error)
            }
        }
    }
    
    /// Update status window to display error status
    private func updateStatusWindowForError(_ error: TranslationError, near mousePoint: CGPoint?) {
        guard let point = mousePoint else { return }
        
        DispatchQueue.main.async {
            switch error {
            case .networkError:
                TranslationStatusWindow.shared.showNetworkError(near: point)
            case .serverError:
                TranslationStatusWindow.shared.showServerError(near: point)
            default:
                TranslationStatusWindow.shared.showFailure()
            }
        }
    }
    
    /// Handle retry notification
    @objc private func handleRetryNotification() {
        Logger.info("Translation retry requested by user")
        // Retry mechanism can be implemented here, such as re-initiating the last failed translation request
        // Currently just logging the user's retry intent
    }
    
    // MARK: - Chat Functionality
    
    /// Chat with LLM using the /chat endpoint with streaming and markdown support
    func chat(
        message: String,
        originalText: String,
        translatedText: String,
        conversationHistory: [(userMessage: String, aiResponse: String)],
        onStreamUpdate: @escaping (String) -> Void,
        completion: @escaping (Result<String, TranslationError>) -> Void
    ) {
        Logger.debug("Starting chat: message=\(message)")
        
        // Client-side quota validation with server verification before making API call
        validateQuotaBeforeTranslation { [weak self] quotaError in
            if let quotaError = quotaError {
                Logger.info("Chat blocked by quota validation (cache + server verified)")
                completion(.failure(quotaError))
                return
            }
            
            // Quota validation passed, proceed with chat
            self?.performActualChat(message: message, originalText: originalText, translatedText: translatedText, conversationHistory: conversationHistory, onStreamUpdate: onStreamUpdate, completion: completion)
        }
    }
    
    // Separated actual chat logic to be called after quota validation
    private func performActualChat(
        message: String,
        originalText: String,
        translatedText: String,
        conversationHistory: [(userMessage: String, aiResponse: String)],
        onStreamUpdate: @escaping (String) -> Void,
        completion: @escaping (Result<String, TranslationError>) -> Void
    ) {
        
        // Create chat endpoint URL
        let chatEndpoint = EnvironmentManager.shared.chatURL 
        
        guard let url = URL(string: chatEndpoint) else {
            Logger.error("Invalid chat URL: \(chatEndpoint)")
            completion(.failure(.networkError("Invalid chat URL")))
            return
        }
        
        // Get authenticated headers
        AuthenticationHelper.shared.getAuthenticatedHeaders { [weak self] headers in
            guard let self = self, let headers = headers else {
                Logger.error("No valid authentication headers available for chat")
                completion(.failure(.authenticationRequired("Authentication required")))
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            
            // Set headers
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
            request.timeoutInterval = self.timeoutInterval
            
            // Build request body (simplified, no environment info)
            guard let userId = SessionManager.shared.getCurrentUser()?.userId else {
                Logger.error("No authenticated user available for chat")
                completion(.failure(.authenticationRequired("No authenticated user")))
                return
            }
            
            // Build conversation history for context
            var conversationPairs: [[String: String]] = []
            for (userMsg, aiResp) in conversationHistory {
                conversationPairs.append([
                    "user_message": userMsg,
                    "ai_response": aiResp
                ])
            }
            
            let requestBody: [String: Any] = [
                "message": message,
                "original_text": originalText,
                "translated_text": translatedText,
                "conversation_history": conversationPairs,
                "user_id": userId
            ]
            
            // Log the complete request for debugging
            do {
                let requestJsonData = try JSONSerialization.data(withJSONObject: requestBody, options: .prettyPrinted)
                if let requestJsonString = String(data: requestJsonData, encoding: .utf8) {
                    // Simplified chat API request log
                    Logger.debug("Chat API Request: POST \(chatEndpoint)")
                }
            } catch {
                Logger.error("Failed to serialize request body for logging: \(error)")
            }
            
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
            } catch {
                Logger.error("Failed to serialize chat request body: \(error)")
                completion(.failure(.parseError("Failed to serialize request")))
                return
            }
            
            // Create streaming delegate for real-time data processing
            let streamingDelegate = ChatStreamingDelegate(
                onStreamUpdate: onStreamUpdate,
                onCompletion: completion
            )
            
            // Create custom URLSession with streaming delegate
            let streamingSession = URLSession(
                configuration: .default,
                delegate: streamingDelegate,
                delegateQueue: nil
            ) 
            
            let streamingTask = streamingSession.dataTask(with: request)
            streamingDelegate.task = streamingTask
            streamingTask.resume()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Quota Cache Management
    
    private func updateCachedQuotaInfo(_ quotaInfo: QuotaInfo) {
        quotaCacheQueue.async(flags: .barrier) {
            self.lastKnownQuotaInfo = quotaInfo
            Logger.debug("Updated cached quota info: \(quotaInfo.quotaDescription)")
        }
    }
    
    private func getCachedQuotaInfo() -> QuotaInfo? {
        return quotaCacheQueue.sync {
            return lastKnownQuotaInfo
        }
    }
    
    private func validateQuotaBeforeTranslation(completion: @escaping (TranslationError?) -> Void) {
        guard let cachedQuota = getCachedQuotaInfo() else {
            // No cached quota info, allow translation (server will handle quota validation)
            Logger.debug("No cached quota info, allowing translation")
            completion(nil)
            return
        }
        
        // Check if cached quota shows exhaustion
        // Quota is exhausted if: server explicitly says so OR (remaining is 0 AND user is not Max/unlimited)
        let cachedQuotaExhausted = cachedQuota.isQuotaExceeded || 
        (cachedQuota.remainingQuota == 0 && !cachedQuota.isUnlimitedUser)
        
        if cachedQuotaExhausted {
            Logger.info("Cached quota shows exhaustion (remaining: \(cachedQuota.remainingQuota)), verifying with server...")
            
            // Double-check with server to ensure quota is actually exhausted
            self.fetchQuotaInfo { [weak self] result in
                switch result {
                case .success(let serverQuota):
                    // Update cache with fresh server data
                    self?.updateCachedQuotaInfo(serverQuota)
                    
                    let serverQuotaExhausted = serverQuota.isQuotaExceeded || 
                    (serverQuota.remainingQuota == 0 && !serverQuota.isUnlimitedUser)
                    
                    if serverQuotaExhausted {
                        Logger.info("Server confirmed quota exhaustion (remaining: \(serverQuota.remainingQuota))")
                        
                        // Trigger quota exceeded dialog and mark recent dialog time
                        DispatchQueue.main.async {
                            self?.quotaDelegate?.didReceiveQuotaExceededError(serverQuota)
                        }
                        self?.recentQuotaDialogTime = Date()
                        
                        completion(.quotaExceeded(serverQuota))
                    } else {
                        Logger.info("Server shows quota available (remaining: \(serverQuota.remainingQuota)), cached data was stale")
                        completion(nil)
                    }
                    
                case .failure(let error):
                    Logger.warn("Failed to verify quota with server: \(error), using cached data as fallback")
                    
                    // If server check fails, use cached data as fallback
                    DispatchQueue.main.async {
                        self?.quotaDelegate?.didReceiveQuotaExceededError(cachedQuota)
                    }
                    self?.recentQuotaDialogTime = Date()
                    
                    completion(.quotaExceeded(cachedQuota))
                }
            }
        } else {
            Logger.debug("Client-side quota validation passed (remaining: \(cachedQuota.remainingQuota))")
            completion(nil)
        }
    }
}

// MARK: - Chat Streaming Delegate
class ChatStreamingDelegate: NSObject, URLSessionDataDelegate {
    private let onStreamUpdate: (String) -> Void
    private let onCompletion: (Result<String, TranslationError>) -> Void
    private var completeResponse = ""
    private var buffer = ""
    
    weak var task: URLSessionDataTask?
    
    init(onStreamUpdate: @escaping (String) -> Void, onCompletion: @escaping (Result<String, TranslationError>) -> Void) {
        self.onStreamUpdate = onStreamUpdate
        self.onCompletion = onCompletion
        super.init()
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let httpResponse = response as? HTTPURLResponse else {
            DispatchQueue.main.async {
                self.onCompletion(.failure(.networkError("Invalid response type")))
            }
            completionHandler(.cancel)
            return
        }
        
        
        if httpResponse.statusCode == 401 {
            DispatchQueue.main.async {
                self.onCompletion(.failure(.authenticationRequired("Authentication required")))
            }
            completionHandler(.cancel)
            return
        }
        
        if httpResponse.statusCode == 429 {
            DispatchQueue.main.async {
                self.onCompletion(.failure(.serverError(429, "Chat quota exceeded")))
            }
            completionHandler(.cancel)
            return
        }
        
        guard httpResponse.statusCode == 200 else {
            DispatchQueue.main.async {
                self.onCompletion(.failure(.serverError(httpResponse.statusCode, "Server error")))
            }
            completionHandler(.cancel)
            return
        }
        
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let responseString = String(data: data, encoding: .utf8) else {
            return
        } 
        
        // Add to buffer for processing
        buffer += responseString
        
        // Process complete lines
        let lines = buffer.components(separatedBy: .newlines)
        
        // Keep the last incomplete line in buffer
        if lines.count > 1 {
            buffer = lines.last ?? ""
            
            // Process complete lines
            for line in lines.dropLast() {
                processStreamLine(line)
            }
        }
    }
    
    private func processStreamLine(_ line: String) {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedLine.isEmpty {
            return
        }
        
        if trimmedLine == "data: [DONE]" {
            DispatchQueue.main.async {
                self.onCompletion(.success(self.completeResponse))
            }
            return
        }
        
        if trimmedLine.hasPrefix("data: ") {
            let jsonString = String(trimmedLine.dropFirst(6))
            
            if let jsonData = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                
                // Check for completion signal first
                if let type = json["type"] as? String {
                    switch type {
                    case "end", "complete", "done":
                        DispatchQueue.main.async {
                            self.onCompletion(.success(self.completeResponse))
                        }
                        return
                    case "error":
                        if let errorMessage = json["error"] as? String {
                            DispatchQueue.main.async {
                                self.onCompletion(.failure(.serverError(500, errorMessage)))
                            }
                        }
                        return
                    case "chunk":
                        // Handle structured chunk with type
                        if let content = json["content"] as? String {
                            completeResponse += content
                            DispatchQueue.main.async {
                                self.onStreamUpdate(self.completeResponse)
                            }
                        }
                        return
                    default:
                        break
                    }
                }
                
                // For chat streaming, we expect content in the response
                if let content = json["content"] as? String {
                    completeResponse += content
                    DispatchQueue.main.async {
                        self.onStreamUpdate(self.completeResponse)
                    }
                } else if let delta = json["delta"] as? [String: Any],
                          let content = delta["content"] as? String {
                    // Handle OpenAI-style delta format
                    completeResponse += content
                    DispatchQueue.main.async {
                        self.onStreamUpdate(self.completeResponse)
                    }
                }
            }
        }
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didCompleteWithError error: Error?) {
        // Process any remaining buffer content
        if !buffer.isEmpty {
            processStreamLine(buffer)
        }
        
        if let error = error {
            DispatchQueue.main.async {
                self.onCompletion(.failure(.networkError(error.localizedDescription)))
            }
        } else {
            DispatchQueue.main.async {
                self.onCompletion(.success(self.completeResponse))
            }
        }
    }
}

// MARK: - URLSessionDataDelegate
extension TranslatorClient: URLSessionDataDelegate {
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // Get timing info if available
        let startTime = objc_getAssociatedObject(dataTask, "streamStartTime") as? CFAbsoluteTime ?? CFAbsoluteTimeGetCurrent()
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        
        guard let httpResponse = response as? HTTPURLResponse else {
            Logger.info("❌ Invalid stream response type after \(String(format: "%.3f", duration * 1000))ms")
            DispatchQueue.main.async {
                self.streamCallbacks?.onError("Invalid response format")
            }
            completionHandler(.cancel)
            return
        }
        
        if httpResponse.statusCode == 429 {
            Logger.warn("⚠️ Stream translation quota exceeded after \(String(format: "%.3f", duration * 1000))ms: \(httpResponse.statusCode)")
            
            // 对于429错误，需要继续接收数据以解析配额信息
            Logger.info("Allowing data reception to parse quota info from 429 response")
            completionHandler(.allow)
            return
        }
        
        guard httpResponse.statusCode == 200 else {
            Logger.info("❌ Stream translation API HTTP error after \(String(format: "%.3f", duration * 1000))ms: \(httpResponse.statusCode)")
            DispatchQueue.main.async {
                self.streamCallbacks?.onError("Server error: \(httpResponse.statusCode)")
            }
            completionHandler(.cancel)
            return
        }
        
        Logger.info("✅ Stream response started after \(String(format: "%.3f", duration * 1000))ms, status: \(httpResponse.statusCode)")
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let dataString = String(data: data, encoding: .utf8) else {
            Logger.error("Failed to decode stream data")
            return
        }
        
        
        // if isProductionEnvironment {
        //     Logger.info("Raw data: \(dataString.prefix(200))...") // Only show first 200 characters
        // }else{
        //     Logger.info("Raw data: \(dataString)")
        // }
        
        // 异步处理数据，避免阻塞delegate队列
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            self?.processStreamData(dataString)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { 
        // Get timing info if available
        let startTime = objc_getAssociatedObject(task, "streamStartTime") as? CFAbsoluteTime ?? CFAbsoluteTimeGetCurrent()
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        
        if let error = error {
            Logger.error("❌ Stream translation error after \(String(format: "%.3f", duration * 1000))ms: \(error.localizedDescription)")
            
            // Create corresponding TranslationError and show friendly reminders
            let translationError = TranslationError.networkError(error.localizedDescription)
            self.handleTranslationError(translationError)
            
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
                                        "monthly_usage": QuotaLimits.FREE_MONTHLY_LIMIT,
                                        "monthly_limit": QuotaLimits.FREE_MONTHLY_LIMIT
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
                                    "monthly_usage": QuotaLimits.FREE_MONTHLY_LIMIT,
                                    "monthly_limit": QuotaLimits.FREE_MONTHLY_LIMIT
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
                                "monthly_usage": QuotaLimits.FREE_MONTHLY_LIMIT,
                                "monthly_limit": QuotaLimits.FREE_MONTHLY_LIMIT
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
                            "monthly_usage": QuotaLimits.FREE_MONTHLY_LIMIT,
                            "monthly_limit": QuotaLimits.FREE_MONTHLY_LIMIT
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
                processStreamLine(streamBuffer)
            }
            Logger.info("✅ Stream translation completed successfully after \(String(format: "%.3f", duration * 1000))ms")
        }
         
        // 清理
        streamSession?.invalidateAndCancel()
        streamSession = nil
        streamCallbacks = nil
        streamProcessor = nil
        streamBuffer = "" 
    }
    
    private func processStreamData(_ dataString: String) {
        // Add to buffer for processing
        streamBuffer += dataString
        
        // Process complete lines
        let lines = streamBuffer.components(separatedBy: .newlines)
        
        // Keep the last incomplete line in buffer
        if lines.count > 1 {
            streamBuffer = lines.last ?? ""
            
            // Process complete lines
            for line in lines.dropLast() {
                processStreamLine(line)
            }
        }
    }
    
    private func processStreamLine(_ line: String) {
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
                        Logger.debug("Stream chunk: '\(content)' (newlines: \(content.contains("\n") ? "YES" : "NO"))")
                        Logger.debug("Full content newlines: \(fullContentFromResponse.contains("\n") ? "YES" : "NO")")
                        
                        DispatchQueue.main.async {
                            self.streamCallbacks?.onChunk(content, fullContentFromResponse)
                        }
                    } else {
                        Logger.error("Missing content or fullContent in chunk event")
                    }
                    
                case "end":
                    Logger.info("Processing end event")
                    let capturedCallbacks = self.streamCallbacks
                    
                    var quotaInfo: QuotaInfo?
                    if let quotaData = json["quota_info"] as? [String: Any] {
                        quotaInfo = QuotaInfo(from: quotaData)
                        Logger.info("Stream quota info: \(quotaInfo!.quotaDescription)")
                        
                        // Update cached quota info for client-side validation
                        self.updateCachedQuotaInfo(quotaInfo!)
                        
                        DispatchQueue.main.async {
                            self.quotaDelegate?.didReceiveQuotaUpdate(quotaInfo!)
                            
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
                    } else if let fullContent = json["fullContent"] as? String {
                        DispatchQueue.main.async {
                            capturedCallbacks?.onComplete(fullContent.isEmpty ? nil : fullContent, quotaInfo)
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

// MARK: - Quota Information
extension TranslatorClient {
    
    /// Fetch current quota information without consuming usage
    func fetchQuotaInfo(completion: @escaping (Result<QuotaInfo, TranslationError>) -> Void) {
        Logger.debug("Fetching quota info from server")
        
        AuthenticationHelper.shared.getAuthenticatedHeaders { [weak self] headers in
            guard let self = self,
                  let headers = headers else {
                Logger.error("Failed to get authenticated headers for quota fetch")
                completion(.failure(.authenticationRequired("Authentication required")))
                return
            }
            
            // Create quota endpoint URL by extracting base URL from apiEndpoint
            let baseURL = EnvironmentManager.shared.baseURL
            let quotaURL = "\(baseURL)/api/quota"
            Logger.debug("Quota URL: \(quotaURL)")
            guard let url = URL(string: quotaURL) else {
                Logger.error("Invalid quota URL: \(quotaURL)")
                completion(.failure(.networkError("Invalid quota URL")))
                return
            }
            
            // Create request
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
            request.timeoutInterval = self.timeoutInterval
            
            // Make request
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    Logger.error("Quota fetch network error: \(error.localizedDescription)")
                    completion(.failure(.networkError(error.localizedDescription)))
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    Logger.error("Invalid response for quota fetch")
                    completion(.failure(.networkError("Invalid response")))
                    return
                }
                
                guard let data = data else {
                    Logger.error("No data received for quota fetch")
                    completion(.failure(.networkError("No data received")))
                    return
                }
                
                if httpResponse.statusCode == 401 {
                    Logger.error("Quota fetch authentication failed")
                    completion(.failure(.authenticationRequired("Authentication required")))
                    return
                }
                
                guard httpResponse.statusCode == 200 else {
                    Logger.error("Quota fetch HTTP error: \(httpResponse.statusCode)")
                    completion(.failure(.serverError(httpResponse.statusCode, "Server error")))
                    return
                }
                
                // Parse response
                do {
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    if let quotaData = json?["quota_info"] as? [String: Any] {
                        let quotaInfo = QuotaInfo(from: quotaData)
                        Logger.info("Quota info fetched successfully: \(quotaInfo.quotaDescription)")
                        
                        // Update cached quota info for client-side validation
                        self.updateCachedQuotaInfo(quotaInfo)
                        
                        // Check if response contains updated user info and update local cache
                        // Only update userType from quotaInfo, as other user info rarely changes
                        SessionManager.shared.updateUserType(quotaInfo.userType)
                        
                        completion(.success(quotaInfo))
                    } else {
                        Logger.error("Failed to parse quota info from response")
                        completion(.failure(.parseError("Invalid quota response format")))
                    }
                } catch {
                    Logger.error("Failed to parse quota response JSON: \(error)")
                    completion(.failure(.parseError("JSON parsing failed")))
                }
            }
            
            task.resume()
        }
    }
} 
