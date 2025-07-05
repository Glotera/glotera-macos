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
    
    // Optimized monitoring state
    private var monitoringTimer: Timer?
    private var lastFailureTime: Date?
    private var consecutiveFailures = 0
    private var isInAdaptiveMode = false

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        Logger.info("AppDelegate did finish launching")
        menuBarController = MenuBarController()
        inputMonitor = InputMonitor()
        
        // 初始化配额管理器 - 这将设置配额委托
        _ = QuotaManager.shared
        
        // Initialize simple memory manager for translation windows
        _ = SimpleMemoryManager.shared
        
        // Initialize performance telemetry
        _ = PerformanceTelemetry.shared
        
        // Initialize update manager and check for updates
        _ = UpdateManager.shared
        UpdateManager.shared.performFirstLaunchCheck()
        
        // Check authentication status on startup
        checkAuthenticationStatus()
        
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
        
        // Note: Adaptive monitoring will start automatically after successful event tap setup
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
        
        Logger.info("Application lifecycle monitoring setup complete")
    }
    
    // 启动优化的 Event Tap 监控
    private func startEventTapMonitoring() {
        startAdaptiveMonitoring()
    }
    
    // Adaptive monitoring with dynamic intervals
    private func startAdaptiveMonitoring() {
        // Start with 60s interval (reduced from 30s for better battery life)
        let initialInterval: TimeInterval = 60.0
        scheduleNextMonitoringCheck(interval: initialInterval)
        Logger.info("Event tap adaptive monitoring started (60s initial interval)")
    }
    
    private func scheduleNextMonitoringCheck(interval: TimeInterval) {
        // Invalidate existing timer
        monitoringTimer?.invalidate()
        
        // Schedule next check
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.performAdaptiveEventTapCheck()
        }
        
        RunLoop.main.add(monitoringTimer!, forMode: .common)
    }
    
    // Optimized adaptive Event Tap health check
    private func performAdaptiveEventTapCheck() {
        guard let eventTap = eventTap else { 
            scheduleNextMonitoringCheck(interval: 60.0)
            return 
        }
        
        let isValid = CFMachPortIsValid(eventTap)
        let isEnabled = CGEvent.tapIsEnabled(tap: eventTap)
        let isActive = isEventMonitoringActive
        
        // 检查是否刚进行过选中文本翻译（可能导致暂时失效）
        let timeSinceSelectionTranslation = inputMonitor.getTimeSinceLastSelectionTranslation()
        let isRecentSelectionTranslation = timeSinceSelectionTranslation < 60.0 // 60秒内
        
        var nextInterval: TimeInterval = 60.0 // Default interval
        
        // 如果发现问题征兆，主动修复
        if !isEnabled || !isValid || !isActive {
            
            // 如果刚进行了选中文本翻译，跳过检查但缩短下次检查间隔
            if isRecentSelectionTranslation {
                Logger.debug("Skipping Event Tap check - recent selection translation (\(String(format: "%.1f", timeSinceSelectionTranslation))s ago)")
                nextInterval = 30.0 // Check again sooner
            } else {
                recordFailure()
                Logger.warn("Event Tap check detected issue - Valid: \(isValid), Enabled: \(isEnabled), Active: \(isActive)")
                
                // 尝试快速恢复
                if quickEnableEventTap() {
                    Logger.info("Event Tap recovery successful")
                    recordRecovery()
                } else {
                    Logger.warn("Event Tap recovery failed, scheduling full restart")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.restartEventMonitoringInternal()
                    }
                    nextInterval = 30.0 // Check more frequently after failure
                }
            }
        } else {
            // System is healthy
            recordHealthyState()
            nextInterval = calculateOptimalInterval()
            
            // Reduced logging frequency
            if consecutiveFailures == 0 && !isInAdaptiveMode {
                let currentTime = Int(Date().timeIntervalSince1970)
                if currentTime % 600 == 0 { // Every 10 minutes instead of 5
                    Logger.debug("Event Tap health check: OK (stable)")
                }
            }
        }
        
        // Schedule next check with adaptive interval
        scheduleNextMonitoringCheck(interval: nextInterval)
    }
    
    // Track failures for adaptive monitoring
    private func recordFailure() {
        lastFailureTime = Date()
        consecutiveFailures += 1
        isInAdaptiveMode = true
        Logger.debug("Recorded failure #\(consecutiveFailures)")
    }
    
    // Track recovery for adaptive monitoring
    private func recordRecovery() {
        Logger.debug("System recovered after \(consecutiveFailures) failures")
        consecutiveFailures = max(0, consecutiveFailures - 2) // Reduce failure count on recovery
        if consecutiveFailures == 0 {
            isInAdaptiveMode = false
        }
    }
    
    // Track healthy state
    private func recordHealthyState() {
        if consecutiveFailures > 0 {
            consecutiveFailures = max(0, consecutiveFailures - 1)
            if consecutiveFailures == 0 {
                isInAdaptiveMode = false
                Logger.debug("System returned to stable state")
            }
        }
    }
    
    // Calculate optimal monitoring interval based on system stability
    private func calculateOptimalInterval() -> TimeInterval {
        if consecutiveFailures == 0 {
            // System is stable - use longer intervals to save CPU/battery
            return 120.0 // 2 minutes for stable system
        } else if consecutiveFailures <= 2 {
            // Minor issues - moderate frequency
            return 60.0 // 1 minute
        } else {
            // Frequent issues - higher frequency monitoring
            return 30.0 // 30 seconds
        }
    }
    
    // Trigger immediate monitoring check (on-demand)
    private func triggerImmediateMonitoringCheck() {
        Logger.debug("Triggering immediate monitoring check")
        performAdaptiveEventTapCheck()
    }
    
    @objc private func applicationDidBecomeActive() {
        Logger.info("Application became active - triggering immediate monitoring check")
        // 应用变为活跃时立即检查事件监听状态
        triggerImmediateMonitoringCheck()
    }
    
    @objc private func applicationDidResignActive() {
        Logger.info("Application resigned active")
    }
    
    @objc private func systemDidWakeUp() {
        Logger.info("System woke up - triggering immediate monitoring check")
        // 系统唤醒后立即检查并可能重启事件监听
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.triggerImmediateMonitoringCheck()
        }
    }
    
    private func verifyEventMonitoring() {
        let status = getEventMonitoringStatus()
         
        if !status.isValid || !status.hasRunLoopSource || !status.isActive {
            Logger.warn("Event monitoring verification failed, restarting...")
            restartEventMonitoringInternal()
        } else {
            Logger.info("Event monitoring verification passed")
        }
    }
    
    public func restartEventMonitoring() {
        Logger.info("Public restart method called")
        restartEventMonitoringInternal()
    }
    
    // 尝试快速重新启用 Event Tap（不完全重建）
    public func quickEnableEventTap() -> Bool {
        guard let eventTap = eventTap else {
            Logger.warn("Quick enable failed: no event tap")
            return false
        }
        
        // 检查 Mach Port 是否有效
        let portValid = CFMachPortIsValid(eventTap)
        if !portValid {
            Logger.warn("Quick enable failed: event tap port invalid")
            return false
        }
        
        // 检查权限
        if !AXIsProcessTrusted() {
            Logger.warn("Quick enable failed: accessibility permissions lost")
            return false
        }
        
        Logger.debug("Attempting quick event tap re-enable...")
        
        // 先禁用再启用，确保状态重置
        CGEvent.tapEnable(tap: eventTap, enable: false)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        // 验证是否成功
        let isEnabled = CGEvent.tapIsEnabled(tap: eventTap)
        let finalValid = CFMachPortIsValid(eventTap)
        
        Logger.info("Quick event tap recovery result - Enabled: \(isEnabled), Valid: \(finalValid)")
        
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
        Logger.info("Restarting event monitoring...")
        
        // 清理现有的监听
        cleanupEventMonitoring()
        
        // 等待一段时间后重新设置
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.setupEventMonitoring()
        }
    }
    
    private func cleanupEventMonitoring() { 
        // 标记为非活跃状态
        isEventMonitoringActive = false
        
        // 清理优化的监控定时器
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        Logger.info("Monitoring timer invalidated")
        
        // 清理 RunLoop Source
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            self.runLoopSource = nil
            Logger.info("RunLoop source removed")
        }
        
        // 清理 Event Tap
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
            Logger.info("Event tap invalidated")
        }
        
        Logger.info("Event monitoring cleanup complete")
    }
    
    private func setupEventMonitoring() { 
        
        // Check accessibility permissions first
        if !AXIsProcessTrusted() {
            Logger.warn("Accessibility permissions not granted")
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            let result = AXIsProcessTrustedWithOptions(options as CFDictionary)
            Logger.info("Permission request result: \(result)")
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
            
            // 创建 RunLoop 源
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            self.runLoopSource = runLoopSource
            
            // 添加到 RunLoop
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes) 
            
            // 启用事件监听
            CGEvent.tapEnable(tap: eventTap, enable: true) 
            
            // 标记为活跃状态
            isEventMonitoringActive = true
            
            // Stop the retry timer since we're successful
            retryTimer?.invalidate()
            retryTimer = nil
            
            // Start adaptive monitoring after successful setup
            startAdaptiveMonitoring()
            
            Logger.info("Event monitoring setup complete")
        } else {
            Logger.error("Failed to create event tap - this usually indicates:")
            Logger.error("1. Accessibility permissions not granted")
            Logger.error("2. App Sandbox restrictions")
            Logger.error("3. System security settings blocking access")
            Logger.error("4. Another app is already using event tapping")
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
                // Start monitoring after successful retry
                startAdaptiveMonitoring()
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
            else if timeSinceLastEvent > 1800 && NSApplication.shared.isActive { // 30分钟而不是10分钟
                // 只有在以下条件都满足时才重启：
                // - 应用处于活跃状态
                // - 超过30分钟没有键盘事件
                // - 用户可能在使用电脑（检查鼠标活动等）
                // - 时间差不是异常值（小于1天）
                if timeSinceLastEvent < 86400 { // 小于24小时才认为是正常的时间差
                    let shouldCheck = checkIfUserIsActive()
                    if shouldCheck {
                        Logger.warn("No keyboard events for \(Int(timeSinceLastEvent))s while app is active and user seems active")
                        needsRestart = true
                        reason = "Long period without keyboard events (\(Int(timeSinceLastEvent))s)"
                    }
                } else {
                    // 时间差异常，可能是时间计算错误，重置事件时间
                    Logger.warn("Detected abnormal time difference (\(Int(timeSinceLastEvent))s), resetting event monitoring")
                    needsRestart = true
                    reason = "Abnormal time difference detected, likely initialization issue"
                }
            }
            
            if needsRestart {
                Logger.error("Event monitoring health check failed: \(reason)")
                Logger.debug("Debug info - Status: \(status), TimeSinceLastEvent: \(timeSinceLastEvent), LastEventTime: \(getLastEventTime())")
                
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
    
    // MARK: - URL Scheme Handling
    
    func application(_ application: NSApplication, open urls: [URL]) {
        Logger.info("Application received URL open request with \(urls.count) URLs")
        
        guard let url = urls.first else {
            Logger.error("No URLs provided in open request")
            return
        }
        
        Logger.info("Processing URL: \(url.absoluteString)")
        
        // Check if this is our authentication callback URL
        if url.scheme == "glotera", url.host == "auth", url.path == "/callback" {
            handleAuthCallback(url: url)
        } else {
            Logger.warn("Unknown URL scheme or path: \(url.absoluteString)")
        }
    }
    
    private func handleAuthCallback(url: URL) {
        Logger.info("Handling authentication callback")
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            Logger.error("Failed to parse URL components")
            showAuthError("Invalid authentication response")
            return
        }
        
        // Extract token and user_id from query parameters
        var token: String?
        var userId: String?
        
        if let queryItems = components.queryItems {
            for item in queryItems {
                switch item.name {
                case "token":
                    token = item.value
                case "user_id":
                    userId = item.value
                default:
                    break
                }
            }
        }
        
        guard let authToken = token, let userIdValue = userId else {
            Logger.error("Missing token or user_id in authentication callback")
            showAuthError("Authentication failed: Missing credentials")
            return
        }
        
        Logger.info("Authentication callback received - User ID: \(userIdValue)")
        
        // Parse JWT token to get user information
        if let userInfo = SessionManager.shared.parseJWTToken(authToken) {
            Logger.info("JWT parsed successfully")
            
            let user = User(
                userId: userInfo["user_id"] as? String ?? userIdValue,
                email: userInfo["email"] as? String ?? userIdValue,
                username: userInfo["username"] as? String ?? "User",
                userType: userInfo["user_type"] as? String ?? "free",
                accountType: userInfo["account_type"] as? String ?? "email"
            )
            
            // Store authentication session in SessionManager
            SessionManager.shared.setAuthSession(token: authToken, user: user)
            
            Logger.info("Authentication successful for user: \(user.email)")
            showAuthSuccess("Welcome back, \(user.username)!")
            
        } else {
            Logger.error("Failed to parse JWT token")
            showAuthError("Authentication failed: Invalid token format")
        }
    }
    
    private func showAuthSuccess(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Login Successful"
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    private func showAuthError(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Login Failed"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    // MARK: - Authentication Status Management
    
    private func checkAuthenticationStatus() {
        if SessionManager.shared.isAuthenticated {
            Logger.info("User is authenticated on startup")
            
            // Validate token with server
            SessionManager.shared.validateToken { [weak self] isValid in
                if isValid {
                    Logger.info("Authentication token validated successfully")
                    if let user = SessionManager.shared.getCurrentUser() {
                        Logger.info("Welcome back: \(user.username) (\(user.email))")
                    }
                } else {
                    Logger.warn("Authentication token validation failed")
                    DispatchQueue.main.async {
                        self?.promptLogin(reason: "Your session has expired. Please sign in again.")
                    }
                }
            }
        } else {
            Logger.info("User is not authenticated on startup")
            // For now, we'll still allow the app to work in anonymous mode
            // In the future, you can uncomment this to require login:
            // promptLogin(reason: "Please sign in to use Glotera.")
        }
    }
    
    private func promptLogin(reason: String) {
        let alert = NSAlert()
        alert.messageText = "Sign In Required"
        alert.informativeText = reason
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Sign In")
        alert.addButton(withTitle: "Use Anonymous Mode")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            openLoginPage()
        } else {
            Logger.info("User chose to continue in anonymous mode")
        }
    }
    
    private func openLoginPage() {
        let environmentManager = EnvironmentManager.shared
        let loginURL = "\(environmentManager.baseURL)/login?redirect=glotera://auth/callback"
        
        guard let url = URL(string: loginURL) else {
            Logger.error("Failed to create login URL")
            return
        }
        
        Logger.info("Opening login page: \(loginURL)")
        NSWorkspace.shared.open(url)
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        Logger.info("Application will terminate - cleaning up")
        cleanupEventMonitoring()
        
        // 清理通知观察者
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}