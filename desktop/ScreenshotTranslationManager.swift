import Cocoa
import Foundation
import Combine

/// Utility class for mapping between key codes and key strings
class KeyCodeMapper {
    /// Convert a key string to its corresponding macOS key code
    static func getKeyCode(for keyString: String) -> UInt16 {
        switch keyString.uppercased() {
        case "A": return 0
        case "S": return 1
        case "D": return 2
        case "F": return 3
        case "H": return 4
        case "G": return 5
        case "Z": return 6
        case "X": return 7
        case "C": return 8
        case "V": return 9
        case "B": return 11
        case "Q": return 12
        case "W": return 13
        case "E": return 14
        case "R": return 15
        case "Y": return 16
        case "T": return 17
        case "1": return 18
        case "2": return 19
        case "3": return 20
        case "4": return 21
        case "6": return 22
        case "5": return 23
        case "=": return 24
        case "9": return 25
        case "7": return 26
        case "-": return 27
        case "8": return 28
        case "0": return 29
        case "]": return 30
        case "O": return 31
        case "U": return 32
        case "[": return 33
        case "I": return 34
        case "P": return 35
        case "L": return 37
        case "J": return 38
        case "'": return 39
        case "K": return 40
        case ";": return 41
        case "\\": return 42
        case ",": return 43
        case "/": return 44
        case "N": return 45
        case "M": return 46
        case ".": return 47
        case "`": return 50
        case "F1": return 122
        case "F2": return 120
        case "F3": return 99
        case "F4": return 118
        case "F5": return 96
        case "F6": return 97
        case "F7": return 98
        case "F8": return 100
        case "F9": return 101
        case "F10": return 109
        case "F11": return 103
        case "F12": return 111
        default: return 1 // Default to 'S' key
        }
    }

    /// Convert a key code to its corresponding key string
    static func getKeyString(for keyCode: UInt16) -> String? {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 50: return "`"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default: return nil
        }
    }

    /// Check if a key string is valid for hotkey use (letters A-Z and numbers 0-9 only)
    static func isValidHotkeyKey(_ keyString: String) -> Bool {
        let validKeys = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
        return validKeys.contains(keyString.uppercased())
    }
}

// Structure to represent user-configured hotkey
struct UserHotkey {
    let keyCode: UInt16
    let requiredModifiers: NSEvent.ModifierFlags
    let description: String
}

class ScreenshotTranslationManager: NSObject {
    static let shared = ScreenshotTranslationManager()

    private var globalMonitor: Any?
    private var localMonitor: Any?  // Add local monitor for in-app events
    private var translationWindow: ImageTranslationWindow?
    private var isScreenshotInProgress = false
    override init() {
        super.init()
        Logger.info("📸 Initializing ScreenshotTranslationManager...")
        setupScreenshotHotkey()
    }

    // Setup screenshot hotkey using user-configured settings
    private func setupScreenshotHotkey() {
        let userHotkey = getUserConfiguredHotkey()
        Logger.info("🔑 Setting up screenshot hotkey (\(userHotkey.description)) using NSEvent...")

        // Remove existing monitors if any
        if let existingMonitor = globalMonitor {
            NSEvent.removeMonitor(existingMonitor)
            globalMonitor = nil
        }
        if let existingLocal = localMonitor {
            NSEvent.removeMonitor(existingLocal)
            localMonitor = nil
        }

        // Add global monitor for events outside the app
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        // Add local monitor for events within the app (so it works when app has focus)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
            return event  // Return the event so it continues to be processed
        }

        if globalMonitor != nil && localMonitor != nil {
            Logger.info("✅ NSEvent monitors (global + local) installed successfully for screenshot hotkey: \(userHotkey.description)")
        } else {
            Logger.error("❌ Failed to install NSEvent monitors for screenshot hotkey")
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // Prevent multiple screenshot processes
        guard !isScreenshotInProgress else {
            Logger.warn("Screenshot already in progress, ignoring hotkey")
            return
        }

        let keyCode = event.keyCode
        let modifierFlags = event.modifierFlags

        // Get user-configured hotkey settings
        let userHotkey = getUserConfiguredHotkey()

        // Check if the pressed key matches user's configured hotkey
        if keyCode == userHotkey.keyCode && modifierFlags.contains(userHotkey.requiredModifiers) {
            // Make sure we don't have extra modifiers
            let relevantModifiers = modifierFlags.intersection([.command, .shift, .control, .option])
            if relevantModifiers == userHotkey.requiredModifiers {
                Logger.info("🚨 User configured hotkey detected (\(userHotkey.description)) - IMMEDIATE screenshot capture!")

                // Set flag to prevent concurrent screenshots
                isScreenshotInProgress = true

                // CRITICAL: Capture screen IMMEDIATELY before any other processing
                // This ensures we get the current foreground application (Chrome)
                guard let immediateScreenshot = captureScreenImmediately() else {
                    Logger.error("Failed to capture immediate screenshot")
                    isScreenshotInProgress = false // Reset flag on error
                    return
                }

                DispatchQueue.main.async { [weak self] in
                    self?.triggerScreenshotTranslationWithPreCapture(immediateScreenshot)
                }
            }
        }
    }

    // Get user-configured hotkey settings
    private func getUserConfiguredHotkey() -> UserHotkey {
        // Load settings from UserDefaults with defaults (Shift+Option+S)
        let keyString = UserDefaults.standard.string(forKey: "screenshot_hotkey_key") ?? "S"
        let useCmd = UserDefaults.standard.bool(forKey: "screenshot_hotkey_cmd")
        let useShift = UserDefaults.standard.object(forKey: "screenshot_hotkey_shift") == nil ? true : UserDefaults.standard.bool(forKey: "screenshot_hotkey_shift")
        let useOption = UserDefaults.standard.object(forKey: "screenshot_hotkey_option") == nil ? true : UserDefaults.standard.bool(forKey: "screenshot_hotkey_option")
        let useControl = UserDefaults.standard.bool(forKey: "screenshot_hotkey_control")

        // Convert key string to key code
        let keyCode = KeyCodeMapper.getKeyCode(for: keyString)

        // Build modifier flags
        var modifiers: NSEvent.ModifierFlags = []
        if useCmd { modifiers.insert(.command) }
        if useShift { modifiers.insert(.shift) }
        if useOption { modifiers.insert(.option) }
        if useControl { modifiers.insert(.control) }

        // Build description
        var components: [String] = []
        if useControl { components.append("⌃") }
        if useOption { components.append("⌥") }
        if useShift { components.append("⇧") }
        if useCmd { components.append("⌘") }
        components.append(keyString)
        let description = components.joined(separator: "")

        return UserHotkey(
            keyCode: keyCode,
            requiredModifiers: modifiers,
            description: description
        )
    }


    // Capture screen immediately on hotkey detection (before any UI changes)
    private func captureScreenImmediately() -> NSImage? {
        Logger.info("📸 Capturing screen state IMMEDIATELY on hotkey...")
        
        // Check screen recording permissions first (macOS 10.15+)
        if #available(macOS 10.15, *) {
            if !hasScreenRecordingPermission() {
                Logger.error("❌ Screen recording permission not granted")
                DispatchQueue.main.async {
                    self.showScreenRecordingPermissionAlert()
                }
                return nil
            }
        }

        // Method 1: Try CGWindowListCreateImage first (captures all visible windows)
        if let windowImage = captureScreenUsingWindowListImmediate() {
            Logger.info("✅ IMMEDIATE screenshot using CGWindowListCreateImage: should show current application content")
            return windowImage
        }

        // Method 2: Fallback to CGDisplayCreateImage
        Logger.warn("⚠️ CGWindowListCreateImage failed, trying CGDisplayCreateImage...")
        return captureScreenUsingDisplayImageImmediate()
    }
    
    // MARK: - Permission Management
    
    @available(macOS 10.15, *)
    private func hasScreenRecordingPermission() -> Bool {
        // Test by trying to capture a small area
        let testRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        let options: CGWindowListOption = [.optionOnScreenOnly]
        
        if let testImage = CGWindowListCreateImage(testRect, options, kCGNullWindowID, []) {
            // If we can capture, we likely have permission
            return true
        } else {
            // If we can't capture, we likely don't have permission
            return false
        }
    }
    
    private func showScreenRecordingPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "Glotera needs screen recording permission to capture screenshots for translation. Please grant permission in System Preferences > Security & Privacy > Privacy > Screen Recording."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open System Preferences to Screen Recording section
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    // MARK: - Public Permission Methods
    
    /// Manually request screen recording permission (useful for setup)
    func requestScreenRecordingPermission() {
        if #available(macOS 10.15, *) {
            if !hasScreenRecordingPermission() {
                Logger.info("Requesting screen recording permission...")
                showScreenRecordingPermissionAlert()
            } else {
                Logger.info("Screen recording permission already granted")
            }
        } else {
            Logger.info("Screen recording permission not required on this macOS version")
        }
    }

    private func captureScreenUsingWindowListImmediate() -> NSImage? {
        // For multi-monitor setup, get the screen containing the mouse cursor
        let mouseLocation = NSEvent.mouseLocation
        let currentScreen = NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens.first!

        Logger.info("🖥️ Immediate capture from screen: \(currentScreen.frame) for mouse at: \(mouseLocation)")
        let screenRect = currentScreen.frame
        let cgRect = CGRect(
            x: screenRect.origin.x,
            y: screenRect.origin.y,
            width: screenRect.size.width,
            height: screenRect.size.height
        )

        // Use the same improved capture strategies as ScreenshotManager
        let captureStrategies: [(String, CGWindowListOption)] = [
            // Strategy 1: Capture all windows on screen (most comprehensive)
            ("AllOnScreen", [.optionAll, .optionOnScreenOnly]),
            
            // Strategy 2: Capture on-screen windows including current window
            ("OnScreenIncluding", [.optionOnScreenOnly, .optionIncludingWindow]),
            
            // Strategy 3: Capture windows above current window
            ("OnScreenAbove", [.optionOnScreenAboveWindow]),
            
            // Strategy 4: Basic on-screen only
            ("OnScreenBasic", [.optionOnScreenOnly])
        ]
        
        for (strategyName, options) in captureStrategies {
            Logger.info("📸 Immediate capture trying strategy: \(strategyName)")
            
            if let cgImage = CGWindowListCreateImage(cgRect, options, kCGNullWindowID, [.bestResolution, .nominalResolution]) {
                let screenSize = CGSize(width: cgImage.width, height: cgImage.height)
                let nsImage = NSImage(cgImage: cgImage, size: screenSize)
                
                Logger.info("✅ Immediate screenshot successful using strategy \(strategyName): \(cgImage.width)x\(cgImage.height)")
                
                // For immediate capture, we'll take the first successful capture
                // since timing is critical for hotkey responsiveness
                return nsImage
            } else {
                Logger.warn("❌ Immediate capture strategy \(strategyName) failed")
            }
        }
        
        Logger.error("❌ All immediate capture strategies failed")
        return nil
    }

    private func captureScreenUsingDisplayImageImmediate() -> NSImage? {
        guard let displayID = CGMainDisplayID() as CGDirectDisplayID? else {
            Logger.error("❌ Failed to get main display ID")
            return nil
        }

        guard let cgImage = CGDisplayCreateImage(displayID) else {
            Logger.error("❌ Failed to create display image")
            return nil
        }

        let screenSize = CGSize(width: cgImage.width, height: cgImage.height)
        let nsImage = NSImage(cgImage: cgImage, size: screenSize)

        Logger.info("✅ Captured immediate screenshot using CGDisplayCreateImage: \(cgImage.width)x\(cgImage.height)")
        return nsImage
    }

    // Main method triggered by hotkey with pre-captured screenshot
    private func triggerScreenshotTranslationWithPreCapture(_ preCapture: NSImage) {
        Logger.info("Screenshot translation triggered with pre-captured image")

        // Check if user is authenticated
        guard SessionManager.shared.isAuthenticated else {
            Logger.warn("User not authenticated, showing login prompt")
            showAuthenticationRequiredDialog()
            return
        }

        // Use the pre-captured image to ensure no selection overlay borders are included
        // This ensures we get the clean screen state from before the overlay was shown
        ScreenshotManager.shared.captureScreenshotWithSelectionUsingPreCapture(preCapture) { [weak self] image in
            // Always reset the screenshot flag when selection is complete
            self?.isScreenshotInProgress = false

            guard let image = image else {
                Logger.info("Screenshot selection cancelled or failed")
                return
            }

            self?.handleScreenshotCaptured(image)
        }
    }

    // Legacy method for backward compatibility
    private func triggerScreenshotTranslation() {
        Logger.info("Screenshot translation triggered by hotkey")

        // Check if user is authenticated
        guard SessionManager.shared.isAuthenticated else {
            Logger.warn("User not authenticated, showing login prompt")
            showAuthenticationRequiredDialog()
            return
        }

        // Start screenshot capture
        ScreenshotManager.shared.captureScreenshotWithSelection { [weak self] image in
            guard let image = image else {
                Logger.info("Screenshot capture cancelled or failed")
                return
            }

            self?.handleScreenshotCaptured(image)
        }
    }

    private func handleScreenshotCaptured(_ image: NSImage) {
        Logger.info("Screenshot captured successfully, processing for translation")

        // Save image locally
        let savedImageURL = ScreenshotManager.shared.saveImageToLocal(image)

        // Convert to base64 for API
        guard let base64String = ScreenshotManager.shared.convertImageToBase64(image) else {
            Logger.error("Failed to convert image to base64")
            showErrorDialog("Failed to process screenshot image")
            return
        }

        // Show translation window
        showImageTranslationWindow(image: image, base64Data: base64String, savedImageURL: savedImageURL)
    }

    private func showImageTranslationWindow(image: NSImage, base64Data: String, savedImageURL: URL?) {
        // Close existing translation window if any
        translationWindow?.close()

        // Create new translation window
        translationWindow = ImageTranslationWindow(
            image: image,
            base64Data: base64Data,
            savedImageURL: savedImageURL
        )

        // Set up callback to save to history when translation completes
        if let windowData = translationWindow?.imageTranslationData {
            // Monitor for translation completion to save to history
            let observation = windowData.$translationResult.sink { [weak self] result in
                if !result.isEmpty {
                    // Save successful translation to history
                    ImageTranslationHistoryManager.shared.addImageTranslation(
                        image: image,
                        originalBase64: base64Data,
                        translationResult: result,
                        targetLanguage: windowData.selectedTargetLanguage,
                        savedImageURL: savedImageURL
                    )
                }
            }

            // Store observation to keep it alive (this is a simplified approach)
            objc_setAssociatedObject(translationWindow!, "translationObserver", observation, .OBJC_ASSOCIATION_RETAIN)
        }

        translationWindow?.makeKeyAndOrderFront(nil)
        Logger.info("Image translation window displayed")
    }

    private func showAuthenticationRequiredDialog() {
        let alert = NSAlert()
        alert.messageText = "Authentication Required"
        alert.informativeText = "Please sign in to use the screenshot translation feature."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Sign In")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Trigger login flow
            NotificationCenter.default.post(name: .showLogin, object: nil)
        }
    }

    private func showErrorDialog(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Screenshot Translation Error"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    // Reload hotkey settings and reset the global monitor
    func reloadHotkeySettings() {
        Logger.info("🔄 Reloading screenshot hotkey settings...")
        setupScreenshotHotkey()
    }

    // Public cleanup method for manual cleanup if needed
    func cleanup() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
            Logger.info("🧹 Screenshot hotkey global monitor manually removed")
        }

        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
            Logger.info("🧹 Screenshot hotkey local monitor manually removed")
        }

        // Close any existing translation window
        translationWindow?.close()
        translationWindow = nil

        // Reset screenshot progress flag
        isScreenshotInProgress = false

        // Force cleanup of screenshot manager
        ScreenshotManager.shared.cleanup()
    }

    // Force reset all window states (emergency function)
    func forceResetWindowStates() {
        Logger.warn("🚨 Force resetting all window states...")

        // Reset our internal state
        isScreenshotInProgress = false

        // Force cleanup screenshot manager
        ScreenshotManager.shared.cleanup()

        // Ensure all Glotera windows are at normal level
        for window in NSApp.windows {
            if window.title.contains("Glotera") || window.title.contains("Image Translation") {
                window.level = .normal
                Logger.info("Reset window level for: \(window.title)")
            }
        }

        // Force application to resign any elevated privileges
        NSApp.deactivate()

        Logger.info("✅ Window states reset complete")
    }
    
    // MARK: - Debug Methods
    
    /// Test the immediate screenshot capture and save to desktop for debugging
    func testImmediateScreenshotCapture() {
        Logger.info("🧪 Testing immediate screenshot capture (same as hotkey trigger)...")
        
        guard let immediateScreenshot = captureScreenImmediately() else {
            Logger.error("❌ Failed to capture immediate screenshot")
            return
        }
        
        // Save to desktop for inspection
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let testFileURL = desktopURL.appendingPathComponent("glotera_immediate_capture_test.png")
        
        guard let tiffData = immediateScreenshot.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            Logger.error("❌ Failed to convert immediate screenshot to PNG")
            return
        }
        
        do {
            try pngData.write(to: testFileURL)
            Logger.info("✅ Immediate capture test saved to: \(testFileURL.path)")
            Logger.info("📊 Image size: \(immediateScreenshot.size.width) x \(immediateScreenshot.size.height)")
        } catch {
            Logger.error("❌ Failed to save immediate capture test: \(error)")
        }
    }
    
    /// Test the full screenshot workflow without showing UI
    func testFullScreenshotWorkflow() {
        Logger.info("🔄 Testing full screenshot workflow...")
        
        // Capture immediate screenshot (like hotkey does)
        guard let preCapture = captureScreenImmediately() else {
            Logger.error("❌ Failed to capture pre-screenshot")
            return
        }
        
        // Test what ScreenshotManager would do with this image
        Logger.info("📊 Pre-capture size: \(preCapture.size.width) x \(preCapture.size.height)")
        
        // Save the pre-capture for comparison with unique name
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let preTestFileURL = desktopURL.appendingPathComponent("glotera_workflow_precapture_\(timestamp).png")

        if let tiffData = preCapture.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            try? pngData.write(to: preTestFileURL)
            Logger.info("✅ Pre-capture saved to: \(preTestFileURL.path)")
        }

        // Also test what the ScreenshotManager's captureFullScreen would return
        if let fullScreenCapture = ScreenshotManager.shared.captureFullScreen() {
            let fullTestFileURL = desktopURL.appendingPathComponent("glotera_workflow_fullscreen_\(timestamp).png")
            
            if let tiffData = fullScreenCapture.tiffRepresentation,
               let bitmapRep = NSBitmapImageRep(data: tiffData),
               let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                try? pngData.write(to: fullTestFileURL)
                Logger.info("✅ ScreenshotManager full capture saved to: \(fullTestFileURL.path)")
                Logger.info("📊 Full capture size: \(fullScreenCapture.size.width) x \(fullScreenCapture.size.height)")
            }
        }
    }

    deinit {
        // Remove global monitor when manager is deallocated
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            Logger.info("🧹 Screenshot hotkey global monitor removed successfully")
        }
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let showLogin = Notification.Name("showLogin")
}