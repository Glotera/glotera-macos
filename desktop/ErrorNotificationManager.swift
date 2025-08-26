import Foundation
import Cocoa
import SwiftUI

// MARK: - User-Friendly Error Types
enum UserFriendlyError {
    case networkConnection(originalError: String)
    case serverUnavailable(statusCode: Int)
    case slowNetwork
    case serverMaintenance
    case unknownError(originalError: String)
    
    var title: String {
        switch self {
        case .networkConnection:
            return "Network Connection Issue"
        case .serverUnavailable:
            return "Service Temporarily Unavailable"
        case .slowNetwork:
            return "Network Response Slow"
        case .serverMaintenance:
            return "Service Under Maintenance"
        case .unknownError:
            return "Translation Issue"
        }
    }
    
    var message: String {
        switch self {
        case .networkConnection:
            return "Unable to connect to translation server. Please check your network connection and try again."
        case .serverUnavailable(let statusCode):
            if statusCode >= 500 {
                return "Translation server is currently under maintenance. Please try again later."
            } else {
                return "Translation service is temporarily unavailable. Please try again later."
            }
        case .slowNetwork:
            return "Network connection is slow. Translation may take longer than usual."
        case .serverMaintenance:
            return "Translation service is under maintenance. Expected to resume in a few minutes."
        case .unknownError:
            return "An issue occurred during translation. Please try again or contact support."
        }
    }
    
    var suggestions: [String] {
        switch self {
        case .networkConnection:
            return [
                "Check WiFi or network connection",
                "Try refreshing network settings",
                "Retry translation later"
            ]
        case .serverUnavailable:
            return [
                "Wait a few minutes and try again",
                "Check Glotera website for service status",
                "Contact support for assistance"
            ]
        case .slowNetwork:
            return [
                "Wait for translation to complete",
                "Check network connection quality"
            ]
        case .serverMaintenance:
            return [
                "Wait a few minutes and try again",
                "Follow Glotera official announcements"
            ]
        case .unknownError:
            return [
                "Retry translation",
                "Restart the application",
                "Contact technical support"
            ]
        }
    }
    
    var iconName: String {
        switch self {
        case .networkConnection:
            return "wifi.exclamationmark"
        case .serverUnavailable:
            return "server.rack"
        case .slowNetwork:
            return "tortoise.fill"
        case .serverMaintenance:
            return "wrench.and.screwdriver.fill"
        case .unknownError:
            return "exclamationmark.triangle.fill"
        }
    }
    
    var iconColor: NSColor {
        switch self {
        case .networkConnection:
            return NSColor.systemOrange
        case .serverUnavailable:
            return NSColor.systemRed
        case .slowNetwork:
            return NSColor.systemYellow
        case .serverMaintenance:
            return NSColor.systemBlue
        case .unknownError:
            return NSColor.systemRed
        }
    }
}

// MARK: - Error Notification Manager
class ErrorNotificationManager {
    static let shared = ErrorNotificationManager()
    
    private init() {}
    
    private var lastNotificationTime: [String: Date] = [:]
    private let minimumNotificationInterval: TimeInterval = 10.0 // 10秒内不重复显示相同错误
    
    /// 分析TranslationError并转换为用户友好的错误
    func classifyError(_ error: TranslationError) -> UserFriendlyError {
        switch error {
        case .networkError(let message):
            return classifyNetworkError(message)
        case .serverError(let code, let message):
            return classifyServerError(code: code, message: message)
        case .parseError(let message):
            return .unknownError(originalError: message)
        case .authenticationRequired(let message):
            // 认证错误由其他组件处理，这里不处理
            return .unknownError(originalError: message)
        case .quotaExceeded:
            // 配额错误由QuotaAlertWindow处理，这里不处理
            return .unknownError(originalError: "Quota exceeded")
        }
    }
    
    private func classifyNetworkError(_ message: String) -> UserFriendlyError {
        let lowercaseMessage = message.lowercased()
        
        if lowercaseMessage.contains("timeout") || lowercaseMessage.contains("timed out") {
            return .slowNetwork
        } else if lowercaseMessage.contains("network") || 
                  lowercaseMessage.contains("connection") ||
                  lowercaseMessage.contains("unreachable") ||
                  lowercaseMessage.contains("offline") {
            return .networkConnection(originalError: message)
        } else {
            return .unknownError(originalError: message)
        }
    }
    
    private func classifyServerError(code: Int, message: String) -> UserFriendlyError {
        switch code {
        case 500...599:
            if message.lowercased().contains("maintenance") {
                return .serverMaintenance
            } else {
                return .serverUnavailable(statusCode: code)
            }
        case 400...499:
            return .serverUnavailable(statusCode: code)
        default:
            return .unknownError(originalError: "\(code): \(message)")
        }
    }
    
    /// 显示用户友好的错误通知
    func showErrorNotification(_ error: TranslationError, near mousePoint: CGPoint? = nil) {
        let userFriendlyError = classifyError(error)
        
        // 防止重复显示相同类型的错误通知
        let errorKey = "\(userFriendlyError.title)"
        if let lastTime = lastNotificationTime[errorKey],
           Date().timeIntervalSince(lastTime) < minimumNotificationInterval {
            Logger.debug("Skipping duplicate error notification: \(errorKey)")
            return
        }
        
        lastNotificationTime[errorKey] = Date()
        
        DispatchQueue.main.async {
            self.showErrorAlert(userFriendlyError, near: mousePoint)
        }
        
        Logger.error("User-friendly error shown: \(userFriendlyError.title) - \(userFriendlyError.message)")
    }
    
    private func showErrorAlert(_ error: UserFriendlyError, near mousePoint: CGPoint?) {
        // 对于非认证和非配额错误，显示自定义错误窗口
        if case .unknownError(let originalError) = error,
           originalError.contains("Authentication") || originalError.contains("Quota") {
            // 让其他组件处理这些特殊错误
            return
        }
        
        // 创建系统Alert对话框
        let alert = NSAlert()
        alert.messageText = error.title
        alert.informativeText = createInformativeText(for: error)
        alert.alertStyle = .warning
        
        // 设置图标
        if let iconImage = NSImage(systemSymbolName: error.iconName, accessibilityDescription: nil) {
            let coloredImage = iconImage.copy() as! NSImage
            coloredImage.lockFocus()
            error.iconColor.set()
            coloredImage.draw(at: NSPoint.zero, from: NSRect.zero, operation: .sourceAtop, fraction: 1.0)
            coloredImage.unlockFocus()
            alert.icon = coloredImage
        }
        
        // 添加按钮
        alert.addButton(withTitle: "Retry")
        alert.addButton(withTitle: "Cancel")
        
        if case .networkConnection = error {
            alert.addButton(withTitle: "Network Settings")
        } else if case .serverUnavailable = error {
            alert.addButton(withTitle: "Check Status")
        }
        
        // 显示对话框
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            // Retry - trigger retranslation
            handleRetryAction()
        case .alertSecondButtonReturn:
            // Cancel - do nothing
            break
        case .alertThirdButtonReturn:
            // Third button - network settings or check status
            handleThirdAction(for: error)
        default:
            break
        }
    }
    
    private func createInformativeText(for error: UserFriendlyError) -> String {
        var text = error.message
        
        if !error.suggestions.isEmpty {
            text += "\n\nSuggested solutions:"
            for (index, suggestion) in error.suggestions.enumerated() {
                text += "\n\(index + 1). \(suggestion)"
            }
        }
        
        return text
    }
    
    private func handleRetryAction() {
        // Notify retry translation - can be implemented via NotificationCenter or delegate pattern
        NotificationCenter.default.post(name: .retryTranslation, object: nil)
        Logger.info("User requested retry after error notification")
    }
    
    private func handleThirdAction(for error: UserFriendlyError) {
        switch error {
        case .networkConnection:
            // Open network settings
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.network")!)
        case .serverUnavailable:
            // Open Glotera status page
            NSWorkspace.shared.open(URL(string: "https://glotera.ai")!)
        default:
            break
        }
    }
    
    /// Show simple status reminder (for TranslationStatusWindow)
    func showSimpleErrorStatus(near mousePoint: CGPoint) {
        // Update status window to show friendly error information
        TranslationStatusWindow.shared.showNetworkError(near: mousePoint)
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let retryTranslation = Notification.Name("retryTranslation")
}
