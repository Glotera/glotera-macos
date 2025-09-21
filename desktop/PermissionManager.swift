import Cocoa
import AVFoundation

class PermissionManager {
    static let shared = PermissionManager()

    // UserDefaults keys for user preferences
    private let kDontRemindScreenRecording = "dont_remind_screen_recording"
    private let kLastPermissionCheckDate = "last_permission_check_date"
    private let kPermissionCheckInterval: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    private let kHasShownInitialPermissionFlow = "has_shown_initial_permission_flow"

    private init() {}

    // MARK: - Public Methods

    /// Reset the permission flow (for testing purposes)
    func resetPermissionFlow() {
        Logger.info("🔄 Resetting permission flow...")
        UserDefaults.standard.set(false, forKey: kHasShownInitialPermissionFlow)
        UserDefaults.standard.set(false, forKey: kDontRemindScreenRecording)
        UserDefaults.standard.synchronize()
    }

    /// Check all required permissions on app startup
    func checkPermissionsOnStartup() {
        Logger.info("🔒 Checking app permissions on startup...")

        // Check current permission states
        let hasAccessibility = AXIsProcessTrustedWithOptions(nil)
        var hasScreenRecording = false
        if #available(macOS 10.15, *) {
            hasScreenRecording = CGPreflightScreenCaptureAccess()
        }

        Logger.info("📊 Accessibility: \(hasAccessibility ? "✅" : "❌"), Screen Recording: \(hasScreenRecording ? "✅" : "❌")")

        // Only show setup if any permission is missing
        if !hasAccessibility || !hasScreenRecording {
            showMinimalPermissionFlow(hasAccessibility: hasAccessibility, hasScreenRecording: hasScreenRecording)
        } else {
            Logger.info("✅ All permissions already granted")
        }
    }

    /// Check if screen recording permission is granted
    @available(macOS 10.15, *)
    func hasScreenRecordingPermission() -> Bool {
        // Use CGPreflightScreenCaptureAccess to check permission without triggering dialog
        // This method only checks current status, doesn't prompt
        let hasPermission = CGPreflightScreenCaptureAccess()

        if hasPermission {
            Logger.debug("✅ Screen recording permission is granted")
        } else {
            Logger.debug("❌ Screen recording permission is not granted")
        }

        return hasPermission
    }

    /// Check screen recording permission and show alert if needed
    func checkScreenRecordingPermission() {
        guard #available(macOS 10.15, *) else {
            Logger.info("Screen recording permission check skipped - macOS < 10.15")
            return
        }

        // Check if user has opted out of reminders
        if UserDefaults.standard.bool(forKey: kDontRemindScreenRecording) {
            Logger.info("User has opted out of screen recording permission reminders")

            // Still check periodically (every 7 days) in case user changes their mind
            if shouldCheckPermissionPeriodically() {
                if !hasScreenRecordingPermission() {
                    Logger.warn("Screen recording permission still not granted (user opted out of reminders)")
                }
            }
            return
        }

        // Check if permission is granted
        if !hasScreenRecordingPermission() {
            Logger.warn("Screen recording permission not granted - showing alert")
            DispatchQueue.main.async {
                self.showScreenRecordingPermissionDialog()
            }
        } else {
            Logger.info("✅ Screen recording permission already granted")
        }
    }

    /// Check accessibility permission
    func checkAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: false]
        let isAccessibilityEnabled = AXIsProcessTrustedWithOptions(options)

        if isAccessibilityEnabled {
            Logger.info("✅ Accessibility permission is granted")
        } else {
            Logger.warn("⚠️ Accessibility permission not granted - some features may not work properly")
            // We don't show an alert for accessibility as it's handled by the system
            // and the app can still function without it for basic features
        }
    }

    // MARK: - Permission Flow Methods

    /// Show minimal permission flow
    private func showMinimalPermissionFlow(hasAccessibility: Bool, hasScreenRecording: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Show a single explanation dialog
            let alert = NSAlert()
            alert.messageText = "Glotera Needs Your Permission"

            var infoText = ""
            if !hasAccessibility && !hasScreenRecording {
                infoText = """
                To provide translation services, Glotera needs:

                📝 Accessibility - Detect text selection and keyboard shortcuts
                📸 Screen Recording - Screenshot translation feature

                After clicking OK, the system will show permission dialogs.
                """
            } else if !hasAccessibility {
                infoText = """
                To provide translation services, Glotera needs:

                📝 Accessibility - Detect text selection and keyboard shortcuts

                After clicking OK, the system will show permission dialog.
                """
            } else if !hasScreenRecording {
                infoText = """
                To enable screenshot translation, Glotera needs:

                📸 Screen Recording Permission

                After clicking OK, the system will show permission dialog.
                """
            }

            alert.informativeText = infoText
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")

            if let appIcon = NSApp.applicationIconImage {
                alert.icon = appIcon
            }

            let response = alert.runModal()

            if response == .alertFirstButtonReturn {
                self.requestPermissionsAutomatically(needsAccessibility: !hasAccessibility, needsScreenRecording: !hasScreenRecording)
            } else {
                Logger.info("User cancelled permission setup")
            }
        }
    }

    /// Request permissions automatically with delay
    private func requestPermissionsAutomatically(needsAccessibility: Bool, needsScreenRecording: Bool) {
        if needsAccessibility {
            // Request accessibility permission immediately
            Logger.info("🔑 Requesting accessibility permission...")
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
            _ = AXIsProcessTrustedWithOptions(options)

            if needsScreenRecording {
                // Wait 30 seconds then request screen recording
                Logger.info("⏰ Will request screen recording permission in 30 seconds...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                    self?.requestScreenRecordingPermissionSilently()
                }
            }
        } else if needsScreenRecording {
            // Only need screen recording, request immediately
            requestScreenRecordingPermissionSilently()
        }
    }

    /// Request screen recording permission silently (just trigger system dialog)
    private func requestScreenRecordingPermissionSilently() {
        guard #available(macOS 10.15, *) else { return }

        Logger.info("📸 Requesting screen recording permission...")

        // Check if permission is already granted
        if CGPreflightScreenCaptureAccess() {
            Logger.info("✅ Screen recording permission already granted")
            return
        }

        // Trigger capture to show the system permission dialog
        // The system dialog will have its own "Open System Preferences" button
        // We don't need to open settings automatically
        let testRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        let options: CGWindowListOption = [.optionOnScreenOnly]
        _ = CGWindowListCreateImage(testRect, options, kCGNullWindowID, [])

        Logger.info("📸 Screen recording permission dialog triggered")
    }

    /// Legacy simplified permission flow (kept for compatibility)
    private func showSimplifiedPermissionFlow(hasAccessibility: Bool, hasScreenRecording: Bool) {
        // Just call the new minimal flow
        showMinimalPermissionFlow(hasAccessibility: hasAccessibility, hasScreenRecording: hasScreenRecording)
    }

    /// Legacy setup permissions sequentially (kept for compatibility)
    private func setupPermissionsSequentially(needsAccessibility: Bool, needsScreenRecording: Bool) {
        requestPermissionsAutomatically(needsAccessibility: needsAccessibility, needsScreenRecording: needsScreenRecording)
    }

    /// Legacy request screen recording permission (kept for compatibility)
    private func requestScreenRecordingPermission() {
        requestScreenRecordingPermissionSilently()
    }

    /// Check permissions silently without UI
    private func checkPermissionsSilently() {
        // Check screen recording silently
        if #available(macOS 10.15, *) {
            if !hasScreenRecordingPermission() {
                Logger.warn("Screen recording permission not granted")

                // Only show reminder if user hasn't opted out and enough time has passed
                if !UserDefaults.standard.bool(forKey: kDontRemindScreenRecording) {
                    if shouldCheckPermissionPeriodically() {
                        DispatchQueue.main.async {
                            self.showScreenRecordingPermissionDialog()
                        }
                    }
                }
            }
        }

        // Check accessibility silently
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: false]
        let isAccessibilityEnabled = AXIsProcessTrustedWithOptions(options)

        if !isAccessibilityEnabled {
            Logger.warn("⚠️ Accessibility permission not granted")
        }
    }

    /// Check screen recording with completion callback
    private func checkScreenRecordingPermissionWithCallback(completion: @escaping () -> Void) {
        guard #available(macOS 10.15, *) else {
            completion()
            return
        }

        if hasScreenRecordingPermission() {
            Logger.info("✅ Screen recording permission already granted")
            completion()
        } else {
            showScreenRecordingPermissionDialogWithCallback(completion: completion)
        }
    }

    /// Show screen recording dialog with callback
    private func showScreenRecordingPermissionDialogWithCallback(completion: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = """
        Step 1 of 2: Screen Recording Permission

        Glotera needs this to capture screenshots for translation.

        Please enable Screen Recording for Glotera in:
        System Settings > Privacy & Security > Screen Recording
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Skip This Step")

        if let appIcon = NSApp.applicationIconImage {
            alert.icon = appIcon
        }

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            openScreenRecordingSettings()

            // Show a waiting dialog
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.showWaitingForPermissionDialog(permissionType: "Screen Recording", completion: completion)
            }
        } else {
            completion()
        }
    }

    /// Check accessibility permission with callback (required)
    private func checkAccessibilityPermissionWithCallback(completion: @escaping () -> Void) {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: false]
        let isAccessibilityEnabled = AXIsProcessTrustedWithOptions(options)

        if isAccessibilityEnabled {
            Logger.info("✅ Accessibility permission already granted")
            completion()
        } else {
            showAccessibilityPermissionDialog(completion: completion)
        }
    }

    /// Show accessibility permission dialog (required)
    private func showAccessibilityPermissionDialog(completion: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
        Step 1: Accessibility Permission (REQUIRED)

        ⚠️ Glotera cannot function without this permission.

        This permission allows Glotera to:
        • Detect when you select text
        • Monitor keyboard shortcuts
        • Provide translation overlay

        When you click "Continue", a system dialog will appear.
        Please click "Open System Preferences" in that dialog.
        """
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Quit App")

        if let appIcon = NSApp.applicationIconImage {
            alert.icon = appIcon
        }

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            // Now trigger the system accessibility dialog
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
            _ = AXIsProcessTrustedWithOptions(options)

            // Show waiting dialog after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.showWaitingForAccessibilityPermission(completion: completion)
            }
        } else {
            // User chose to quit
            NSApp.terminate(nil)
        }
    }

    /// Wait for accessibility permission (required)
    private func showWaitingForAccessibilityPermission(completion: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "Waiting for Accessibility Permission"
        alert.informativeText = """
        Please grant Accessibility permission in System Settings.

        ⚠️ This permission is REQUIRED for Glotera to work.

        Important: After granting permission, you may need to restart Glotera for changes to take effect.

        Click "I've Granted Permission" after enabling it in System Settings.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "I've Granted Permission")
        alert.addButton(withTitle: "Open System Settings Again")
        alert.addButton(withTitle: "Quit App")

        if let appIcon = NSApp.applicationIconImage {
            alert.icon = appIcon
        }

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            // User says they granted permission
            // Check if permission was actually granted
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: false]
            let isEnabled = AXIsProcessTrustedWithOptions(options)

            if isEnabled {
                Logger.info("✅ Accessibility permission granted")
                completion()
            } else {
                // Permission might be granted but requires restart
                showRestartRequiredAlert()
            }

        case .alertSecondButtonReturn:
            // Open System Settings again
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
            // Show the waiting dialog again
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.showWaitingForAccessibilityPermission(completion: completion)
            }

        default:
            // User chose to quit
            NSApp.terminate(nil)
        }
    }

    /// Show restart required alert (no longer used in minimal flow)
    private func showRestartRequiredAlert() {
        // In the minimal flow, we don't show restart alerts
        // The app will just continue and permissions will work after restart
        Logger.info("Accessibility permission may require restart to take effect")
    }

    /// Restart the application
    private func restartApplication() {
        let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
        let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [path]
        task.launch()
        NSApp.terminate(nil)
    }

    /// Check screen recording permission (optional)
    private func checkScreenRecordingPermissionOptional() {
        guard #available(macOS 10.15, *) else {
            showSetupCompleteDialog()
            return
        }

        if hasScreenRecordingPermission() {
            Logger.info("✅ Screen recording permission already granted")
            showSetupCompleteDialog()
        } else {
            showOptionalScreenRecordingDialog()
        }
    }

    /// Show optional screen recording dialog
    private func showOptionalScreenRecordingDialog() {
        let alert = NSAlert()
        alert.messageText = "Optional: Screen Recording Permission"
        alert.informativeText = """
        Step 2: Screen Recording Permission (OPTIONAL)

        This permission enables the screenshot translation feature.

        You can:
        • Set it up now for full functionality
        • Skip and set it up later when needed
        • Continue without this feature

        Would you like to enable screenshot translation?
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Enable Screenshot Translation")
        alert.addButton(withTitle: "Skip for Now")
        alert.addButton(withTitle: "Don't Ask Again")

        if let appIcon = NSApp.applicationIconImage {
            alert.icon = appIcon
        }

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            // User wants to enable
            openScreenRecordingSettings()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.showWaitingForScreenRecordingPermission()
            }

        case .alertThirdButtonReturn:
            // Don't ask again
            UserDefaults.standard.set(true, forKey: kDontRemindScreenRecording)
            showSetupCompleteDialog()

        default:
            // Skip for now
            showSetupCompleteDialog()
        }
    }

    /// Wait for screen recording permission (optional)
    private func showWaitingForScreenRecordingPermission() {
        let alert = NSAlert()
        alert.messageText = "Setting Up Screen Recording"
        alert.informativeText = """
        Please grant Screen Recording permission in System Settings if you want to use screenshot translation.

        This is optional - you can continue without it.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Continue")

        if let appIcon = NSApp.applicationIconImage {
            alert.icon = appIcon
        }

        alert.runModal()
        showSetupCompleteDialog()
    }

    /// Check accessibility permission with UI (legacy method for compatibility)
    private func checkAccessibilityPermissionWithUI() {
        checkAccessibilityPermissionWithCallback {
            self.showSetupCompleteDialog()
        }
    }

    /// Show accessibility permission dialog (legacy method for compatibility)
    private func showAccessibilityPermissionDialog() {
        showAccessibilityPermissionDialog {
            self.showSetupCompleteDialog()
        }
    }

    /// Show waiting dialog while user grants permission
    private func showWaitingForPermissionDialog(permissionType: String, completion: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "Waiting for \(permissionType) Permission"
        alert.informativeText = """
        Please grant the \(permissionType) permission in System Settings.

        Once you've granted the permission, click Continue.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "I'll Do This Later")

        if let appIcon = NSApp.applicationIconImage {
            alert.icon = appIcon
        }

        alert.runModal()
        completion()
    }

    /// Show setup complete dialog
    private func showSetupCompleteDialog() {
        // Check what permissions were granted
        let hasAccessibility = AXIsProcessTrustedWithOptions(nil)
        var hasScreenRecording = false
        if #available(macOS 10.15, *) {
            hasScreenRecording = hasScreenRecordingPermission()
        }

        let alert = NSAlert()
        alert.messageText = "Setup Complete!"

        var infoText = "Glotera is now ready to use!\n\n"
        infoText += "✅ Accessibility: Granted\n"
        infoText += hasScreenRecording ? "✅ Screen Recording: Granted\n" : "⚠️ Screen Recording: Not granted (screenshot translation disabled)\n"
        infoText += "\nYou can start translating by:\n"
        infoText += "• Selecting text and pressing your hotkey\n"
        if hasScreenRecording {
            infoText += "• Taking screenshots for translation\n"
        }
        infoText += "• Using the menu bar options"

        alert.informativeText = infoText
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Get Started")

        if let appIcon = NSApp.applicationIconImage {
            alert.icon = appIcon
        }

        alert.runModal()
    }

    // MARK: - Private Methods

    private func shouldCheckPermissionPeriodically() -> Bool {
        guard let lastCheckDate = UserDefaults.standard.object(forKey: kLastPermissionCheckDate) as? Date else {
            // Never checked before
            UserDefaults.standard.set(Date(), forKey: kLastPermissionCheckDate)
            return true
        }

        let timeSinceLastCheck = Date().timeIntervalSince(lastCheckDate)
        if timeSinceLastCheck > kPermissionCheckInterval {
            UserDefaults.standard.set(Date(), forKey: kLastPermissionCheckDate)
            return true
        }

        return false
    }

    private func showScreenRecordingPermissionDialog() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = """
        Glotera needs Screen Recording permission to capture screenshots for translation.

        Without this permission, the screenshot translation feature will not work properly.

        Please enable Screen Recording for Glotera in:
        System Settings > Privacy & Security > Screen Recording
        """
        alert.alertStyle = .warning

        // Add buttons
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Remind Me Later")
        alert.addButton(withTitle: "Don't Remind Me Again")

        // Add icon
        if let appIcon = NSApp.applicationIconImage {
            alert.icon = appIcon
        }

        // Show alert and handle response
        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn: // Open System Settings
            openScreenRecordingSettings()
            Logger.info("User chose to open System Settings for Screen Recording")

        case .alertSecondButtonReturn: // Remind Me Later
            Logger.info("User chose to be reminded later about Screen Recording permission")
            // Will check again on next app launch

        case .alertThirdButtonReturn: // Don't Remind Me Again
            UserDefaults.standard.set(true, forKey: kDontRemindScreenRecording)
            Logger.info("User chose not to be reminded about Screen Recording permission")
            showDontRemindConfirmation()

        default:
            break
        }
    }

    private func showDontRemindConfirmation() {
        let alert = NSAlert()
        alert.messageText = "Reminder Disabled"
        alert.informativeText = """
        You won't be reminded about Screen Recording permission again.

        Note: Screenshot translation will not work without this permission.

        You can always enable it manually in:
        System Settings > Privacy & Security > Screen Recording
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")

        if let appIcon = NSApp.applicationIconImage {
            alert.icon = appIcon
        }

        alert.runModal()
    }

    private func openScreenRecordingSettings() {
        // Try the direct URL first (works on macOS 13+)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            // Fallback for older macOS versions
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Manual Permission Request

    /// Manually request screen recording permission (e.g., from menu)
    func requestScreenRecordingPermissionManually() {
        guard #available(macOS 10.15, *) else {
            showOldMacOSAlert()
            return
        }

        if hasScreenRecordingPermission() {
            showPermissionAlreadyGrantedAlert()
        } else {
            // Clear the "don't remind" preference if user manually requests
            UserDefaults.standard.set(false, forKey: kDontRemindScreenRecording)
            showScreenRecordingPermissionDialog()
        }
    }

    private func showOldMacOSAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission"
        alert.informativeText = "Screen recording permission is not required on macOS versions earlier than 10.15 (Catalina)."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showPermissionAlreadyGrantedAlert() {
        let alert = NSAlert()
        alert.messageText = "Permission Already Granted"
        alert.informativeText = "Screen Recording permission is already granted. Screenshot translation should work properly."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")

        if let appIcon = NSApp.applicationIconImage {
            alert.icon = appIcon
        }

        alert.runModal()
    }

    // MARK: - Permission Status

    /// Get current permission status for display
    func getPermissionStatus() -> PermissionStatus {
        var status = PermissionStatus()

        // Check Screen Recording
        if #available(macOS 10.15, *) {
            status.screenRecording = hasScreenRecordingPermission()
        } else {
            status.screenRecording = true // Not required on older macOS
        }

        // Check Accessibility
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: false]
        status.accessibility = AXIsProcessTrustedWithOptions(options)

        // Check if user opted out of reminders
        status.dontRemindScreenRecording = UserDefaults.standard.bool(forKey: kDontRemindScreenRecording)

        return status
    }

    struct PermissionStatus {
        var screenRecording: Bool = false
        var accessibility: Bool = false
        var dontRemindScreenRecording: Bool = false

        var allGranted: Bool {
            return screenRecording && accessibility
        }

        var summary: String {
            var items: [String] = []
            items.append("Screen Recording: \(screenRecording ? "✅" : "❌")")
            items.append("Accessibility: \(accessibility ? "✅" : "⚠️")")
            if dontRemindScreenRecording && !screenRecording {
                items.append("(Reminders disabled)")
            }
            return items.joined(separator: ", ")
        }
    }
}