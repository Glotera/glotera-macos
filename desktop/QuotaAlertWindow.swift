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
            Logger.info("配额警告显示过于频繁，跳过此次提醒")
            return
        }
        
        guard !isShowingAlert else {
            Logger.info("已有配额提醒窗口显示中，跳过")
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
        • Free Account: 100 translations per month
        • Pro Account: 500 translations per month for $2.9/month  
        • Max Account: Unlimited translations for $4.9/month
        
        Please sign in to continue.
        """
        
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Sign In")
        alert.addButton(withTitle: "Learn About Pricing")
        alert.addButton(withTitle: "Quit App")
        
        // 移除应用图标，并防止系统自动附加默认图标
        alert.icon = nil
        alert.icon = NSImage(size: NSSize(width: 1, height: 1))
        
        // 确保对话框显示在最前面
        alert.window.level = .modalPanel
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            // Sign In
            self.openLoginPage()
        case .alertSecondButtonReturn:
            // Learn About Pricing
            self.openPricingPage()
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
            Logger.info("已有配额提醒窗口显示中，跳过")
            return
        }
        
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
        
        To ensure continuous translation service, we recommend upgrading to Pro or Max:
        • Unlimited translations
        • Faster translation speed
        • Priority customer support
        """
        
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Upgrade to Pro/Max")
        alert.addButton(withTitle: "Continue") 
        
        // 移除应用图标，并防止系统自动附加默认图标
        alert.icon = nil
        alert.icon = NSImage(size: NSSize(width: 1, height: 1))
        
        // 确保对话框显示在最前面
        alert.window.level = .modalPanel
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            // Upgrade to Pro
            self.openUpgradePage()
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
        alert.messageText = "Translation Quota Exceeded"
        alert.informativeText = """
        Your free translation quota (100 times) for this month has been used up.
        
        Upgrade your plan:
        • Pro: 500 translations per month for $2.9/month
        • Max: Unlimited translations for $7.9/month
        • Priority customer support
        • Advanced translation features
        """
        
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Upgrade Now")
        alert.addButton(withTitle: "Next Month")
        
        // 移除应用图标，并防止系统自动附加默认图标
        alert.icon = nil
        alert.icon = NSImage(size: NSSize(width: 1, height: 1))
        
        // 确保对话框显示在最前面
        alert.window.level = .modalPanel
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            // Upgrade now
            self.openUpgradePage()
        case .alertSecondButtonReturn:
            // Next month
            Logger.info("User chose to upgrade next month")
        default:
            break
        }
        
        isShowingAlert = false
    }
    
    
    private func openLoginPage() {
        let environmentManager = EnvironmentManager.shared
        let loginURL = "\(environmentManager.baseURL)/login?redirect=glotera://auth/callback"
        
        if let url = URL(string: loginURL) {
            NSWorkspace.shared.open(url)
            Logger.info("Opening login page: \(loginURL)")
        } else {
            Logger.error("Invalid login URL: \(loginURL)")
            
            // Backup plan - Show login information
            let alert = NSAlert()
            alert.messageText = "Login Information"
            alert.informativeText = """
            Please visit the following URL to sign in:
            \(loginURL)
            
            Or contact support for assistance:
            support@glotera.ai
            """
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    private func openPricingPage() {
        let environmentManager = EnvironmentManager.shared
        let pricingURL = "\(environmentManager.baseURL)/pricing"
        
        if let url = URL(string: pricingURL) {
            NSWorkspace.shared.open(url)
            Logger.info("Opening pricing page: \(pricingURL)")
        } else {
            Logger.error("Invalid pricing URL: \(pricingURL)")
            
            // Backup plan - Show pricing information
            let alert = NSAlert()
            alert.messageText = "Pricing Information"
            alert.informativeText = """
            Please visit the following URL to see pricing:
            \(pricingURL)
            
            Pro Plan: $2.9/month for unlimited translations
            
            Contact support for assistance:
            support@glotera.ai
            """
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    private func openUpgradePage() {
        let upgradeURL = "https://glotera.ai/upgrade"
        
        if let url = URL(string: upgradeURL) {
            NSWorkspace.shared.open(url)
            Logger.info("打开升级页面: \(upgradeURL)")
        } else {
            Logger.error("无效的升级页面URL: \(upgradeURL)")
            
            // Backup plan - Show upgrade information
            let alert = NSAlert()
            alert.messageText = "Upgrade Information"
            alert.informativeText = """
            Please visit the following URL to upgrade to Pro:
            https://glotera.ai/upgrade
            
            Or contact support for assistance:
            support@glotera.ai
            """
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
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
        Logger.info("配额提醒状态已重置")
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
        Logger.info("QuotaManager初始化完成，已设置为TranslatorClient的配额委托")
    }
    
    // MARK: - TranslatorQuotaDelegate
    
    func didReceiveQuotaUpdate(_ quotaInfo: QuotaInfo) {
        Logger.info("配额更新: \(quotaInfo.quotaDescription)")
        
        // 可以在这里更新菜单栏的配额显示等
        DispatchQueue.main.async {
            self.updateQuotaDisplayInMenuBar(quotaInfo)
        }
    }
    
    func didReceiveQuotaWarning(_ quotaInfo: QuotaInfo) {
        Logger.info("收到配额警告: 剩余 \(quotaInfo.remainingQuota) 次")
        
        // 将低配额警告加入延迟队列，等翻译完成后再显示
        scheduleDelayedWarning(quotaInfo)
    }
    
    func didReceiveQuotaExceededError(_ quotaInfo: QuotaInfo) {
        Logger.info("收到配额耗尽错误")
        
        // 显示配额耗尽对话框
        QuotaAlertWindow.shared.showQuotaExceeded(quotaInfo)
    }
    
    // MARK: - Private Methods
    
    private func updateQuotaDisplayInMenuBar(_ quotaInfo: QuotaInfo) {
        // 这里可以更新菜单栏中的配额显示
        // 例如更新MenuBarController中的配额信息
        if (NSApp.delegate as? AppDelegate)?.menuBarController != nil {
            // 假设MenuBarController有更新配额显示的方法
            // menuBarController.updateQuotaDisplay(quotaInfo)
        }
        
        Logger.info("菜单栏配额显示已更新: \(quotaInfo.quotaDescription)")
    }
    
    /// 安排延迟的低配额警告
    private func scheduleDelayedWarning(_ quotaInfo: QuotaInfo) {
        // 添加到待处理队列
        pendingLowQuotaWarnings.append(quotaInfo)
        Logger.info("已将配额警告加入延迟队列，当前队列长度: \(pendingLowQuotaWarnings.count)")
        
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
        Logger.info("显示延迟的配额警告: 剩余 \(latestQuotaInfo.remainingQuota) 次")
        
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
        Logger.info("已清除所有待处理的配额警告")
    }
} 
