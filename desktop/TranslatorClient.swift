import Foundation

class TranslatorClient: NSObject {
    static let shared = TranslatorClient()
    let endpoint = "http://localhost:1145/translate"
    private let timeoutInterval: TimeInterval = 30.0
    
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
    } // 10秒超时

    func translate(text: String, to: String, completion: @escaping (String?) -> Void) {
        Logger.info("Calling translation API")
        guard let url = URL(string: endpoint) else { 
            Logger.info("Invalid URL: \(endpoint)")
            completion(nil)
            return 
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeoutInterval
        
        let body: [String: Any] = ["text": text, "to": to]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            Logger.info("Failed to serialize request body: \(error)")
            completion(nil)
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                Logger.info("Translation API error: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                Logger.info("Invalid response type")
                completion(nil)
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                Logger.info("Translation API HTTP error: \(httpResponse.statusCode)")
                completion(nil)
                return
            }
            
            guard let data = data else {
                Logger.info("No data received from translation API")
                completion(nil)
                return
            } 
            
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let translated = json["translated"] as? String else {
                    Logger.info("Failed to parse translation response")
                    completion(nil)
                    return
                }
                Logger.info("Translation successful")
                completion(translated)
            } catch {
                Logger.info("Failed to parse JSON response: \(error)")
                completion(nil)
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
        streamSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeoutInterval
        
        // 添加 stream: true 参数
        let body: [String: Any] = ["text": text, "to": to, "stream": true]
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
            Logger.info("Failed to decode stream data")
            return
        }
        
        // 将新数据添加到缓冲区
        streamBuffer += dataString
        
        // 处理缓冲区中的完整行
        var fullContent = ""
        let lines = streamBuffer.components(separatedBy: .newlines)
        
        // 保留最后一行（可能不完整）
        if lines.count > 1 {
            streamBuffer = lines.last ?? ""
            
            // 处理完整的行
            for line in lines.dropLast() {
                processStreamLine(line, fullContent: &fullContent)
            }
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
    
    private func processStreamLine(_ line: String, fullContent: inout String) {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedLine.isEmpty || trimmedLine == "data: [DONE]" {
            return
        }
        
        if trimmedLine.hasPrefix("data: ") {
            let jsonString = String(trimmedLine.dropFirst(6))
            
            do {
                guard let jsonData = jsonString.data(using: .utf8),
                      let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                      let type = json["type"] as? String else {
                    Logger.info("Failed to parse stream JSON: \(jsonString)")
                    return
                }
                
                switch type {
                case "chunk":
                    if let content = json["content"] as? String,
                       let fullContentFromResponse = json["fullContent"] as? String {
                        fullContent = fullContentFromResponse
                        Logger.info("Stream chunk received: \(content)")
                        let capturedFullContent = fullContent // 捕获值而非引用
                        DispatchQueue.main.async {
                            self.streamCallbacks?.onChunk(content, capturedFullContent)
                        }
                    }
                    
                case "end":
                    Logger.info("Processing end event") 
                    
                    // 捕获回调，避免被 didCompleteWithError 清理
                    let capturedCallbacks = self.streamCallbacks
                    
                    if let result = json["result"] as? [String: Any],
                       let translated = result["translated"] as? String { 
                        DispatchQueue.main.async {
                            capturedCallbacks?.onComplete(translated)
                        }
                    } else {
                        Logger.info("Stream translation completed with accumulated content: \(fullContent)")
                        let capturedFullContent = fullContent // 捕获值而非引用
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
