import Cocoa
import SwiftUI

/// 配额提醒窗口 - 用于显示配额警告和升级提示
class QuotaAlertWindow: NSWindow {
    
    static let shared = QuotaAlertWindow()
    
    private var isShowingAlert = false
    private var lastAlertTime: Date?
    private var hasShownFirstTranslationGuidance = false
    
    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        self.title = "Glotera - Quota Alert"
        self.isReleasedWhenClosed = false
        self.level = .modalPanel  // 使用最高优先级，确保显示在翻译窗口前面
        self.center()
    }
    
    /// 显示配额警告对话框
    func showQuotaWarning(_ quotaInfo: QuotaInfo) {
        // 防止频繁弹窗 - 每小时最多显示一次警告
        if let lastTime = lastAlertTime, 
           Date().timeIntervalSince(lastTime) < 3600 {
            Logger.info("Quota warning shown too frequently, skipping this reminder")
            return
        }
        
        guard !isShowingAlert else {
            Logger.info("Quota alert window already shown, skipping")
            return
        }
        
        lastAlertTime = Date()
        isShowingAlert = true
        
        DispatchQueue.main.async { [weak self] in
            // Only show for authenticated users since anonymous mode is disabled
            if SessionManager.shared.isAuthenticated {
                self?.showWarningDialog(quotaInfo)
            } else {
                // Should not happen since login is required, but handle gracefully
                self?.showLoginRequirement()
            }
        }
    }
    
    /// Show login requirement when user tries to use features without authentication
    func showLoginRequirement() {
        guard !isShowingAlert else {
            Logger.info("Alert already showing, skipping login requirement")
            return
        }
        
        isShowingAlert = true
        
        DispatchQueue.main.async { [weak self] in
            self?.showLoginRequiredDialog()
        }
    }
    
    private func showLoginRequiredDialog() {
        let alert = NSAlert()
        alert.messageText = "Sign In Required"
        alert.informativeText = """
        Glotera requires you to sign in to use translation features.
        
        Choose your plan:
        • Free Account: \(QuotaLimits.FREE_MONTHLY_LIMIT) translations per month
        • Pro Account: \(QuotaLimits.PRO_MONTHLY_LIMIT) translations per month
        • Max Account: Unlimited translations
        
        Please sign in to continue.
        """
        
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Sign In")
        alert.addButton(withTitle: "Learn About Pricing")
        alert.addButton(withTitle: "Quit App")
        
        // Set info icon for login requirement dialog
        if let infoIcon = NSImage(systemSymbolName: "info.circle.fill", accessibilityDescription: "Information") {
            alert.icon = infoIcon
        } else if let infoIcon = NSImage(named: NSImage.infoName) {
            alert.icon = infoIcon
        }
        
        // 确保对话框显示在最前面
        alert.window.level = .modalPanel
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            // Sign In
            UserManager.shared.openLoginPage()
        case .alertSecondButtonReturn:
            // Learn About Pricing
            EnvironmentManager.shared.openUpgradePage()
        case .alertThirdButtonReturn:
            // Quit App
            Logger.info("User chose to quit app without signing in")
            NSApplication.shared.terminate(nil)
        default:
            break
        }
        
        isShowingAlert = false
    }
    
    /// 显示配额耗尽对话框
    func showQuotaExceeded(_ quotaInfo: QuotaInfo) {
        guard !isShowingAlert else {
            Logger.info("Quota alert window already shown, skipping")
            return
        }
        
        // Check cooldown period to prevent duplicate dialogs within 5 seconds
        let now = Date()
        if let lastAlert = lastAlertTime, now.timeIntervalSince(lastAlert) < 5.0 {
            Logger.info("Quota exhausted dialog shown recently, skipping duplicate (cooldown: \(now.timeIntervalSince(lastAlert))s)")
            return
        }
        
        lastAlertTime = now
        
        // 配额耗尽时，无需再显示后续的低配额警告
        QuotaManager.shared.clearPendingWarnings()
        
        // 在显示配额耗尽对话框之前，立即关闭所有翻译相关窗口
        DispatchQueue.main.async {
            self.closeAllTranslationWindows()
        }
        
        isShowingAlert = true
        
        DispatchQueue.main.async { [weak self] in
            // Only show for authenticated users since anonymous mode is disabled
            if SessionManager.shared.isAuthenticated {
                self?.showExceededDialog(quotaInfo)
            } else {
                // Should not happen since login is required, but handle gracefully
                self?.showLoginRequirement()
            }
        }
    }
    
    private func showWarningDialog(_ quotaInfo: QuotaInfo) {
        let alert = NSAlert()
        alert.messageText = "Translation Quota Running Low"
        alert.informativeText = """
        You have \(quotaInfo.remainingQuota) translations remaining.
        
        To ensure continuous translation service, we recommend upgrading to Pro (\(QuotaLimits.PRO_MONTHLY_LIMIT)/month) or Max (unlimited):
        • Unlimited translations
        • Faster translation speed
        • Priority customer support
        """
        
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Upgrade to Pro/Max")
        alert.addButton(withTitle: "Continue") 
        
        // Set warning icon for quota warning dialog
        if let warningIcon = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Warning") {
            alert.icon = warningIcon
        } else if let cautionIcon = NSImage(named: NSImage.cautionName) {
            alert.icon = cautionIcon
        }
        
        // 确保对话框显示在最前面
        alert.window.level = .modalPanel
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            // Upgrade to Pro
            EnvironmentManager.shared.openUpgradePage()
        case .alertSecondButtonReturn:
            // Continue using
            Logger.info("User chose to continue with free quota") 
        default:
            break
        }
        
        isShowingAlert = false
    }
    
    private func showExceededDialog(_ quotaInfo: QuotaInfo) {
        let alert = NSAlert()
        alert.messageText = "Translation Quota Exhausted"
        
        // Create more user-friendly message based on user type
        let quotaMessage: String
        if quotaInfo.isFreeUser {
            quotaMessage = """
            You've used all \(QuotaLimits.FREE_MONTHLY_LIMIT) free translations for this month.
            
            🚀 Upgrade to continue translating:
            • Pro Plan: \(QuotaLimits.PRO_MONTHLY_LIMIT) translations/month
            • Max Plan: Unlimited translations
            
            Your quota will reset next month, or upgrade now for instant access.
            """
        } else {
            quotaMessage = """
            Your translation quota has been exceeded.
            
            Please check your account status or contact support if you believe this is an error.
            """
        }
        
        alert.informativeText = quotaMessage
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Upgrade Now")
        alert.addButton(withTitle: "Maybe Later")
        
        // Set custom icon for quota exhausted dialog
        if let customIcon = createQuotaExhaustedIcon() {
            alert.icon = customIcon
        } else {
            // Fallback to system warning icon if custom icon creation fails
            alert.icon = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Warning")
            // If system symbol not available (older macOS), use named system image
            if alert.icon == nil {
                alert.icon = NSImage(named: NSImage.cautionName)
            }
        }
        
        // 确保对话框显示在最前面
        alert.window.level = .modalPanel
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            // Upgrade now
            Logger.info("User clicked 'Upgrade Now' for quota exceeded")
            EnvironmentManager.shared.openUpgradePage()
        case .alertSecondButtonReturn:
            // Maybe later
            Logger.info("User clicked 'Maybe Later' for quota exceeded")
        default:
            Logger.info("User dismissed quota exceeded dialog")
            break
        }
        
        isShowingAlert = false
    } 
    
    /// 关闭所有翻译相关窗口
    private func closeAllTranslationWindows() {
        Logger.info("Closing all translation windows due to quota exceeded")
        
        // 关闭翻译菜单窗口及其管理的流式翻译窗口
        TranslationMenuWindow.shared.hide()
        
        // 隐藏翻译状态窗口
        TranslationStatusWindow.shared.hideStatus()
        
        // 遍历所有窗口，寻找并关闭TranslationResultWindow实例
        for window in NSApplication.shared.windows {
            if window is TranslationResultWindow {
                Logger.info("Found and hiding TranslationResultWindow")
                window.orderOut(nil)
            }
        }
    }
    
    /// 重置提醒状态 - 用于测试或特殊情况
    func resetAlertState() {
        isShowingAlert = false
        lastAlertTime = nil
        Logger.info("Quota alert state reset")
    }
    
    /// 创建配额耗尽对话框的自定义图标
    private func createQuotaExhaustedIcon() -> NSImage? {
        // Try to use system symbol first (macOS 11+)
        if let systemIcon = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Warning") {
            systemIcon.size = NSSize(width: 64, height: 64)
            return systemIcon
        }
        
        // Fallback to system caution icon for older macOS versions
        if let cautionIcon = NSImage(named: NSImage.cautionName) {
            cautionIcon.size = NSSize(width: 64, height: 64)
            return cautionIcon
        }
        
        // Last resort: create a simple custom icon
        let image = NSImage(size: NSSize(width: 64, height: 64))
        image.lockFocus()
        
        // Draw a warning triangle
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 32, y: 10))
        path.line(to: NSPoint(x: 50, y: 50))
        path.line(to: NSPoint(x: 14, y: 50))
        path.close()
        
        NSColor.systemOrange.setFill()
        path.fill()
        
        // Draw exclamation mark
        let exclamationPath = NSBezierPath()
        exclamationPath.move(to: NSPoint(x: 30, y: 40))
        exclamationPath.line(to: NSPoint(x: 34, y: 40))
        exclamationPath.line(to: NSPoint(x: 34, y: 25))
        exclamationPath.line(to: NSPoint(x: 30, y: 25))
        exclamationPath.close()
        
        let dotPath = NSBezierPath(ovalIn: NSRect(x: 30, y: 20, width: 4, height: 4))
        
        NSColor.white.setFill()
        exclamationPath.fill()
        dotPath.fill()
        
        image.unlockFocus()
        return image
    }
}

/// 全局配额管理器 - 统一处理配额相关的UI提示
class QuotaManager: TranslatorQuotaDelegate {
    
    static let shared = QuotaManager()
    
    // 延迟提醒队列
    private var pendingLowQuotaWarnings: [QuotaInfo] = []
    private var warningTimer: Timer?
    
    private init() {
        // 设置为TranslatorClient的配额委托
        TranslatorClient.shared.quotaDelegate = self
        Logger.info("QuotaManager initialized, set as quota delegate for TranslatorClient")
    }
    
    // MARK: - TranslatorQuotaDelegate
    
    func didReceiveQuotaUpdate(_ quotaInfo: QuotaInfo) {
        Logger.debug("Quota updated: \(quotaInfo.quotaDescription)")
        
        // 更新菜单栏的配额显示
        DispatchQueue.main.async {
            self.updateQuotaDisplayInMenuBar(quotaInfo)
        }
    }
    
    func didReceiveQuotaWarning(_ quotaInfo: QuotaInfo) {
        Logger.info("Received quota warning: remaining \(quotaInfo.remainingQuota) times")
        
        // 更新菜单栏的配额显示
        DispatchQueue.main.async {
            self.updateQuotaDisplayInMenuBar(quotaInfo)
        }
        
        // 将低配额警告加入延迟队列，等翻译完成后再显示
        scheduleDelayedWarning(quotaInfo)
    }
    
    func didReceiveQuotaExceededError(_ quotaInfo: QuotaInfo) {
        Logger.info("Received quota exhausted error")
        
        // 更新菜单栏的配额显示
        DispatchQueue.main.async {
            self.updateQuotaDisplayInMenuBar(quotaInfo)
        }
        
        // 显示配额耗尽对话框
        QuotaAlertWindow.shared.showQuotaExceeded(quotaInfo)
    }
    
    // MARK: - Private Methods
    
    private func updateQuotaDisplayInMenuBar(_ quotaInfo: QuotaInfo) {
        // Post notification for MenuBarController to update quota display
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .quotaInfoUpdated,
                object: quotaInfo
            )
        }
        
        Logger.debug("Menu bar quota display updated: \(quotaInfo.quotaDescription)")
    }
    
    /// 安排延迟的低配额警告
    private func scheduleDelayedWarning(_ quotaInfo: QuotaInfo) {
        // 添加到待处理队列
        pendingLowQuotaWarnings.append(quotaInfo)
        Logger.info("Quota warning added to delay queue, current queue length: \(pendingLowQuotaWarnings.count)")
        
        // 取消之前的定时器
        warningTimer?.invalidate()
        
        // 设置延迟显示定时器（2秒后显示，给翻译完成留出时间）
        warningTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.showPendingWarnings()
        }
    }
    
    /// 显示所有待处理的警告
    private func showPendingWarnings() {
        guard !pendingLowQuotaWarnings.isEmpty else { return }
        
        // 取最新的配额信息（如果有多个的话）
        let latestQuotaInfo = pendingLowQuotaWarnings.last!
        Logger.info("Show delayed quota warning: remaining \(latestQuotaInfo.remainingQuota) times")
        
        // 清空队列
        pendingLowQuotaWarnings.removeAll()
        
        // 显示警告对话框
        QuotaAlertWindow.shared.showQuotaWarning(latestQuotaInfo)
    }
    
    /// 立即显示待处理的警告（用于某些特殊情况）
    func showPendingWarningsImmediately() {
        warningTimer?.invalidate()
        showPendingWarnings()
    }
    
    /// 清除所有待处理的警告（当配额耗尽时使用）
    func clearPendingWarnings() {
        warningTimer?.invalidate()
        pendingLowQuotaWarnings.removeAll()
        Logger.info("All pending quota warnings cleared")
    }
} 
