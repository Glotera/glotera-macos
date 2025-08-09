import Foundation

// User information structure
struct User {
    let userId: String
    let email: String
    let username: String
    let userType: String  // free, pro, enterprise
    let accountType: String  // email, google
}

// MARK: - Authentication Cache
struct AuthenticationCacheEntry {
    let token: String
    let user: User
    let validatedAt: Date
    let isValid: Bool
    
    var isExpired: Bool {
        Date().timeIntervalSince(validatedAt) > AuthenticationCache.validationTTL
    }
}

class AuthenticationCache {
    static let validationTTL: TimeInterval = 300 // 5 minutes
    static let fastCheckTTL: TimeInterval = 30   // 30 seconds for fast local checks
    
    private var cacheEntry: AuthenticationCacheEntry?
    private var lastFastCheck: Date?
    private let cacheQueue = DispatchQueue(label: "authCache", attributes: .concurrent)
    
    func getCachedEntry() -> AuthenticationCacheEntry? {
        return cacheQueue.sync {
            guard let entry = cacheEntry, !entry.isExpired else {
                return nil
            }
            return entry
        }
    }
    
    func setCachedEntry(_ entry: AuthenticationCacheEntry) {
        cacheQueue.async(flags: .barrier) {
            self.cacheEntry = entry
        }
    }
    
    func clearCache() {
        cacheQueue.async(flags: .barrier) {
            self.cacheEntry = nil
            self.lastFastCheck = nil
        }
    }
    
    func shouldPerformFastCheck() -> Bool {
        guard let lastCheck = lastFastCheck else { return true }
        return Date().timeIntervalSince(lastCheck) > Self.fastCheckTTL
    }
    
    func updateFastCheck() {
        cacheQueue.async(flags: .barrier) {
            self.lastFastCheck = Date()
        }
    }
}

// Authentication session manager
class SessionManager {
    static let shared = SessionManager()
    
    private init() {}
    
    // UserDefaults keys for all user info (moved from Keychain to reduce user interruption)
    private let tokenKey = "auth_token"
    private let userIdKey = "user_id"
    private let userEmailKey = "user_email"
    private let usernameKey = "username"
    private let userTypeKey = "user_type"
    private let accountTypeKey = "account_type"
    
    // Current authentication state
    private var currentUser: User?
    private var authToken: String?
    
    // Authentication caching
    private let authCache = AuthenticationCache()
    private var pendingValidations: [String: [(Bool) -> Void]] = [:]
    private let validationQueue = DispatchQueue(label: "authValidation", attributes: .concurrent)
    
    // MARK: - Public Authentication Methods
    
    /// Check if user is currently authenticated (fast local check with caching)
    var isAuthenticated: Bool {
        // First check cached validation result
        if let cachedEntry = authCache.getCachedEntry() {
            // Logger.debug("SessionManager: ✅ Cache hit - using cached authentication result: \(cachedEntry.isValid)")
            PerformanceTelemetry.shared.recordAuthCacheHit(true)
            return cachedEntry.isValid
        }
        
        // Perform fast local check only if needed
        if authCache.shouldPerformFastCheck() {
            let hasToken = getStoredToken() != nil
            let hasUser = getCurrentUser() != nil
            let authenticated = hasToken && hasUser
            
            authCache.updateFastCheck()
            PerformanceTelemetry.shared.recordAuthCacheHit(false)
            Logger.debug("SessionManager: Fast auth check - hasToken: \(hasToken), hasUser: \(hasUser), isAuthenticated: \(authenticated)")
            
            return authenticated
        }
        
        // Return last known state if recent fast check was performed
        let hasToken = authToken != nil || getStoredToken() != nil
        let hasUser = currentUser != nil
        let authenticated = hasToken && hasUser
        
        Logger.debug("SessionManager: Fallback auth check - isAuthenticated: \(authenticated)")
        return authenticated
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
    
    /// Get current authentication token (with caching)
    func getAuthToken() -> String? {
        // Check cached entry first
        if let cachedEntry = authCache.getCachedEntry(), cachedEntry.isValid {
            return cachedEntry.token
        }
        
        // Fall back to memory cache
        if let cachedToken = authToken {
            return cachedToken
        }
        
        // Load from storage as last resort
        let token = getStoredToken()
        authToken = token
        return token
    }
    
    /// Get authentication token with validation (cached)
    func getValidatedAuthToken(completion: @escaping (String?) -> Void) {
        // Check if we have a valid cached entry
        if let cachedEntry = authCache.getCachedEntry(), cachedEntry.isValid {
            Logger.debug("SessionManager: ✅ Cache hit - returning cached valid token")
            completion(cachedEntry.token)
            return
        }
        
        // Validate token asynchronously
        validateTokenCached { [weak self] isValid in
            if isValid {
                completion(self?.getAuthToken())
            } else {
                completion(nil)
            }
        }
    }
    
    /// Store authentication session
    func setAuthSession(token: String, user: User) {
        Logger.info("SessionManager: Storing authentication session for user: \(user.email)")
        
        // Store token and user info in UserDefaults (moved from Keychain to reduce interruption)
        UserDefaults.standard.set(token, forKey: tokenKey)
        UserDefaults.standard.set(user.userId, forKey: userIdKey)
        UserDefaults.standard.set(user.email, forKey: userEmailKey)
        UserDefaults.standard.set(user.username, forKey: usernameKey)
        UserDefaults.standard.set(user.userType, forKey: userTypeKey)
        UserDefaults.standard.set(user.accountType, forKey: accountTypeKey)
        
        // Cache in memory
        currentUser = user
        authToken = token
        
        // Create cached entry with successful validation
        let cacheEntry = AuthenticationCacheEntry(
            token: token,
            user: user,
            validatedAt: Date(),
            isValid: true
        )
        authCache.setCachedEntry(cacheEntry)
        
        Logger.info("SessionManager: Authentication session stored successfully with cache")
        
        // Post notification for UI updates
        NotificationCenter.default.post(name: .userDidLogin, object: user)
    }
    
    /// Clear authentication session (logout)
    func clearSession() {
        Logger.info("SessionManager: Clearing authentication session")
        
        // Remove from UserDefaults (no longer using Keychain)
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: userIdKey)
        UserDefaults.standard.removeObject(forKey: userEmailKey)
        UserDefaults.standard.removeObject(forKey: usernameKey)
        UserDefaults.standard.removeObject(forKey: userTypeKey)
        UserDefaults.standard.removeObject(forKey: accountTypeKey)
        
        // Clear cache
        currentUser = nil
        authToken = nil
        authCache.clearCache()
        
        Logger.info("SessionManager: Authentication session cleared with cache")
        
        // Post notification for UI updates
        NotificationCenter.default.post(name: .userDidLogout, object: nil)
    }
    
    /// Validate current token with server
    func validateToken(completion: @escaping (Bool) -> Void) {
        let timer = PerformanceTelemetry.shared.startTiming("auth.validation")
        
        guard let token = getAuthToken() else {
            timer.finish(success: false)
            completion(false)
            return
        }
        
        // First check if token is expired locally (faster than server call)
        if isTokenExpired(token) {
            Logger.warn("SessionManager: Token is expired locally, clearing session")
            clearSession()
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
        request.timeoutInterval = 10.0  // 10 second timeout to prevent hanging
        
        let requestBody = ["token": token]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            Logger.error("SessionManager: Failed to serialize verification request: \(error)")
            completion(false)
            return
        }
        
        Logger.debug("SessionManager: Validating token with server")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    Logger.error("SessionManager: Token validation network error: \(error)")
                    timer.addContext("error_type", "network")
                    timer.finish(success: false)
                    // Don't fail authentication due to network issues - allow offline usage
                    Logger.info("SessionManager: Allowing offline authentication due to network error")
                    completion(true)
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    Logger.error("SessionManager: Invalid response type")
                    timer.addContext("error_type", "invalid_response")
                    timer.finish(success: false)
                    completion(false)
                    return
                }
                
                timer.addContext("status_code", httpResponse.statusCode)
                
                if httpResponse.statusCode == 200 {
                    Logger.debug("SessionManager: Token validation successful")
                    timer.finish(success: true)
                    completion(true)
                } else if httpResponse.statusCode == 401 {
                    Logger.warn("SessionManager: Token validation failed - token is invalid or expired")
                    timer.addContext("error_type", "unauthorized")
                    timer.finish(success: false)
                    // Only clear session for 401 (unauthorized)
                    self?.clearSession()
                    completion(false)
                } else {
                    Logger.warn("SessionManager: Token validation failed with status: \(httpResponse.statusCode)")
                    timer.addContext("error_type", "server_error")
                    timer.finish(success: false)
                    // For other HTTP errors (500, 503, etc.), don't clear session - might be temporary server issues
                    Logger.info("SessionManager: Allowing offline authentication due to server error")
                    completion(true)
                }
            }
        }.resume()
    }
    
    /// Validate token with caching and batching support
    func validateTokenCached(completion: @escaping (Bool) -> Void) {
        guard let token = getAuthToken(),
              let user = getCurrentUser() else {
            completion(false)
            return
        }
        
        // Check cached validation result first
        if let cachedEntry = authCache.getCachedEntry() {
            Logger.debug("SessionManager: ✅ Cache hit - using cached validation result: \(cachedEntry.isValid)")
            completion(cachedEntry.isValid)
            return
        }
        
        // Check for pending validation for this token to avoid duplicate calls
        let shouldStartValidation = validationQueue.sync { () -> Bool in
            if var pendingCallbacks = pendingValidations[token] {
                // Add to existing batch
                pendingCallbacks.append(completion)
                pendingValidations[token] = pendingCallbacks
                Logger.debug("SessionManager: Added to batch validation (total: \(pendingCallbacks.count))")
                return false // Don't start new validation
            } else {
                // Start new batch validation
                pendingValidations[token] = [completion]
                Logger.debug("SessionManager: Starting new batch validation")
                return true // Start new validation
            }
        }
        
        guard shouldStartValidation else {
            return // Validation already in progress, callback added to batch
        }
        
        // Perform actual validation
        validateToken { [weak self] isValid in
            guard let self = self else { return }
            
            // Create cache entry
            let cacheEntry = AuthenticationCacheEntry(
                token: token,
                user: user,
                validatedAt: Date(),
                isValid: isValid
            )
            self.authCache.setCachedEntry(cacheEntry)
            
            // Notify all pending callbacks
            let callbacks = self.validationQueue.sync { () -> [(Bool) -> Void] in
                let callbacks = self.pendingValidations[token] ?? []
                self.pendingValidations.removeValue(forKey: token)
                return callbacks
            }
            
            Logger.debug("SessionManager: Batch validation completed, notifying \(callbacks.count) callbacks")
            for callback in callbacks {
                callback(isValid)
            }
        }
    }
    
    /// Get authentication cache statistics for performance monitoring
    func getAuthCacheStats() -> (cacheHits: Bool, pendingValidations: Int) {
        let hasCachedEntry = authCache.getCachedEntry() != nil
        let pendingCount = validationQueue.sync {
            return pendingValidations.values.reduce(0) { $0 + $1.count }
        }
        return (hasCachedEntry, pendingCount)
    }
    
    /// Check if current user has access to chat translation feature (Pro/Max only)
    func hasChatTranslationAccess() -> Bool {
        guard let user = getCurrentUser() else {
            return false
        }
        
        // Allow access for pro and enterprise (max) users only
        return user.userType.lowercased() == "pro" || user.userType.lowercased() == "max"
    }
    
    // MARK: - Private UserDefaults Methods
    
    private func getStoredToken() -> String? {
        let token = UserDefaults.standard.string(forKey: tokenKey)
        if token != nil {
            Logger.debug("SessionManager: Retrieved token from UserDefaults successfully")
        } else {
            Logger.info("SessionManager: No token found in UserDefaults")
        }
        return token
    }
    
    private func getStoredUserId() -> String? {
        return UserDefaults.standard.string(forKey: userIdKey)
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let userDidLogin = Notification.Name("userDidLogin")
    static let userDidLogout = Notification.Name("userDidLogout")
    static let quotaInfoUpdated = Notification.Name("quotaInfoUpdated")
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