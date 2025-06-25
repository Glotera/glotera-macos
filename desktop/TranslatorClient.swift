import Foundation

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
                apiEndpoint: "https://glotera.ai/api/translate", 
                isProduction: true,
                timeoutInterval: 30.0,
                maxRetries: 3
            )
        #endif
    }()
}

class TranslatorClient: NSObject {
    static let shared = TranslatorClient()
    
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
        let onComplete: (String?) -> Void
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

    // 翻译文本
    func translate(text: String, to language: String, completion: @escaping (Result<String, Error>) -> Void) {
        // 使用信号量进行同步调用
        translationSemaphore.wait()
        
        Logger.info("Calling translation API")
        
        guard let url = URL(string: endpoint) else {
            Logger.error("Invalid API URL")
            translationSemaphore.signal()
            completion(.failure(URLError(.badURL)))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 构建包含环境信息的新请求体
        let environment = EnvironmentManager.shared.getEnvironmentInfo()
        let userId = UserManager.shared.getUserId()
        
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
            completion(.failure(error))
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            // 确保在退出时总是释放信号量
            defer { self.translationSemaphore.signal() }

            if let error = error {
                Logger.info("Translation API error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                Logger.info("Invalid response type")
                completion(.failure(NSError(domain: "", code: 0, userInfo: nil)))
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                Logger.info("Translation API HTTP error: \(httpResponse.statusCode)")
                completion(.failure(NSError(domain: "", code: httpResponse.statusCode, userInfo: nil)))
                return
            }
            
            guard let data = data else {
                Logger.info("No data received from translation API")
                completion(.failure(NSError(domain: "", code: 0, userInfo: nil)))
                return
            } 
            
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let translated = json["translated"] as? String else {
                    Logger.info("Failed to parse translation response")
                    completion(.failure(NSError(domain: "", code: 0, userInfo: nil)))
                    return
                }
                Logger.info("Translation successful: \(translated)")
                completion(.success(translated))
            } catch {
                Logger.info("Failed to parse JSON response: \(error)")
                completion(.failure(error))
            }
        }
        task.resume()
    }
    
    func translateStream(
        text: String, 
        to: String, 
        onChunk: @escaping (String, String) -> Void,  // (chunk, fullContent)
        onComplete: @escaping (String?) -> Void,      // finalResult
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
        
        // 添加流式相关的请求头
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        
        // Build the request body with environment info
        let environment = EnvironmentManager.shared.getEnvironmentInfo()
        let userId = UserManager.shared.getUserId()
        
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
                    
                    if let result = json["result"] as? [String: Any],
                       let translated = result["translated"] as? String {
                        DispatchQueue.main.async {
                            capturedCallbacks?.onComplete(translated)
                        }
                    } else {
                        DispatchQueue.main.async {
                            capturedCallbacks?.onComplete(capturedFullContent.isEmpty ? nil : capturedFullContent)
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
