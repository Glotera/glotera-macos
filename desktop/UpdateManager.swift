import Cocoa
import Foundation

#if canImport(Sparkle)
import Sparkle
#endif

// Update Manager for Sparkle integration
// Note: Sparkle framework needs to be added to the project for this to compile
// This implementation provides the structure for when Sparkle is integrated

class UpdateManager: NSObject {
    static let shared = UpdateManager()
    
    private var isSparkleAvailable = false
    
    #if canImport(Sparkle)
    private var updaterController: SPUStandardUpdaterController?
    #endif
    
    override init() {
        super.init()
        initializeSparkle()
    }
    
    private func initializeSparkle() {
        // Check if Sparkle framework is available
        #if canImport(Sparkle)
        let feedURL = EnvironmentManager.shared.baseURL + "/api/appcast.xml"
        Logger.info("Initializing Sparkle with feed URL: \(feedURL)")
        
        // Sparkle 2.7.1 initialization with delegate for custom feed URL
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        self.isSparkleAvailable = true
        Logger.info("Sparkle updater initialized successfully with delegate")
        #else
        Logger.warn("Sparkle framework not available - update checking disabled")
        self.isSparkleAvailable = false
        #endif
    }
    
    func checkForUpdates() {
        guard isSparkleAvailable else {
            Logger.warn("Cannot check for updates - Sparkle framework not available")
            return
        }
        
        #if canImport(Sparkle)
        Logger.info("Manually checking for updates...")
        updaterController?.updater.checkForUpdates()
        #endif
    }
    
    func checkForUpdatesInBackground() {
        guard isSparkleAvailable else {
            Logger.debug("Background update check skipped - Sparkle not available")
            return
        }
        
        #if canImport(Sparkle)
        Logger.debug("Checking for updates in background...")
        updaterController?.updater.checkForUpdatesInBackground()
        #endif
    }
    
    // Store current channel for delegate method
    private var currentChannel: String = "stable"
    
    func setUpdateChannel(_ channel: String) {
        guard isSparkleAvailable else {
            Logger.warn("Cannot set update channel - Sparkle framework not available")
            return
        }
        
        Logger.info("Switching to \(channel) channel")
        self.currentChannel = channel
        
        #if canImport(Sparkle)
        // Recreate updater with new delegate that will return new feed URL
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        Logger.info("Updater recreated with new channel: \(channel)")
        #endif
    }
    
    
    // Send analytics about update events
    private func sendUpdateAnalytics(event: String, currentVersion: String, targetVersion: String? = nil) {
        let environmentManager = EnvironmentManager.shared
        guard let url = URL(string: "\(environmentManager.serverURL)/api/app/analytics") else { 
            Logger.error("Invalid analytics URL")
            return 
        }
        
        let payload: [String: Any] = [
            "event_type": event,
            "app_version": currentVersion,
            "target_version": targetVersion ?? "",
            "user_id": UserManager.shared.userId,
            "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    Logger.debug("Failed to send update analytics: \(error.localizedDescription)")
                } else {
                    Logger.debug("Update analytics sent: \(event)")
                }
            }.resume()
        } catch {
            Logger.error("Failed to serialize analytics payload: \(error)")
        }
    }
    
    func getCurrentVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
    
    func performFirstLaunchCheck() {
        // Check for updates on first launch (after a delay)
        if isFirstLaunch() {
            Logger.info("First launch detected - will check for updates in 5 seconds")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                self.checkForUpdatesInBackground()
            }
        }
    }
    
    private func isFirstLaunch() -> Bool {
        let hasLaunchedKey = "HasLaunchedBefore"
        let hasLaunched = UserDefaults.standard.bool(forKey: hasLaunchedKey)
        if !hasLaunched {
            UserDefaults.standard.set(true, forKey: hasLaunchedKey)
            return true
        }
        return false
    }
    
}

// MARK: - Sparkle Delegate (when framework is available)
#if canImport(Sparkle)
extension UpdateManager: SPUUpdaterDelegate {
    
    // Provide custom feed URL based on environment and channel
    func feedURLString(for updater: SPUUpdater) -> String? {
        let baseURL = EnvironmentManager.shared.baseURL
        let feedURL = currentChannel == "beta" 
            ? "\(baseURL)/api/appcast.xml?channel=beta"
            : "\(baseURL)/api/appcast.xml"
        
        Logger.info("Providing feed URL: \(feedURL) for channel: \(currentChannel)")
        return feedURL
    }
    
    // Optional: Add analytics delegate methods
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Logger.info("Update available: current version: \(getCurrentVersion()), target version: \(item.versionString)")
        sendUpdateAnalytics(event: "update_available", 
                          currentVersion: getCurrentVersion(),
                          targetVersion: item.versionString)
    }
    
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Logger.debug("No updates available")
        sendUpdateAnalytics(event: "no_update_available", 
                          currentVersion: getCurrentVersion())
    }
    
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        Logger.info("Installing update: \(item.versionString)")
        sendUpdateAnalytics(event: "update_install_started", 
                          currentVersion: getCurrentVersion(),
                          targetVersion: item.versionString)
    }
    
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        Logger.error("Update failed with error: \(error.localizedDescription), current version: \(getCurrentVersion())")
        sendUpdateAnalytics(event: "update_failed", 
                          currentVersion: getCurrentVersion())
    }
}
#endif