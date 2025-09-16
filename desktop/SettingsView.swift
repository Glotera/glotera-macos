import SwiftUI

struct SettingsView: View {
    @State private var screenshotHotkeyKey: String = "S"
    @State private var screenshotHotkeyUseCmd: Bool = true
    @State private var screenshotHotkeyUseShift: Bool = true
    @State private var screenshotHotkeyUseOption: Bool = false
    @State private var screenshotHotkeyUseControl: Bool = false

    var body: some View {
        Form {
            // Language Settings Section
            Section(header: Text("Language Settings").font(.headline)) {
                Text("Language configuration will be expanded here")
                    .foregroundColor(.secondary)
            }

            // Hotkey Settings Section
            Section(header: Text("Screenshot Translation Hotkey").font(.headline)) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Customize the hotkey combination to trigger screenshot translation")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Modifier keys
                    HStack {
                        Text("Modifiers:")

                        Toggle("⌘ Cmd", isOn: $screenshotHotkeyUseCmd)
                            .toggleStyle(CheckboxToggleStyle())

                        Toggle("⇧ Shift", isOn: $screenshotHotkeyUseShift)
                            .toggleStyle(CheckboxToggleStyle())

                        Toggle("⌥ Option", isOn: $screenshotHotkeyUseOption)
                            .toggleStyle(CheckboxToggleStyle())

                        Toggle("⌃ Control", isOn: $screenshotHotkeyUseControl)
                            .toggleStyle(CheckboxToggleStyle())
                    }

                    // Key selection
                    HStack {
                        Text("Key:")
                        Picker("Key", selection: $screenshotHotkeyKey) {
                            ForEach(availableKeys, id: \.self) { key in
                                Text(key).tag(key)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 100)
                    }

                    // Current hotkey display
                    HStack {
                        Text("Current combination:")
                        Text(currentHotkeyDescription)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }

                    // Apply button
                    Button("Apply Hotkey") {
                        applyHotkeySettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValidHotkeyConfiguration)
                }
                .padding(.vertical, 8)
            }

            // Startup Settings Section
            Section(header: Text("Startup Settings").font(.headline)) {
                Text("Startup settings will be expanded here")
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 500, height: 450)
        .onAppear {
            loadCurrentSettings()
        }
    }

    private var availableKeys: [String] {
        ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"]
    }

    private var currentHotkeyDescription: String {
        var components: [String] = []
        if screenshotHotkeyUseControl { components.append("⌃") }
        if screenshotHotkeyUseOption { components.append("⌥") }
        if screenshotHotkeyUseShift { components.append("⇧") }
        if screenshotHotkeyUseCmd { components.append("⌘") }
        components.append(screenshotHotkeyKey)
        return components.joined(separator: "")
    }

    private var isValidHotkeyConfiguration: Bool {
        // At least one modifier key should be selected
        return screenshotHotkeyUseCmd || screenshotHotkeyUseShift || screenshotHotkeyUseOption || screenshotHotkeyUseControl
    }

    private func loadCurrentSettings() {
        // Load current hotkey settings from UserDefaults or ConfigManager
        let settings = ConfigManager.shared.loadAppSettings()

        // Load screenshot hotkey settings (with defaults)
        screenshotHotkeyKey = UserDefaults.standard.string(forKey: "screenshot_hotkey_key") ?? "S"
        screenshotHotkeyUseCmd = UserDefaults.standard.bool(forKey: "screenshot_hotkey_cmd") || UserDefaults.standard.object(forKey: "screenshot_hotkey_cmd") == nil // Default to true
        screenshotHotkeyUseShift = UserDefaults.standard.bool(forKey: "screenshot_hotkey_shift") || UserDefaults.standard.object(forKey: "screenshot_hotkey_shift") == nil // Default to true
        screenshotHotkeyUseOption = UserDefaults.standard.bool(forKey: "screenshot_hotkey_option")
        screenshotHotkeyUseControl = UserDefaults.standard.bool(forKey: "screenshot_hotkey_control")

        Logger.info("Loaded hotkey settings: \(currentHotkeyDescription)")
    }

    private func applyHotkeySettings() {
        guard isValidHotkeyConfiguration else {
            Logger.warn("Invalid hotkey configuration, at least one modifier required")
            return
        }

        // Save settings to UserDefaults
        UserDefaults.standard.set(screenshotHotkeyKey, forKey: "screenshot_hotkey_key")
        UserDefaults.standard.set(screenshotHotkeyUseCmd, forKey: "screenshot_hotkey_cmd")
        UserDefaults.standard.set(screenshotHotkeyUseShift, forKey: "screenshot_hotkey_shift")
        UserDefaults.standard.set(screenshotHotkeyUseOption, forKey: "screenshot_hotkey_option")
        UserDefaults.standard.set(screenshotHotkeyUseControl, forKey: "screenshot_hotkey_control")

        // TODO: Implement hotkey update once HotkeyManager is added to Xcode project
        // For now, just save the settings
        Logger.info("Hotkey settings saved - implementation pending project integration")

        Logger.info("Applied new hotkey settings: \(currentHotkeyDescription)")

        // Show success feedback
        showHotkeyUpdateSuccess()
    }

    private func showHotkeyUpdateSuccess() {
        // Simple success indication - you could expand this with a toast notification
        let alert = NSAlert()
        alert.messageText = "Hotkey Updated"
        alert.informativeText = "Screenshot translation hotkey has been updated to: \(currentHotkeyDescription)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// Custom checkbox style for toggle buttons
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: {
            configuration.isOn.toggle()
        }) {
            HStack {
                Image(systemName: configuration.isOn ? "checkbox.square.fill" : "square")
                    .foregroundColor(configuration.isOn ? .accentColor : .secondary)
                configuration.label
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
} 