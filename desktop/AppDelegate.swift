import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController!
    var inputMonitor: InputMonitor!
    var runLoopSource: CFRunLoopSource?
    var retryTimer: Timer?
    var eventTap: CFMachPort?
    
    // 添加状态跟踪
    private var isEventMonitoringActive = false

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
    
    // 添加 Event Tap 状态检查方法
    func isEventTapValid() -> Bool {
        guard let eventTap = eventTap else {
            return false
        }
        return CFMachPortIsValid(eventTap) && isEventMonitoringActive
    }
    
    // 添加获取事件监听状态的方法
    func getEventMonitoringStatus() -> (isActive: Bool, isValid: Bool, hasRunLoopSource: Bool) {
        let isValid = eventTap != nil && CFMachPortIsValid(eventTap!)
        let hasRunLoopSource = runLoopSource != nil
        return (isEventMonitoringActive, isValid, hasRunLoopSource)
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
        let status = getEventMonitoringStatus()
        print("[LOG] Event monitoring status - Active: \(status.isActive), Valid: \(status.isValid), HasRunLoopSource: \(status.hasRunLoopSource)")
        
        if !status.isValid || !status.hasRunLoopSource || !status.isActive {
            print("[LOG] Event monitoring verification failed, restarting...")
            restartEventMonitoringInternal()
        } else {
            print("[LOG] Event monitoring verification passed")
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
        print("[LOG] Cleaning up event monitoring...")
        
        // 标记为非活跃状态
        isEventMonitoringActive = false
        
        // 清理 RunLoop Source
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            self.runLoopSource = nil
            print("[LOG] RunLoop source removed")
        }
        
        // 清理 Event Tap
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
            print("[LOG] Event tap invalidated")
        }
        
        print("[LOG] Event monitoring cleanup complete")
    }
    
    private func setupEventMonitoring() {
        print("[LOG] Setting up event monitoring...")
        
        // Check accessibility permissions first
        if !AXIsProcessTrusted() {
            print("[LOG] Accessibility permissions not granted")
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            let result = AXIsProcessTrustedWithOptions(options as CFDictionary)
            print("[LOG] Permission request result: \(result)")
            return
        }
        
        // 创建事件监听器
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        let callback = inputMonitor.createEventTapCallback()
        
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: nil
        )
        
        if let eventTap = eventTap {
            print("[LOG] Event tap created successfully")
            
            // 创建 RunLoop 源
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            self.runLoopSource = runLoopSource
            
            // 添加到 RunLoop
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            print("[LOG] RunLoop source added")
            
            // 启用事件监听
            CGEvent.tapEnable(tap: eventTap, enable: true)
            print("[LOG] Event tap enabled")
            
            // 标记为活跃状态
            isEventMonitoringActive = true
            
            // Stop the retry timer since we're successful
            retryTimer?.invalidate()
            retryTimer = nil
            
            print("[LOG] Event monitoring setup complete")
        } else {
            print("[LOG] Failed to create event tap - this usually indicates:")
            print("[LOG] 1. Accessibility permissions not granted")
            print("[LOG] 2. App Sandbox restrictions")
            print("[LOG] 3. System security settings blocking access")
            print("[LOG] 4. Another app is already using event tapping")
            isEventMonitoringActive = false
        }
    }
    
    private func checkAndRetryEventMonitoring(_ timer: Timer) {
        // If we don't have event monitoring active and permissions are now available, try again
        if !isEventMonitoringActive && AXIsProcessTrusted() {
            print("[LOG] Accessibility permissions granted, retrying event monitoring setup...")
            setupEventMonitoring()
            if isEventMonitoringActive {
                print("[LOG] Event monitoring setup successful after retry")
                timer.invalidate() // Stop retrying once successful
            }
        } else if isEventMonitoringActive {
            // 如果已经活跃，验证状态
            let status = getEventMonitoringStatus()
            if !status.isValid || !status.hasRunLoopSource {
                print("[LOG] Event monitoring appears corrupted, attempting restart...")
                restartEventMonitoringInternal()
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