import Cocoa
import Foundation
import Combine

class ScreenshotTranslationManager: NSObject {
    static let shared = ScreenshotTranslationManager()

    private var globalMonitor: Any?
    private var translationWindow: ImageTranslationWindow?
    private var isScreenshotInProgress = false
    override init() {
        super.init()
        Logger.info("📸 Initializing ScreenshotTranslationManager...")
        setupScreenshotHotkey()
    }

    // Setup screenshot hotkey (Shift+Option+S) using modern NSEvent
    private func setupScreenshotHotkey() {
        Logger.info("🔑 Setting up screenshot hotkey (Shift+Option+S) using NSEvent...")

        // Remove existing monitor if any
        if let existingMonitor = globalMonitor {
            NSEvent.removeMonitor(existingMonitor)
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        if globalMonitor != nil {
            Logger.info("✅ NSEvent global monitor installed successfully for screenshot hotkey: Shift+Option+S")
        } else {
            Logger.error("❌ Failed to install NSEvent global monitor for screenshot hotkey")
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

        // Check for Shift+Option+S (keyCode 1 for 'S')
        if keyCode == 1 && modifierFlags.contains([.shift, .option]) {
            // Make sure we don't have other modifiers (like Ctrl or Cmd)
            let relevantModifiers = modifierFlags.intersection([.command, .shift, .control, .option])
            if relevantModifiers == [.shift, .option] {
                Logger.info("🚨 Shift+Option+S detected - IMMEDIATE screenshot capture!")

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

    // Public cleanup method for manual cleanup if needed
    func cleanup() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
            Logger.info("🧹 Screenshot hotkey global monitor manually removed")
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
        
        // Save the pre-capture for comparison
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let preTestFileURL = desktopURL.appendingPathComponent("glotera_workflow_precapture.png")
        
        if let tiffData = preCapture.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            try? pngData.write(to: preTestFileURL)
            Logger.info("✅ Pre-capture saved to: \(preTestFileURL.path)")
        }
        
        // Also test what the ScreenshotManager's captureFullScreen would return
        if let fullScreenCapture = ScreenshotManager.shared.captureFullScreen() {
            let fullTestFileURL = desktopURL.appendingPathComponent("glotera_workflow_fullscreen.png")
            
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