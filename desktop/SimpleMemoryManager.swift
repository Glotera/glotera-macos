import Cocoa
import Foundation

/// Minimal no-op memory manager to prevent crashes while maintaining interface compatibility
class SimpleMemoryManager {
    static let shared = SimpleMemoryManager()
    
    // MARK: - Statistics (for interface compatibility)
    private var totalWindowsCreated: Int = 0
    private var totalWindowsCleaned: Int = 0
    
    private init() {
        Logger.info("SimpleMemoryManager initialized (no-op mode for stability)")
    }
    
    // MARK: - Window Tracking (No-op implementations)
    
    func registerWindow(_ window: NSWindow) {
        // No-op: Just increment counter for statistics
        totalWindowsCreated += 1
        Logger.debug("SimpleMemoryManager: Registered window (no-op mode)")
    }
    
    func unregisterWindow(_ window: NSWindow?) {
        // No-op: Safe to call even with deallocated windows
        Logger.debug("SimpleMemoryManager: Unregistered window (no-op mode)")
    }
    
    // MARK: - Public Interface
    
    func getStatistics() -> (active: Int, created: Int, cleaned: Int) {
        // Return basic statistics without actual tracking
        return (active: 0, created: totalWindowsCreated, cleaned: totalWindowsCleaned)
    }
    
    func forceCleanup() {
        Logger.info("SimpleMemoryManager: Force cleanup requested (no-op mode)")
        // Just hide the status window as a simple cleanup
        TranslationStatusWindow.shared.hideStatus()
        totalWindowsCleaned += 1
    }
}