import Cocoa
import Carbon

class HotkeyManager: NSObject {
    static let shared = HotkeyManager()

    private var hotkeyRefs: [EventHotKeyRef?] = []
    private var hotkeyCallbacks: [UInt32: () -> Void] = [:]
    private var nextHotkeyID: UInt32 = 1000

    override init() {
        super.init()
        Logger.info("🔧 Initializing HotkeyManager...")
        setupEventHandler()
    }

    private func setupEventHandler() {
        Logger.info("🔧 Setting up Carbon event handler for hotkeys...")
        let eventSpec = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        ]

        let status = InstallEventHandler(GetApplicationEventTarget(),
                          { (nextHandler, event, userData) -> OSStatus in
                              guard let event = event else { return OSStatus(eventNotHandledErr) }
                              return HotkeyManager.shared.handleHotkeyEvent(event: event)
                          },
                          1,
                          eventSpec,
                          nil,
                          nil)

        if status == noErr {
            Logger.info("✅ Carbon event handler installed successfully")
        } else {
            Logger.error("❌ Failed to install Carbon event handler with status: \(status)")
        }
    }

    private func handleHotkeyEvent(event: EventRef) -> OSStatus {
        var hotkeyID = EventHotKeyID()
        GetEventParameter(event,
                         EventParamName(kEventParamDirectObject),
                         EventParamType(typeEventHotKeyID),
                         nil,
                         MemoryLayout<EventHotKeyID>.size,
                         nil,
                         &hotkeyID)

        let id = hotkeyID.id
        if let callback = hotkeyCallbacks[id] {
            DispatchQueue.main.async {
                callback()
            }
        }

        return noErr
    }

    @discardableResult
    func registerHotkey(keyCode: UInt32, modifiers: UInt32, callback: @escaping () -> Void) -> UInt32? {
        Logger.info("🔑 Attempting to register hotkey - keyCode: \(keyCode), modifiers: \(modifiers)")

        let hotkeyID = EventHotKeyID(signature: OSType(kEventClassKeyboard), id: nextHotkeyID)
        var hotkeyRef: EventHotKeyRef?

        let status = RegisterEventHotKey(keyCode,
                                       modifiers,
                                       hotkeyID,
                                       GetApplicationEventTarget(),
                                       0,
                                       &hotkeyRef)

        if status == noErr, let ref = hotkeyRef {
            hotkeyRefs.append(ref)
            hotkeyCallbacks[nextHotkeyID] = callback
            let registeredID = nextHotkeyID
            nextHotkeyID += 1

            Logger.info("✅ Successfully registered hotkey with ID: \(registeredID), keyCode: \(keyCode), modifiers: \(modifiers)")
            return registeredID
        } else {
            Logger.error("❌ Failed to register hotkey with status: \(status) (keyCode: \(keyCode), modifiers: \(modifiers))")
            return nil
        }
    }

    func unregisterHotkey(_ hotkeyID: UInt32) {
        hotkeyCallbacks.removeValue(forKey: hotkeyID)
        Logger.info("Unregistered hotkey with ID: \(hotkeyID)")
    }

    func unregisterAllHotkeys() {
        for hotkeyRef in hotkeyRefs {
            if let ref = hotkeyRef {
                UnregisterEventHotKey(ref)
            }
        }
        hotkeyRefs.removeAll()
        hotkeyCallbacks.removeAll()
        Logger.info("Unregistered all hotkeys")
    }

    // Helper method to register screenshot translation hotkey (Shift+Option+S)
    func registerScreenshotTranslationHotkey(callback: @escaping () -> Void) -> UInt32? {
        // Key code for 'S' is 1, Shift+Option modifiers
        let keyCode: UInt32 = 1 // 'S' key
        let modifiers: UInt32 = UInt32(shiftKey | optionKey)

        Logger.info("Registering screenshot hotkey with Carbon: Shift+Option+S")
        return registerHotkey(keyCode: keyCode, modifiers: modifiers, callback: callback)
    }

    // Helper method to register custom hotkey from settings
    func registerCustomHotkey(keyCode: UInt32, useCmd: Bool, useShift: Bool, useOption: Bool, useControl: Bool, callback: @escaping () -> Void) -> UInt32? {
        var modifiers: UInt32 = 0
        if useCmd { modifiers |= UInt32(cmdKey) }
        if useShift { modifiers |= UInt32(shiftKey) }
        if useOption { modifiers |= UInt32(optionKey) }
        if useControl { modifiers |= UInt32(controlKey) }

        return registerHotkey(keyCode: keyCode, modifiers: modifiers, callback: callback)
    }
}

// MARK: - Key code constants for common keys
extension HotkeyManager {
    static let keyCodes: [String: UInt32] = [
        "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7, "C": 8, "V": 9, "B": 11, "Q": 12, "W": 13, "E": 14, "R": 15, "Y": 16, "T": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "O": 31, "U": 32, "[": 33, "I": 34, "P": 35, "RETURN": 36, "L": 37, "J": 38, "'": 39, "K": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "N": 45, "M": 46, ".": 47, "TAB": 48, "SPACE": 49, "`": 50, "DELETE": 51, "ESCAPE": 53, "F17": 64, "F18": 79, "F19": 80, "F20": 90, "F5": 96, "F6": 97, "F7": 98, "F3": 99, "F8": 100, "F9": 101, "F11": 103, "F13": 105, "F16": 106, "F14": 107, "F10": 109, "F12": 111, "F15": 113, "HELP": 114, "HOME": 115, "PGUP": 116, "DELETE_FORWARD": 117, "F4": 118, "END": 119, "F2": 120, "PGDN": 121, "F1": 122, "LEFT": 123, "RIGHT": 124, "DOWN": 125, "UP": 126
    ]
}