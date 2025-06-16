import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController!
    var inputMonitor: InputMonitor!
    var runLoopSource: CFRunLoopSource?
    var retryTimer: Timer?
    var eventTap: CFMachPort?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        print("[LOG] AppDelegate did finish launching")
        menuBarController = MenuBarController()
        inputMonitor = InputMonitor()
        
        // Try to setup event monitoring
        setupEventMonitoring()
        
        // 启动选中文本监听
        AXController.shared.startSelectionMonitoring()
        
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
        
        // 添加应用生命周期监听
        setupApplicationLifecycleMonitoring()
    }
    
    private func setupApplicationLifecycleMonitoring() {
        // 监听应用进入后台和前台
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        
        // 监听系统唤醒
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWakeUp),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        
        print("[LOG] Application lifecycle monitoring setup complete")
    }
    
    @objc private func applicationDidBecomeActive() {
        print("[LOG] Application became active - checking event monitoring")
        // 应用变为活跃时检查事件监听状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.verifyEventMonitoring()
        }
    }
    
    @objc private func applicationDidResignActive() {
        print("[LOG] Application resigned active")
    }
    
    @objc private func systemDidWakeUp() {
        print("[LOG] System woke up - restarting event monitoring")
        // 系统唤醒后重新启动事件监听
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.restartEventMonitoringInternal()
        }
    }
    
    private func verifyEventMonitoring() {
        if let eventTap = eventTap {
            let isValid = CFMachPortIsValid(eventTap)
            print("[LOG] Event tap validity check: \(isValid)")
            if !isValid {
                print("[LOG] Event tap is invalid, restarting...")
                restartEventMonitoringInternal()
            }
        } else {
            print("[LOG] No event tap found, setting up...")
            setupEventMonitoring()
        }
    }
    
    public func restartEventMonitoring() {
        print("[LOG] Public restart method called")
        restartEventMonitoringInternal()
    }
    
    private func restartEventMonitoringInternal() {
        print("[LOG] Restarting event monitoring...")
        
        // 清理现有的监听
        cleanupEventMonitoring()
        
        // 等待一段时间后重新设置
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.setupEventMonitoring()
        }
    }
    
    private func cleanupEventMonitoring() {
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        
        print("[LOG] Event monitoring cleanup complete")
    }
    
    private func setupEventMonitoring() {
        let eventTap = inputMonitor.startMonitoringAndReturnEventTap()
        if let eventTap = eventTap {
            print("[LOG] Event tap created successfully")
            self.eventTap = eventTap
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            self.runLoopSource = runLoopSource
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
            
            // Stop the retry timer since we're successful
            retryTimer?.invalidate()
            retryTimer = nil
            
            print("[LOG] Event monitoring setup complete")
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
    
    func applicationWillTerminate(_ aNotification: Notification) {
        print("[LOG] Application will terminate - cleaning up")
        cleanupEventMonitoring()
        
        // 清理通知观察者
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}