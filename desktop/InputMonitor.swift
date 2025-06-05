import Cocoa
import Carbon

class InputMonitor {
    private var eventTap: CFMachPort?
    private let triggerPattern = #"(.*?)[@#](id|en|zh|ja|jp|ko|fr|de|es|ru|th)\s*$"#
    private let regex: NSRegularExpression

    init() {
        regex = try! NSRegularExpression(pattern: triggerPattern, options: .caseInsensitive)
    }

    func startMonitoringAndReturnEventTap() -> CFMachPort? {
        print("[LOG] InputMonitor startMonitoring called")
        
        // Check accessibility permissions first
        if !checkAccessibilityPermissions() {
            print("[LOG] Accessibility permissions not granted")
            requestAccessibilityPermissions()
            return nil
        }
        
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                if type == .keyDown {
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    if keyCode == kVK_Space { // 空格键
                        DispatchQueue.main.async {
                            InputMonitor.shared.handleSpaceKey()
                        }
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        )
        
        if eventTap == nil {
            print("[LOG] Failed to create event tap - this usually indicates:")
            print("[LOG] 1. Accessibility permissions not granted")
            print("[LOG] 2. App Sandbox restrictions")
            print("[LOG] 3. System security settings blocking access")
        }
        
        return eventTap
    }
    
    private func checkAccessibilityPermissions() -> Bool {
        let trusted = AXIsProcessTrusted()
        print("[LOG] Accessibility permission check result: \(trusted)")
        
        if !trusted {
            // 获取当前应用的Bundle ID和路径以便调试
            if let bundleId = Bundle.main.bundleIdentifier {
                print("[LOG] Current Bundle ID: \(bundleId)")
            }
            let bundlePath = Bundle.main.bundlePath
            print("[LOG] Current Bundle Path: \(bundlePath)")
        }
        
        return trusted
    }
    
    private func requestAccessibilityPermissions() {
        print("[LOG] Requesting accessibility permissions...")
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let result = AXIsProcessTrustedWithOptions(options as CFDictionary)
        print("[LOG] Permission request result: \(result)")
    }

    static let shared = InputMonitor()

    func handleSpaceKey() {
        print("[LOG] Space key detected")
        guard let (text, lang) = AXController.shared.detectTriggerAndExtract() else {
            print("[LOG] No trigger detected in input")
            return
        }
        print("[LOG] Trigger detected: text=\(text), lang=\(lang)")
        TranslatorClient.shared.translate(text: text, to: lang) { translated in
            print("[LOG] Translation result: \(translated ?? "nil")")
            if let translated = translated {
                AXController.shared.replaceInput(with: translated)
            }
        }
    }
} 