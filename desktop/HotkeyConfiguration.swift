import Cocoa
import Foundation

// MARK: - Hotkey Configuration Models
struct HotkeyConfiguration: Codable {
    let keyCode: UInt32
    let modifiers: NSEvent.ModifierFlags
    let displayName: String

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, displayName: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayName = displayName
    }

    // Custom coding keys to handle NSEvent.ModifierFlags
    enum CodingKeys: String, CodingKey {
        case keyCode
        case modifiers
        case displayName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(UInt32.self, forKey: .keyCode)
        let modifierRawValue = try container.decode(UInt.self, forKey: .modifiers)
        modifiers = NSEvent.ModifierFlags(rawValue: modifierRawValue)
        displayName = try container.decode(String.self, forKey: .displayName)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifiers.rawValue, forKey: .modifiers)
        try container.encode(displayName, forKey: .displayName)
    }

    // Check if this hotkey matches the given event
    func matches(event: NSEvent) -> Bool {
        let eventKeyCode = event.keyCode
        let eventModifiers = event.modifierFlags

        // Check key code
        guard eventKeyCode == keyCode else { return false }

        // Check modifiers (only care about command, option, shift, control)
        let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
        let expectedModifiers = modifiers.intersection(relevantModifiers)
        let actualModifiers = eventModifiers.intersection(relevantModifiers)

        return expectedModifiers == actualModifiers
    }
}

// MARK: - Hotkey Configuration Manager
class HotkeyConfigurationManager: ObservableObject {
    static let shared = HotkeyConfigurationManager()

    // Default hotkey configurations
    private let defaultConfigurations: [String: HotkeyConfiguration] = [
        "screenshot_translation": HotkeyConfiguration(
            keyCode: 1, // 'S' key
            modifiers: [.shift, .option],
            displayName: "Shift+Option+S"
        )
    ]

    private let userDefaultsKey = "glotera_hotkey_configurations"
    private var customConfigurations: [String: HotkeyConfiguration] = [:]

    private init() {
        loadCustomConfigurations()
    }

    // MARK: - Public Interface

    /// Get hotkey configuration for a specific action
    func getConfiguration(for action: String) -> HotkeyConfiguration? {
        // First check custom configurations, then fall back to defaults
        return customConfigurations[action] ?? defaultConfigurations[action]
    }

    /// Set custom hotkey configuration for a specific action
    func setConfiguration(for action: String, configuration: HotkeyConfiguration) {
        customConfigurations[action] = configuration
        saveCustomConfigurations()

        Logger.info("Updated hotkey configuration for \(action): \(configuration.displayName)")

        // Post notification for hotkey changes
        NotificationCenter.default.post(
            name: .hotkeyConfigurationChanged,
            object: nil,
            userInfo: ["action": action, "configuration": configuration]
        )
    }

    /// Reset hotkey configuration to default for a specific action
    func resetToDefault(for action: String) {
        customConfigurations.removeValue(forKey: action)
        saveCustomConfigurations()

        Logger.info("Reset hotkey configuration for \(action) to default")

        // Post notification for hotkey changes
        if let defaultConfig = defaultConfigurations[action] {
            NotificationCenter.default.post(
                name: .hotkeyConfigurationChanged,
                object: nil,
                userInfo: ["action": action, "configuration": defaultConfig]
            )
        }
    }

    /// Get all available actions
    func getAllActions() -> [String] {
        let allActions = Set(defaultConfigurations.keys).union(Set(customConfigurations.keys))
        return Array(allActions).sorted()
    }

    /// Check if a hotkey configuration conflicts with existing ones
    func hasConflict(configuration: HotkeyConfiguration, excludingAction: String? = nil) -> String? {
        for (action, existingConfig) in getAllConfigurations() {
            if let excludingAction = excludingAction, action == excludingAction {
                continue
            }

            if existingConfig.keyCode == configuration.keyCode &&
               existingConfig.modifiers == configuration.modifiers {
                return action
            }
        }
        return nil
    }

    /// Get all current configurations (custom + default)
    func getAllConfigurations() -> [String: HotkeyConfiguration] {
        var allConfigs = defaultConfigurations
        for (action, config) in customConfigurations {
            allConfigs[action] = config
        }
        return allConfigs
    }

    // MARK: - Persistence

    private func loadCustomConfigurations() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            Logger.debug("No custom hotkey configurations found")
            return
        }

        do {
            customConfigurations = try JSONDecoder().decode([String: HotkeyConfiguration].self, from: data)
            Logger.info("Loaded \(customConfigurations.count) custom hotkey configurations")
        } catch {
            Logger.error("Failed to load custom hotkey configurations: \(error)")
            customConfigurations = [:]
        }
    }

    private func saveCustomConfigurations() {
        do {
            let data = try JSONEncoder().encode(customConfigurations)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            Logger.debug("Saved \(customConfigurations.count) custom hotkey configurations")
        } catch {
            Logger.error("Failed to save custom hotkey configurations: \(error)")
        }
    }
}

// MARK: - Helper Extensions

extension NSEvent.ModifierFlags {
    /// Convert modifier flags to human-readable string
    var displayString: String {
        var components: [String] = []

        if contains(.control) { components.append("Ctrl") }
        if contains(.option) { components.append("Option") }
        if contains(.shift) { components.append("Shift") }
        if contains(.command) { components.append("Cmd") }

        return components.joined(separator: "+")
    }

    /// Create modifier flags from individual booleans
    static func from(control: Bool = false, option: Bool = false, shift: Bool = false, command: Bool = false) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if control { flags.insert(.control) }
        if option { flags.insert(.option) }
        if shift { flags.insert(.shift) }
        if command { flags.insert(.command) }
        return flags
    }
}

// MARK: - Key Code Utilities

class KeyCodeHelper {
    /// Common key codes mapping
    static let keyCodes: [String: UInt32] = [
        "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7, "C": 8, "V": 9,
        "B": 11, "Q": 12, "W": 13, "E": 14, "R": 15, "Y": 16, "T": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "O": 31, "U": 32, "[": 33, "I": 34, "P": 35,
        "RETURN": 36, "L": 37, "J": 38, "'": 39, "K": 40, ";": 41, "\\": 42, ",": 43,
        "/": 44, "N": 45, "M": 46, ".": 47, "TAB": 48, "SPACE": 49, "`": 50, "DELETE": 51,
        "ESCAPE": 53, "F1": 122, "F2": 120, "F3": 99, "F4": 118, "F5": 96, "F6": 97,
        "F7": 98, "F8": 100, "F9": 101, "F10": 109, "F11": 103, "F12": 111,
        "LEFT": 123, "RIGHT": 124, "DOWN": 125, "UP": 126
    ]

    /// Reverse mapping from key code to key name
    static let keyNames: [UInt32: String] = {
        var reversed: [UInt32: String] = [:]
        for (name, code) in keyCodes {
            reversed[code] = name
        }
        return reversed
    }()

    /// Get key name from key code
    static func keyName(for keyCode: UInt32) -> String {
        return keyNames[keyCode] ?? "Unknown(\(keyCode))"
    }

    /// Get key code from key name
    static func keyCode(for keyName: String) -> UInt32? {
        return keyCodes[keyName.uppercased()]
    }

    /// Create display name for hotkey configuration
    static func createDisplayName(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) -> String {
        let keyName = self.keyName(for: keyCode)
        let modifierString = modifiers.displayString

        if modifierString.isEmpty {
            return keyName
        } else {
            return "\(modifierString)+\(keyName)"
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let hotkeyConfigurationChanged = Notification.Name("hotkeyConfigurationChanged")
}

// MARK: - Hotkey Actions

/// Enum defining all available hotkey actions
enum HotkeyAction: String, CaseIterable {
    case screenshotTranslation = "screenshot_translation"

    var displayName: String {
        switch self {
        case .screenshotTranslation:
            return "Screenshot Translation"
        }
    }

    var description: String {
        switch self {
        case .screenshotTranslation:
            return "Capture screenshot and translate text within it"
        }
    }
}