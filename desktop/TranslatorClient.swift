import Foundation

class TranslatorClient {
    static let shared = TranslatorClient()
    let endpoint = "http://localhost:1145/translate"
    private let timeoutInterval: TimeInterval = 30.0 // 10秒超时

    func translate(text: String, to: String, completion: @escaping (String?) -> Void) {
        NSLog("[LOG] Calling translation API: text=\(text), to=\(to)")
        guard let url = URL(string: endpoint) else { 
            NSLog("[LOG] Invalid URL: \(endpoint)")
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
            NSLog("[LOG] Failed to serialize request body: \(error)")
            completion(nil)
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                NSLog("[LOG] Translation API error: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                NSLog("[LOG] Invalid response type")
                completion(nil)
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                NSLog("[LOG] Translation API HTTP error: \(httpResponse.statusCode)")
                completion(nil)
                return
            }
            
            guard let data = data else {
                NSLog("[LOG] No data received from translation API")
                completion(nil)
                return
            }
            
            NSLog("[LOG] Translation API response: \(String(data: data, encoding: .utf8) ?? "nil")")
            
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let translated = json["translated"] as? String else {
                    NSLog("[LOG] Failed to parse translation response")
                    completion(nil)
                    return
                }
                NSLog("[LOG] Translation successful: \(translated)")
                completion(translated)
            } catch {
                NSLog("[LOG] Failed to parse JSON response: \(error)")
                completion(nil)
            }
        }
        task.resume()
    }
} 
