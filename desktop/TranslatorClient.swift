import Foundation

class TranslatorClient {
    static let shared = TranslatorClient()
    let endpoint = "http://localhost:1145/translate"

    func translate(text: String, to: String, completion: @escaping (String?) -> Void) {
        print("[LOG] Calling translation API: text=\(text), to=\(to)")
        guard let url = URL(string: endpoint) else { completion(nil); return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["text": text, "to": to]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            print("[LOG] Translation API response: \(String(data: data ?? Data(), encoding: .utf8) ?? "nil")")
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let translated = json["translated"] as? String else {
                completion(nil)
                return
            }
            completion(translated)
        }
        task.resume()
    }
} 