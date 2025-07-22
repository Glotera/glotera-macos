import Cocoa
import Foundation

class UserManager {
    
    static let shared = UserManager()
    
    private(set) var userId: String
    
    private let userIdKey = "GloteraUserID"
    
    private init() {
        // Initialize with a temporary value. The real value is set in loadOrCreateUserId.
        self.userId = ""
        self.userId = loadOrCreateUserId()
        Logger.info("UserManager initialized. User ID: \(self.userId)")
    }
    
    private func loadOrCreateUserId() -> String {
        let userDefaults = UserDefaults.standard
        
        // Try to load existing user ID
        if let existingUserId = userDefaults.string(forKey: userIdKey) {
            Logger.info("Found existing User ID: \(existingUserId)")
            return existingUserId
        }
        
        // If not found, create and save a new one
        let newUserId = UUID().uuidString
        userDefaults.set(newUserId, forKey: userIdKey)
        Logger.info("No User ID found. Generated a new one: \(newUserId)")
        
        return newUserId
    }
    

    
    // Optional: A function to get the user ID, which makes the usage clear.
    public func getUserId() -> String {
        return self.userId
    }

    func promptLogin(reason: String) {
        let alert = NSAlert()
        alert.messageText = "Sign In Required"
        alert.informativeText = reason
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Sign In")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            openLoginPage()
        }  
    }
    
    func openLoginPage() {
        let environmentManager = EnvironmentManager.shared
        let loginURL = "\(environmentManager.baseURL)/login?redirect=glotera://auth/callback"
        
        guard let url = URL(string: loginURL) else {
            Logger.error("Failed to create login URL")
            return
        }
        
        Logger.info("Opening login page: \(loginURL)")
        NSWorkspace.shared.open(url)
    }
}
