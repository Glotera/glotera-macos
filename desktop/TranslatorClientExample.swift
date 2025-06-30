import Foundation

// MARK: - TranslatorClient Quota Usage Example

class TranslatorQuotaExample: TranslatorQuotaDelegate {
    
    func setupTranslatorClient() {
        // 设置配额委托
        TranslatorClient.shared.quotaDelegate = self
        
        // 检查用户类型
        if TranslatorClient.shared.isFreeUser() {
            print("当前为免费用户，每月限制200次翻译")
            
            // 获取当前配额状态
            TranslatorClient.shared.getUserQuota { result in
                switch result {
                case .success(let quotaInfo):
                    print("配额信息: \(quotaInfo.quotaDescription)")
                    if quotaInfo.isLowQuota {
                        self.showQuotaWarning(quotaInfo)
                    }
                case .failure(let error):
                    print("获取配额信息失败: \(error.localizedDescription)")
                }
            }
        } else {
            print("当前为Pro用户，享受无限制翻译")
        }
    }
    
    // MARK: - Translation Examples
    
    func performTranslation() {
        let text = "Hello world"
        
        // 使用新的翻译方法（包含配额信息）
        TranslatorClient.shared.translate(text: text, to: "zh") { result in
            switch result {
            case .success(let translationResult):
                print("翻译成功: \(translationResult.translated)")
                
                if let quotaInfo = translationResult.quotaInfo {
                    print("配额状态: \(quotaInfo.quotaDescription)")
                }
                
            case .failure(let error):
                switch error {
                case .quotaExceeded(let quotaInfo):
                    // 配额超限错误
                    self.handleQuotaExceeded(quotaInfo)
                    
                case .networkError(let message):
                    print("网络错误: \(message)")
                    
                case .serverError(let code, let message):
                    print("服务器错误 \(code): \(message)")
                    
                case .parseError(let message):
                    print("解析错误: \(message)")
                }
            }
        }
    }
    
    func performStreamTranslation() {
        let text = "This is a long text that will be translated using streaming mode"
        
        TranslatorClient.shared.translateStream(
            text: text,
            to: "zh",
            onChunk: { chunk, fullContent in
                // 处理流式数据块
                print("收到翻译片段: \(chunk)")
                print("当前完整内容: \(fullContent)")
            },
            onComplete: { finalResult, quotaInfo in
                // 翻译完成
                print("流式翻译完成: \(finalResult ?? "Empty result")")
                
                if let quotaInfo = quotaInfo {
                    print("配额状态: \(quotaInfo.quotaDescription)")
                }
            },
            onError: { error in
                print("流式翻译错误: \(error)")
            }
        )
    }
    
    // MARK: - TranslatorQuotaDelegate Implementation
    
    func didReceiveQuotaUpdate(_ quotaInfo: QuotaInfo) {
        DispatchQueue.main.async {
            print("配额更新: \(quotaInfo.quotaDescription)")
            
            // 可以在这里更新UI显示剩余次数
            self.updateQuotaDisplay(quotaInfo)
        }
    }
    
    func didReceiveQuotaWarning(_ quotaInfo: QuotaInfo) {
        DispatchQueue.main.async {
            print("配额警告: 剩余 \(quotaInfo.remainingQuota) 次翻译")
            self.showQuotaWarning(quotaInfo)
        }
    }
    
    func didReceiveQuotaExceededError(_ quotaInfo: QuotaInfo) {
        DispatchQueue.main.async {
            print("配额已用完!")
            self.handleQuotaExceeded(quotaInfo)
        }
    }
    
    // MARK: - UI Handlers
    
    private func updateQuotaDisplay(_ quotaInfo: QuotaInfo) {
        // 更新UI显示配额信息
        // 这里可以更新状态栏、设置窗口等UI元素
        print("更新UI: \(quotaInfo.quotaDescription)")
    }
    
    private func showQuotaWarning(_ quotaInfo: QuotaInfo) {
        // 显示配额警告对话框
        print("⚠️ 配额警告: \(quotaInfo.quotaStatusMessage ?? "")")
        
        // 可以显示一个非阻塞的通知或横幅
        // 建议用户升级到Pro版本
    }
    
    private func handleQuotaExceeded(_ quotaInfo: QuotaInfo) {
        // 处理配额超限情况
        print("🚫 配额已用完: \(quotaInfo.quotaStatusMessage ?? "")")
        
        // 可以显示升级对话框或禁用翻译功能
        // 直到下个月或用户升级到Pro版本
        self.showUpgradePrompt(quotaInfo)
    }
    
    private func showUpgradePrompt(_ quotaInfo: QuotaInfo) {
        // 显示升级到Pro版本的提示
        print("💡 升级提示: 升级到Pro版本享受无限制翻译")
        
        // 这里可以打开升级页面或显示购买对话框
    }
}

// MARK: - Backward Compatibility Example

class BackwardCompatibilityExample {
    
    func useOldTranslationMethod() {
        // 使用向后兼容的方法（只返回翻译文本）
        TranslatorClient.shared.translateText(text: "Hello", to: "zh") { result in
            switch result {
            case .success(let translated):
                print("翻译结果: \(translated)")
                
            case .failure(let error):
                print("翻译失败: \(error.localizedDescription)")
            }
        }
    }
    
    func useOldStreamMethod() {
        // 使用向后兼容的流式方法
        TranslatorClient.shared.translateStreamText(
            text: "Hello world",
            to: "zh",
            onChunk: { chunk, fullContent in
                print("片段: \(chunk)")
            },
            onComplete: { result in
                print("完成: \(result ?? "Empty")")
            },
            onError: { error in
                print("错误: \(error)")
            }
        )
    }
} 