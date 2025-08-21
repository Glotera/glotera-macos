import Foundation

/// 配额限制常量定义
/// 与服务端保持一致，便于维护和修改
struct QuotaLimits {
    
    // MARK: - 月度翻译配额限制
    /// 免费用户月度翻译配额
    static let FREE_MONTHLY_LIMIT = 100
    
    /// Pro用户月度翻译配额
    static let PRO_MONTHLY_LIMIT = 5000
    
    /// Max用户月度翻译配额（无限制）
    static let MAX_MONTHLY_LIMIT = -1
    
    // MARK: - 配额警告阈值
    /// 低配额警告阈值（剩余配额低于此值时显示警告）
    static let LOW_QUOTA_THRESHOLD = 10
    
    // MARK: - 用户类型标识
    /// 免费用户类型
    static let USER_TYPE_FREE = "free"
    
    /// Pro用户类型
    static let USER_TYPE_PRO = "pro"
    
    /// Max用户类型
    static let USER_TYPE_MAX = "max" 
    
    /// 获取完整的套餐描述（用于UI显示）
    static func getPlanDescription() -> String {
        return "Free: \(FREE_MONTHLY_LIMIT)/month • Pro: \(PRO_MONTHLY_LIMIT)/month • Max: Unlimited"
    }
    
}
