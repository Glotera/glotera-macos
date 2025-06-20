import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController!
    var inputMonitor: InputMonitor!
    var runLoopSource: CFRunLoopSource?
    var retryTimer: Timer?
    var eventTap: CFMachPort?
    
    // 添加状态跟踪
    var isEventMonitoringActive = false
    private var lastRestartTime: Date?
    private var lastMouseLocation: NSPoint?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        print("[LOG] AppDelegate did finish launching")
        menuBarController = MenuBarController()
        inputMonitor = InputMonitor()
        
        // Try to setup event monitoring
        setupEventMonitoring()
        
        // 启动选中文本监听
        AXController.shared.startSelectionMonitoring()
        
        // Setup a timer to retry if permissions are granted later (check every 15 seconds, max 20 times)
        var retryCount = 0
        retryTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] timer in
            retryCount += 1
            if retryCount > 20 { // 增加重试次数限制，因为间隔变长了
                Logger.warn("Stopping retry attempts after 20 tries")
                timer.invalidate()
                return
            }
            self?.checkAndRetryEventMonitoring(timer)
        }
        
        // 添加应用生命周期监听
        setupApplicationLifecycleMonitoring()
        
        // 启动主动 Event Tap 监控
        startEventTapMonitoring()
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
    
    // 获取最后事件时间的访问器
    func getLastEventTime() -> Date {
        return InputMonitor.shared.getLastEventTime()
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
    
    // 启动主动 Event Tap 监控
    private func startEventTapMonitoring() {
        // 每30秒检查一次 Event Tap 状态，主动预防问题
        let monitorTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.proactiveEventTapCheck()
        }
        
        // 保存 timer 引用，以便应用退出时清理
        RunLoop.main.add(monitorTimer, forMode: .common)
        Logger.info("Event tap proactive monitoring started (30s interval)")
    }
    
    // 主动检查 Event Tap 状态
    private func proactiveEventTapCheck() {
        guard let eventTap = eventTap else { return }
        
        let isValid = CFMachPortIsValid(eventTap)
        let isEnabled = CGEvent.tapIsEnabled(tap: eventTap)
        let isActive = isEventMonitoringActive
        
        // 如果发现问题征兆，主动修复
        if !isEnabled || !isValid || !isActive {
            Logger.warn("Proactive check detected issue - Valid: \(isValid), Enabled: \(isEnabled), Active: \(isActive)")
            
            // 尝试快速恢复
            if quickEnableEventTap() {
                Logger.info("Proactive recovery successful")
            } else {
                Logger.warn("Proactive recovery failed, scheduling full restart")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.restartEventMonitoringInternal()
                }
            }
        } else {
            // 每10次检查输出一次正常状态
            let currentTime = Int(Date().timeIntervalSince1970)
            if currentTime % 300 == 0 { // 大约每5分钟输出一次
                Logger.debug("Proactive check: Event tap healthy")
            }
        }
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
    
    // 尝试快速重新启用 Event Tap（不完全重建）
    public func quickEnableEventTap() -> Bool {
        guard let eventTap = eventTap else {
            Logger.debug("Quick enable failed: no event tap")
            return false
        }
        
        // 检查 Mach Port 是否有效
        let portValid = CFMachPortIsValid(eventTap)
        if !portValid {
            Logger.debug("Quick enable failed: event tap port invalid")
            return false
        }
        
        Logger.debug("Attempting quick event tap re-enable...")
        
        // 先禁用再启用，确保状态重置
        CGEvent.tapEnable(tap: eventTap, enable: false)
        Thread.sleep(forTimeInterval: 0.01) // 10ms 短暂延迟
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        // 等待一小段时间让系统处理
        Thread.sleep(forTimeInterval: 0.05) // 50ms
        
        // 验证是否成功
        let isEnabled = CGEvent.tapIsEnabled(tap: eventTap)
        let finalValid = CFMachPortIsValid(eventTap)
        
        Logger.debug("Quick recovery result - Enabled: \(isEnabled), Valid: \(finalValid)")
        
        if isEnabled && finalValid {
            isEventMonitoringActive = true
            Logger.info("Quick event tap recovery successful")
            return true
        } else {
            Logger.warn("Quick event tap recovery failed - Enabled: \(isEnabled), Valid: \(finalValid)")
            return false
        }
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
        
        // 创建事件监听器 - 使用更稳定的配置
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        let callback = inputMonitor.createEventTapCallback()
        
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap, // 改为 tail 位置，减少与其他应用冲突
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
            Logger.info("Accessibility permissions granted, retrying event monitoring setup...")
            setupEventMonitoring()
            if isEventMonitoringActive {
                Logger.info("Event monitoring setup successful after retry")
                timer.invalidate() // Stop retrying once successful
            }
        } else if isEventMonitoringActive {
            // 更智能的健康检查 - 减少误报
            let status = getEventMonitoringStatus()
            let timeSinceLastEvent = Date().timeIntervalSince(getLastEventTime())
            
            // 检查关键失效指标
            var needsRestart = false
            var reason = ""
            
            // 1. Event Tap 完全失效（最严重）
            if !status.isValid {
                needsRestart = true
                reason = "Event tap invalid"
            }
            // 2. RunLoop Source 丢失（严重）
            else if !status.hasRunLoopSource {
                needsRestart = true
                reason = "RunLoop source missing"
            }
            // 3. 权限丢失（严重）
            else if !AXIsProcessTrusted() {
                needsRestart = true
                reason = "Accessibility permissions lost"
            }
            // 4. Event Tap 被系统禁用 - 先尝试快速恢复
            else if let eventTap = eventTap, !CGEvent.tapIsEnabled(tap: eventTap) {
                Logger.warn("Event tap disabled by system, attempting quick recovery...")
                if quickEnableEventTap() {
                    Logger.info("Event tap quick recovery successful")
                    return // 恢复成功，无需重启
                } else {
                    needsRestart = true
                    reason = "Event tap disabled by system (quick recovery failed)"
                }
            }
            // 5. 长时间没有键盘事件检查 - 更宽松的条件
            else if timeSinceLastEvent > 600 && NSApplication.shared.isActive { // 10分钟而不是5分钟
                // 只有在以下条件都满足时才重启：
                // - 应用处于活跃状态
                // - 超过10分钟没有键盘事件
                // - 用户可能在使用电脑（检查鼠标活动等）
                let shouldCheck = checkIfUserIsActive()
                if shouldCheck {
                    Logger.warn("No keyboard events for \(Int(timeSinceLastEvent))s while app is active and user seems active")
                    needsRestart = true
                    reason = "Long period without keyboard events (\(Int(timeSinceLastEvent))s)"
                }
            }
            
            if needsRestart {
                Logger.error("Event monitoring health check failed: \(reason)")
                Logger.debug("Status details - Active: \(status.isActive), Valid: \(status.isValid), HasRunLoopSource: \(status.hasRunLoopSource)")
                Logger.debug("Time since last event: \(timeSinceLastEvent)s")
                
                // 增加重启之间的间隔，避免频繁重启
                if let lastRestart = lastRestartTime, Date().timeIntervalSince(lastRestart) < 30 {
                    Logger.warn("Skipping restart - last restart was less than 30 seconds ago")
                    return
                }
                
                lastRestartTime = Date()
                restartEventMonitoringInternal()
            } else {
                // 减少调试输出频率 - 每5分钟输出一次而不是每分钟
                let currentTime = Date().timeIntervalSince1970
                if Int(currentTime) % 300 == 0 { // 每5分钟输出一次
                    Logger.info("Event monitoring health: OK - Last event: \(Int(timeSinceLastEvent))s ago")
                }
            }
        }
    }
    
    // 检查用户是否在活跃使用电脑
    private func checkIfUserIsActive() -> Bool {
        // 简单的用户活跃检查：检查最近的鼠标移动
        let currentMouseLocation = NSEvent.mouseLocation
        
        // 如果这是第一次检查，记录位置并返回false（给用户时间）
        if lastMouseLocation == nil {
            lastMouseLocation = currentMouseLocation
            return false
        }
        
        // 检查鼠标是否移动过
        let mouseMoved = abs(currentMouseLocation.x - lastMouseLocation!.x) > 10 ||
                        abs(currentMouseLocation.y - lastMouseLocation!.y) > 10
        
        lastMouseLocation = currentMouseLocation
        
        // 如果鼠标移动了，说明用户在活跃使用
        return mouseMoved
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        print("[LOG] Application will terminate - cleaning up")
        cleanupEventMonitoring()
        
        // 清理通知观察者
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}