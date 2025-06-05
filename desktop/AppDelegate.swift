import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController!
    var inputMonitor: InputMonitor!
    var runLoopSource: CFRunLoopSource?
    var retryTimer: Timer?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        print("[LOG] AppDelegate did finish launching")
        menuBarController = MenuBarController()
        inputMonitor = InputMonitor()
        
        // Try to setup event monitoring
        setupEventMonitoring()
        
        // Setup a timer to retry if permissions are granted later (check every 5 seconds, max 10 times)
        var retryCount = 0
        retryTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] timer in
            retryCount += 1
            if retryCount > 10 {
                print("[LOG] Stopping retry attempts after 10 tries")
                timer.invalidate()
                return
            }
            self?.checkAndRetryEventMonitoring(timer)
        }
    }
    
    private func setupEventMonitoring() {
        let eventTap = inputMonitor.startMonitoringAndReturnEventTap()
        if let eventTap = eventTap {
            print("[LOG] Event tap created successfully")
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            self.runLoopSource = runLoopSource
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
            
            // Stop the retry timer since we're successful
            retryTimer?.invalidate()
            retryTimer = nil
        } else {
            print("[LOG] Failed to create event tap. Check Accessibility permissions and App Sandbox settings.")
            print("[LOG] Please grant Accessibility permissions in System Settings > Privacy & Security > Accessibility")
        }
    }
    
    private func checkAndRetryEventMonitoring(_ timer: Timer) {
        // If we don't have an event tap and permissions are now available, try again
        if runLoopSource == nil && AXIsProcessTrusted() {
            print("[LOG] Accessibility permissions granted, retrying event tap creation...")
            setupEventMonitoring()
            if runLoopSource != nil {
                print("[LOG] Event monitoring setup successful after retry")
                timer.invalidate() // Stop retrying once successful
            }
        }
    }
}