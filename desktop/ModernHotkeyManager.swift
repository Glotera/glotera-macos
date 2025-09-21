import Cocoa
import Carbon

class ModernHotkeyManager: NSObject {
    static let shared = ModernHotkeyManager()

    private var globalMonitor: Any?
    private var hotkeyCallbacks: [String: () -> Void] = [:]

    override init() {
        super.init()
        Logger.info("🚀 Initializing ModernHotkeyManager...")
        setupGlobalEventMonitoring()
    }

    private func setupGlobalEventMonitoring() {
        Logger.info("🔧 Setting up NSEvent global monitoring for hotkeys...")

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        if globalMonitor != nil {
            Logger.info("✅ NSEvent global monitor installed successfully")
        } else {
            Logger.error("❌ Failed to install NSEvent global monitor")
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let keyCode = event.keyCode
        let modifierFlags = event.modifierFlags

        // Check for Shift+Option+S (keyCode 1 for 'S')
        if keyCode == 1 && modifierFlags.contains([.shift, .option]) {
            // Make sure we don't have other modifiers (like Ctrl or Cmd)
            let relevantModifiers = modifierFlags.intersection([.command, .shift, .control, .option])
            if relevantModifiers == [.shift, .option] {
                Logger.info("🚨 Shift+Option+S detected!")

                if let callback = hotkeyCallbacks["screenshot"] {
                    DispatchQueue.main.async {
                        callback()
                    }
                }
            }
        }
    }

    func registerScreenshotHotkey(callback: @escaping () -> Void) -> Bool {
        Logger.info("🔑 Registering screenshot hotkey (Shift+Option+S)...")
        hotkeyCallbacks["screenshot"] = callback
        Logger.info("✅ Screenshot hotkey callback registered")
        return true
    }

    deinit {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            Logger.info("🧹 Global event monitor removed")
        }
    }
}

// MARK: - Modern Screenshot Translation Manager
class ModernScreenshotTranslationManager: NSObject {
    static let shared = ModernScreenshotTranslationManager()

    private var translationWindow: ImageTranslationWindow?

    override init() {
        super.init()
        Logger.info("📸 Initializing ModernScreenshotTranslationManager...")
        setupScreenshotHotkey()
    }

    private func setupScreenshotHotkey() {
        Logger.info("🔑 Setting up modern screenshot hotkey (Shift+Option+S)...")

        let success = ModernHotkeyManager.shared.registerScreenshotHotkey { [weak self] in
            Logger.info("🚨 Modern screenshot hotkey triggered!")
            self?.triggerScreenshotTranslation()
        }

        if success {
            Logger.info("✅ Modern screenshot translation hotkey registered successfully")
        } else {
            Logger.error("❌ Failed to register modern screenshot translation hotkey")
        }
    }

    private func triggerScreenshotTranslation() {
        Logger.info("📸 Screenshot translation triggered by modern hotkey")

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

        translationWindow?.makeKeyAndOrderFront(nil)
        Logger.info("Image translation window displayed")
    }

    private func showAuthenticationRequiredDialog() {
        DispatchQueue.main.async {
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
}