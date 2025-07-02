import Foundation
import Security

// User information structure
struct User {
    let userId: String
    let email: String
    let username: String
    let userType: String  // free, pro, enterprise
    let accountType: String  // email, google
}

// Authentication session manager
class SessionManager {
    static let shared = SessionManager()
    
    private init() {}
    
    // Keychain service identifier
    private let keychainService = "ai.glotera.desktop"
    private let tokenKey = "auth_token"
    private let userIdKey = "user_id"
    
    // UserDefaults keys for additional user info
    private let userEmailKey = "user_email"
    private let usernameKey = "username"
    private let userTypeKey = "user_type"
    private let accountTypeKey = "account_type"
    
    // Current authentication state
    private var currentUser: User?
    private var authToken: String?
    
    // MARK: - Public Authentication Methods
    
    /// Check if user is currently authenticated
    var isAuthenticated: Bool {
        return getStoredToken() != nil && getCurrentUser() != nil
    }
    
    /// Get current authenticated user
    func getCurrentUser() -> User? {
        if let cachedUser = currentUser {
            return cachedUser
        }
        
        // Try to load user from storage
        guard let userId = getStoredUserId(),
              let email = UserDefaults.standard.string(forKey: userEmailKey),
              let username = UserDefaults.standard.string(forKey: usernameKey) else {
            return nil
        }
        
        let userType = UserDefaults.standard.string(forKey: userTypeKey) ?? "free"
        let accountType = UserDefaults.standard.string(forKey: accountTypeKey) ?? "email"
        
        let user = User(
            userId: userId,
            email: email,
            username: username,
            userType: userType,
            accountType: accountType
        )
        
        currentUser = user
        return user
    }
    
    /// Get current authentication token
    func getAuthToken() -> String? {
        if let cachedToken = authToken {
            return cachedToken
        }
        
        let token = getStoredToken()
        authToken = token
        return token
    }
    
    /// Store authentication session
    func setAuthSession(token: String, user: User) {
        Logger.info("SessionManager: Storing authentication session for user: \(user.email)")
        
        // Store token in Keychain
        storeTokenInKeychain(token)
        
        // Store user info in UserDefaults and Keychain
        storeUserIdInKeychain(user.userId)
        UserDefaults.standard.set(user.email, forKey: userEmailKey)
        UserDefaults.standard.set(user.username, forKey: usernameKey)
        UserDefaults.standard.set(user.userType, forKey: userTypeKey)
        UserDefaults.standard.set(user.accountType, forKey: accountTypeKey)
        
        // Cache in memory
        currentUser = user
        authToken = token
        
        Logger.info("SessionManager: Authentication session stored successfully")
        
        // Post notification for UI updates
        NotificationCenter.default.post(name: .userDidLogin, object: user)
    }
    
    /// Clear authentication session (logout)
    func clearSession() {
        Logger.info("SessionManager: Clearing authentication session")
        
        // Remove from Keychain
        removeTokenFromKeychain()
        removeUserIdFromKeychain()
        
        // Remove from UserDefaults
        UserDefaults.standard.removeObject(forKey: userEmailKey)
        UserDefaults.standard.removeObject(forKey: usernameKey)
        UserDefaults.standard.removeObject(forKey: userTypeKey)
        UserDefaults.standard.removeObject(forKey: accountTypeKey)
        
        // Clear cache
        currentUser = nil
        authToken = nil
        
        Logger.info("SessionManager: Authentication session cleared")
        
        // Post notification for UI updates
        NotificationCenter.default.post(name: .userDidLogout, object: nil)
    }
    
    /// Validate current token with server
    func validateToken(completion: @escaping (Bool) -> Void) {
        guard let token = getAuthToken() else {
            completion(false)
            return
        }
        
        let environmentManager = EnvironmentManager.shared
        let baseURL = environmentManager.serverURL
        
        guard let url = URL(string: "\(baseURL)/api/auth/verify") else {
            Logger.error("SessionManager: Invalid verification URL")
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = ["token": token]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            Logger.error("SessionManager: Failed to serialize verification request: \(error)")
            completion(false)
            return
        }
        
        Logger.info("SessionManager: Validating token with server")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    Logger.error("SessionManager: Token validation network error: \(error)")
                    completion(false)
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    Logger.error("SessionManager: Invalid response type")
                    completion(false)
                    return
                }
                
                if httpResponse.statusCode == 200 {
                    Logger.info("SessionManager: Token validation successful")
                    completion(true)
                } else {
                    Logger.warn("SessionManager: Token validation failed with status: \(httpResponse.statusCode)")
                    // Token is invalid, clear session
                    self?.clearSession()
                    completion(false)
                }
            }
        }.resume()
    }
    
    // MARK: - Private Keychain Methods
    
    private func storeTokenInKeychain(_ token: String) {
        let tokenData = Data(token.utf8)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenKey,
            kSecValueData as String: tokenData
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status != errSecSuccess {
            Logger.error("SessionManager: Failed to store token in Keychain: \(status)")
        } else {
            Logger.info("SessionManager: Token stored in Keychain successfully")
        }
    }
    
    private func getStoredToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let tokenData = result as? Data,
           let token = String(data: tokenData, encoding: .utf8) {
            return token
        }
        
        if status != errSecItemNotFound {
            Logger.error("SessionManager: Failed to retrieve token from Keychain: \(status)")
        }
        
        return nil
    }
    
    private func removeTokenFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenKey
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status != errSecSuccess && status != errSecItemNotFound {
            Logger.error("SessionManager: Failed to remove token from Keychain: \(status)")
        }
    }
    
    private func storeUserIdInKeychain(_ userId: String) {
        let userIdData = Data(userId.utf8)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: userIdKey,
            kSecValueData as String: userIdData
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status != errSecSuccess {
            Logger.error("SessionManager: Failed to store user ID in Keychain: \(status)")
        }
    }
    
    private func getStoredUserId() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: userIdKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let userIdData = result as? Data,
           let userId = String(data: userIdData, encoding: .utf8) {
            return userId
        }
        
        return nil
    }
    
    private func removeUserIdFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: userIdKey
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status != errSecSuccess && status != errSecItemNotFound {
            Logger.error("SessionManager: Failed to remove user ID from Keychain: \(status)")
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let userDidLogin = Notification.Name("userDidLogin")
    static let userDidLogout = Notification.Name("userDidLogout")
}

// MARK: - JWT Token Utilities
extension SessionManager {
    
    /// Parse JWT token to extract user information (for debugging/validation)
    func parseJWTToken(_ token: String) -> [String: Any]? {
        let segments = token.components(separatedBy: ".")
        guard segments.count == 3 else {
            Logger.error("SessionManager: Invalid JWT token format")
            return nil
        }
        
        let payload = segments[1]
        
        // Add padding if needed
        var paddedPayload = payload
        let padding = 4 - (payload.count % 4)
        if padding != 4 {
            paddedPayload += String(repeating: "=", count: padding)
        }
        
        guard let payloadData = Data(base64Encoded: paddedPayload),
              let payloadDict = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            Logger.error("SessionManager: Failed to decode JWT payload")
            return nil
        }
        
        return payloadDict
    }
    
    /// Check if JWT token is expired
    func isTokenExpired(_ token: String) -> Bool {
        guard let payload = parseJWTToken(token),
              let exp = payload["exp"] as? TimeInterval else {
            return true
        }
        
        let expirationDate = Date(timeIntervalSince1970: exp)
        return Date() >= expirationDate
    }
}