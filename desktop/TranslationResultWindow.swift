import Cocoa
import SwiftUI

class TranslationResultWindow: NSWindow {
    private var hostingView: NSHostingView<TranslationResultView>?
    private var clickMonitor: Any?
    private var resultView: TranslationResultView?
    private var lastInteractionTime: Date = Date()
    
    // MARK: - Memory Management Integration
    
    private func recordInteraction() {
        lastInteractionTime = Date()
        // Interaction recording not needed in simplified version
    }
    
    init(original: String, translated: String) {
        // 动态计算窗口大小以适应内容
        let estimatedSize = Self.calculateWindowSize(original: original, translated: translated)
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: estimatedSize.width, height: estimatedSize.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = NSColor.clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true // 启用窗口拖动
        
        setupContent(original: original, translated: translated)
        setupClickOutsideMonitor()
        
        // Register with SimpleMemoryManager
        SimpleMemoryManager.shared.registerWindow(self)
    }
    
    init(originalText: String, targetLanguage: String) {
        // 初始窗口大小，宽度固定600px，高度会根据内容动态调整
        let initialSize = NSSize(width: 600, height: 200)
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: initialSize.width, height: initialSize.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = NSColor.clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        
        setupStreamContent(original: originalText, targetLanguage: targetLanguage)
        setupClickOutsideMonitor()
        
        // Register with SimpleMemoryManager
        SimpleMemoryManager.shared.registerWindow(self)
    }
    
    private func setupStreamContent(original: String, targetLanguage: String) {
        resultView = TranslationResultView(
            original: original,
            translated: "...", // 初始占位文本
            isStreaming: true,
            onCopy: { [weak self] text in
                self?.copyToClipboard(text)
            },
            onClose: { [weak self] in
                self?.hide()
            },
            onUpgradePrompt: { [weak self] in
                self?.showFollowupQuestionUpgradePrompt()
            }
        )
        
        // Set up chat toggle callback
        resultView?.viewModel.onChatToggle = { [weak self] in
            self?.handleChatToggle()
        }
        
        hostingView = NSHostingView(rootView: resultView!)
        self.contentView = hostingView
        
        // 开始流式翻译
        startStreamTranslation(original: original, to: targetLanguage)
    }
    
    private func handleChatToggle() {
        guard let resultView = self.resultView else { return }
        
        let newSize = Self.calculateWindowSize(
            original: resultView.original,
            translated: resultView.viewModel.translated,
            showingChat: resultView.viewModel.showingChat
        )
        
        let currentFrame = self.frame
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.visibleFrame
        
        // Calculate new position - expand upward to keep bottom visible
        var newY: CGFloat
        if resultView.viewModel.showingChat {
            // When enabling chat, expand upward
            newY = currentFrame.origin.y + currentFrame.height - newSize.height
            // Ensure the window doesn't go above screen bounds
            if newY < screenFrame.origin.y {
                newY = screenFrame.origin.y
            }
        } else {
            // When disabling chat, keep the top position and shrink downward
            newY = currentFrame.origin.y
            // Make sure the window fits on screen
            if newY + newSize.height > screenFrame.origin.y + screenFrame.height {
                newY = screenFrame.origin.y + screenFrame.height - newSize.height
            }
        }
        
        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: newY,
            width: currentFrame.width,  // 保持当前宽度不变
            height: newSize.height
        )
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.allowsImplicitAnimation = true
            self.setFrame(newFrame, display: true, animate: true)
        }
    }
    
    private func startStreamTranslation(original: String, to: String) {
         
        // 添加超时机制，防止状态卡住
        var isCompleted = false
        var lastContent = ""
        let timeoutTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            if !isCompleted {
                Logger.info("Stream translation timeout detected")
                // 如果有内容，使用最后的内容；否则显示超时信息
                if !lastContent.isEmpty {
                    Logger.info("Using last received content as final result: '\(lastContent)'")
                    self?.completeStreamTranslation(lastContent)
                } else {
                    Logger.info("No content received, showing timeout message")
                    self?.completeStreamTranslation("Translation timeout")
                }
            }
        }
        
        TranslatorClient.shared.translateStream(
            text: original,
            to: to,
            onChunk: { [weak self] chunk, fullContent in
                // 实时更新翻译内容
                lastContent = fullContent 
                DispatchQueue.main.async {
                    self?.updateStreamContent(fullContent)
                }
            },
            onComplete: { [weak self] finalResult, quotaInfo in
                // 翻译完成
                isCompleted = true
                timeoutTimer.invalidate()
                
                let result = finalResult ?? lastContent
                Logger.info("Stream translation completed: '\(result)'")
                DispatchQueue.main.async {
                    self?.completeStreamTranslation(result)
                }
            },
            onError: { [weak self] errorMessage in
                // 翻译出错
                isCompleted = true
                timeoutTimer.invalidate()
                
                Logger.info("Stream translation error: '\(errorMessage)'")
                DispatchQueue.main.async {
                    // 如果是配额耗尽错误，直接关闭翻译浮窗
                    if errorMessage.contains("翻译次数已用完") || errorMessage.contains("quota") {
                        Logger.info("Quota exceeded in stream translation, hiding result window")
                        self?.hide()
                    } else if errorMessage.contains("Authentication required") || errorMessage.contains("sign in") {
                        // 认证错误，直接关闭翻译浮窗，让登录提示显示
                        Logger.info("Authentication required in stream translation, hiding result window")
                        self?.hide()
                    } else {
                        // 其他错误显示错误信息
                        self?.handleStreamError(errorMessage)
                    }
                }
                
            }
        )
    }
    
    private func updateStreamContent(_ content: String) {
        guard let resultView = self.resultView else {
            Logger.info("Warning: resultView is nil in updateStreamContent")
            return
        }

        // Debug: Log the raw content to see what we're actually receiving
        Logger.debug("🔍 Raw stream content received (length: \(content.count))")
        if content.contains("\n\n") {
            Logger.debug("✅ Content contains \\n\\n (double newlines)")
            let paragraphs = content.components(separatedBy: "\n\n")
            Logger.debug("📊 Found \(paragraphs.count) paragraphs")
        } else if content.contains("\\n\\n") {
            Logger.debug("⚠️ Content contains escaped \\\\n\\\\n")
        } else if content.contains("\n") {
            Logger.debug("📝 Content contains single newlines only")
        } else {
            Logger.debug("❌ Content has no newlines")
        }

        // 确保在主线程更新UI
        if Thread.isMainThread {
            resultView.viewModel.updateTranslation(content, isStreaming: true)
            
            // 根据内容动态调整窗口大小，使用优化的调整逻辑
            let newSize = Self.calculateWindowSize(
                original: resultView.original, 
                translated: content,
                showingChat: resultView.viewModel.showingChat
            )
            let currentFrame = self.frame
            
            // 只有在高度有显著变化时才调整窗口（避免频繁调整）
            let sizeThreshold: CGFloat = 20
            if abs(newSize.height - currentFrame.height) > sizeThreshold {
                let screen = NSScreen.main ?? NSScreen.screens.first!
                let screenFrame = screen.visibleFrame
                
                // Smart positioning to keep window on screen
                var newY = currentFrame.origin.y + currentFrame.height - newSize.height
                if newY < screenFrame.origin.y {
                    newY = screenFrame.origin.y
                }
                
                let newFrame = NSRect(
                    x: currentFrame.origin.x,
                    y: newY,
                    width: currentFrame.width,  // 保持当前宽度不变
                    height: newSize.height     // 只调整高度
                )
                
                // 使用更平滑的动画
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    context.allowsImplicitAnimation = true
                    self.setFrame(newFrame, display: true, animate: true)
                }
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.updateStreamContent(content)
            }
        }
    }
    
    private func completeStreamTranslation(_ finalResult: String) {
        guard let resultView = self.resultView else {
            Logger.info("Warning: resultView is nil in completeStreamTranslation")
            return
        }
        
        // 确保在主线程更新UI
        if Thread.isMainThread { 
            resultView.viewModel.updateTranslation(finalResult, isStreaming: false)
            
            // 完成时进行最终的窗口大小调整以适应完整的翻译内容
            let finalSize = Self.calculateWindowSize(
                original: resultView.original, 
                translated: finalResult,
                showingChat: resultView.viewModel.showingChat
            )
            let currentFrame = self.frame
            let screen = NSScreen.main ?? NSScreen.screens.first!
            let screenFrame = screen.visibleFrame
            
            // Smart positioning for final adjustment
            var newY = currentFrame.origin.y + currentFrame.height - finalSize.height
            if newY < screenFrame.origin.y {
                newY = screenFrame.origin.y
            }
            
            let finalFrame = NSRect(
                x: currentFrame.origin.x,
                y: newY,
                width: finalSize.width,
                height: finalSize.height
            )
            
            // 使用稍慢的动画来完成最终调整
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.allowsImplicitAnimation = true
                self.setFrame(finalFrame, display: true, animate: true)
            }
            
            // 流式翻译完成后清除缓存的应用信息
            EnvironmentManager.shared.clearTriggerAppInfo()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.completeStreamTranslation(finalResult)
            }
        }
    }
    
    private func handleStreamError(_ errorMessage: String) {
        DispatchQueue.main.async { [weak self] in
            let errorText = "Translation failed: \(errorMessage)"
            self?.resultView?.viewModel.updateTranslation(errorText, isStreaming: false)
            Logger.info("Stream translation error in window: \(errorMessage)")
            // 流式翻译错误后也清除缓存的应用信息
            EnvironmentManager.shared.clearTriggerAppInfo()
        }
    }
    
    // 设置点击外部区域监听
    private func setupClickOutsideMonitor() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.isVisible else { return }
            
            let clickLocation = NSEvent.mouseLocation
            let windowFrame = self.frame
            
            // 如果点击在窗口外部，隐藏窗口
            if !windowFrame.contains(clickLocation) {
                DispatchQueue.main.async {
                    self.hide()
                }
            }
        }
    }
    
    func show() {
        // 将窗口居中显示在主屏幕上
        if let mainScreen = NSScreen.main {
            let screenFrame = mainScreen.visibleFrame
            let windowFrame = self.frame
            let x = screenFrame.origin.x + (screenFrame.width - windowFrame.width) / 2
            let y = screenFrame.origin.y + (screenFrame.height - windowFrame.height) / 2
            self.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        self.orderFront(nil)
        self.makeKey()
        
        // Record interaction with MemoryManager
        recordInteraction()
        
        Logger.info("Translation result window shown at screen center")
    }
    
    func showAt(point: NSPoint) {
        // 获取鼠标所在的屏幕
        let mouseScreen = NSScreen.screens.first { screen in
            screen.frame.contains(point)
        } ?? NSScreen.main
        
        // 获取屏幕可见区域（排除Dock和菜单栏）
        let screenFrame = mouseScreen?.visibleFrame ?? NSRect.zero
        let windowSize = self.frame.size
        let margin: CGFloat = 20 // 边缘留白
        
        var resultPoint = point
        
        // 智能位置计算：优先显示在鼠标右下方
        var preferredX = point.x + 10 // 稍微偏右
        var preferredY = point.y - 60 // 稍微偏下
        
        // 水平位置调整
        if preferredX + windowSize.width + margin > screenFrame.maxX {
            // 右侧空间不足，尝试显示在左侧
            preferredX = point.x - windowSize.width - 10
            if preferredX < screenFrame.minX + margin {
                // 左侧也不足，强制在屏幕范围内
                preferredX = screenFrame.minX + margin
            }
        }
        
        // 确保不超出左边界
        if preferredX < screenFrame.minX + margin {
            preferredX = screenFrame.minX + margin
        }
        
        // 垂直位置调整
        if preferredY - windowSize.height < screenFrame.minY + margin {
            // 下方空间不足，显示在鼠标上方
            preferredY = point.y + 60
            if preferredY > screenFrame.maxY - margin {
                // 上方也不足，强制在屏幕范围内
                preferredY = screenFrame.maxY - margin
            }
        }
        
        // 确保不超出上边界
        if preferredY > screenFrame.maxY - margin {
            preferredY = screenFrame.maxY - margin
        }
        
        // 最终检查：确保窗口完全在屏幕内
        if preferredX + windowSize.width > screenFrame.maxX {
            preferredX = screenFrame.maxX - windowSize.width - margin
        }
        if preferredY - windowSize.height < screenFrame.minY {
            preferredY = screenFrame.minY + windowSize.height + margin
        }
        
        resultPoint = NSPoint(x: preferredX, y: preferredY)
        
        self.setFrameTopLeftPoint(resultPoint)
        self.orderFront(nil)
        self.makeKey()
        
        // Record interaction with MemoryManager
        recordInteraction()
    }
    
    func hide() {
        self.orderOut(nil)
        
        // 清理点击监听
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        
        // Unregister from SimpleMemoryManager
        SimpleMemoryManager.shared.unregisterWindow(self)
        
        Logger.debug("Translation result window hidden")
    }
    
    deinit {
        // 确保在销毁时清理监听
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        
        // Note: Don't unregister in deinit to avoid crashes with deallocated objects
        // The no-op SimpleMemoryManager handles this safely
        
        Logger.debug("TranslationResultWindow deinitialized")
    }
    
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        Logger.info("Copied to clipboard: \(text)")
        
        // Record interaction
        recordInteraction()
        
        // 复制后关闭翻译浮窗
        self.hide()
    }
    
    private func showFollowupQuestionUpgradePrompt() {
        let alert = NSAlert()
        alert.messageText = "Follow-up Question"
        alert.informativeText = "Follow-up Question feature is only available for Pro and Max users."
        alert.alertStyle = .informational
        
        // Add buttons
        alert.addButton(withTitle: "Upgrade Now")
        alert.addButton(withTitle: "Cancel")
        
        // Set the window as parent for the alert
        alert.beginSheetModal(for: self) { response in
            if response == .alertFirstButtonReturn {
                // User clicked "Upgrade Now"
                EnvironmentManager.shared.openUpgradePage()
            }
            // User clicked "Cancel" or closed the dialog - do nothing
        }
    }
    
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return false
    }
    
    // MARK: - Event Tracking for Memory Management
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        recordInteraction()
    }
    
    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        recordInteraction()
    }
    
    override func keyDown(with event: NSEvent) {
        super.keyDown(with: event)
        recordInteraction()
    }
    
    override func becomeKey() {
        super.becomeKey()
        recordInteraction()
    }
    
    // 重写方法以控制窗口焦点行为，确保拖动时不会意外隐藏
    override func resignKey() {
        // 不调用super，防止窗口在失去焦点时被自动隐藏
        // 用户需要通过点击关闭按钮或点击外部区域来关闭
    }
    
    // 计算窗口大小以适应内容
    private static func calculateWindowSize(original: String, translated: String, showingChat: Bool = false) -> NSSize {
        let fixedWidth: CGFloat = 600  // 固定宽度600px
        
        if showingChat {
            // When chat is active, use a larger fixed proportional layout
            // Total height: 600px (1:2 ratio - 200px for translation, 400px for chat)
            return NSSize(width: fixedWidth, height: 600)
        }
        
        // Original dynamic calculation for translation-only view
        let padding: CGFloat = 24 
        let verticalSpacing: CGFloat = 80 
        
        // 计算文本所需的高度
        let font = NSFont.systemFont(ofSize: 13)
        let textWidth = fixedWidth - padding - 16 // 减去文本框内部padding
        
        let originalHeight = original.boundingRect(
            with: NSSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        ).height
        
        let translatedHeight = translated.boundingRect(
            with: NSSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        ).height
        
        // 确保每个文本框至少有合适的高度，并为ScrollView预留空间
        let minTextHeight: CGFloat = 25 
        // 增加最大文本高度以适应长翻译，特别是在流式模式下
        let maxTextHeight: CGFloat = max(200, min(translatedHeight + 20, 400)) // 动态调整最大高度
        let finalOriginalHeight = min(max(originalHeight + 15, minTextHeight), 120) // 原文保持较小高度
        let finalTranslatedHeight = min(max(translatedHeight + 15, minTextHeight), maxTextHeight)
        
        // 计算基础翻译内容的高度
        let translationHeight = verticalSpacing + finalOriginalHeight + finalTranslatedHeight + 30 
        
        // 增加最大高度限制以适应长翻译
        let maxHeight: CGFloat = min(translationHeight, 600)
        let finalHeight = max(maxHeight, 150) 
        
        return NSSize(width: fixedWidth, height: finalHeight)
    }
    
    private func setupContent(original: String, translated: String) {
        let resultView = TranslationResultView(
            original: original,
            translated: translated,
            isStreaming: false,
            onCopy: { [weak self] text in
                self?.copyToClipboard(text)
            },
            onClose: { [weak self] in
                self?.hide()
            },
            onUpgradePrompt: { [weak self] in
                self?.showFollowupQuestionUpgradePrompt()
            }
        )
        
        // Set up chat toggle callback
        resultView.viewModel.onChatToggle = { [weak self] in
            self?.handleChatToggle()
        }
        
        hostingView = NSHostingView(rootView: resultView)
        self.contentView = hostingView
        self.resultView = resultView
    }
}

// MARK: - Chat Models
struct ChatBubbleMessage: Identifiable {
    let id = UUID()
    let content: String
    let isFromUser: Bool
    let timestamp: Date
    
    init(content: String, isFromUser: Bool) {
        self.content = content
        self.isFromUser = isFromUser
        self.timestamp = Date()
    }
}

class TranslationResultViewModel: ObservableObject {
    @Published var translated: String
    @Published var isStreaming: Bool
    @Published var chatMessages: [ChatBubbleMessage] = []
    @Published var showingChat: Bool = false
    @Published var isChatLoading: Bool = false
    
    private let originalText: String
    
    init(translated: String, isStreaming: Bool, originalText: String = "") {
        self.translated = translated
        self.isStreaming = isStreaming
        self.originalText = originalText
        Logger.info("TranslationResultViewModel initialized with isStreaming: \(isStreaming)")
    }
    
    func updateTranslation(_ newTranslation: String, isStreaming: Bool) {
         
        // 确保在主线程更新
        if Thread.isMainThread {
            self.translated = newTranslation
            self.isStreaming = isStreaming
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.updateTranslation(newTranslation, isStreaming: isStreaming)
            }
        }
    }
    
    var onChatToggle: (() -> Void)?
    
    func toggleChat() {
        // Only allow Follow-up Question toggle for Pro/Max users
        guard SessionManager.shared.hasFollowupQuestionAccess() else {
            Logger.info("Follow-up Question toggle blocked - user doesn't have Follow-up Question access")
            return
        }
        
        showingChat.toggle()
        onChatToggle?()
    }
    
    func sendChatMessage(_ message: String) {
        // Only allow Follow-up Question messages for Pro/Max users
        guard SessionManager.shared.hasFollowupQuestionAccess() else {
            Logger.info("Follow-up Question message blocked - user doesn't have Follow-up Question access")
            return
        }
        
        // Add user message
        let userMessage = ChatBubbleMessage(content: message, isFromUser: true)
        chatMessages.append(userMessage)
        
        // Set loading state
        isChatLoading = true
        
        // Build conversation history from existing messages
        var conversationHistory: [(userMessage: String, aiResponse: String)] = []
        
        // Group messages into conversation pairs
        var i = 0
        while i < chatMessages.count - 1 { // Exclude the message we just added
            let currentMessage = chatMessages[i]
            if currentMessage.isFromUser && i + 1 < chatMessages.count {
                let nextMessage = chatMessages[i + 1]
                if !nextMessage.isFromUser {
                    // Found a user-AI pair
                    conversationHistory.append((
                        userMessage: currentMessage.content,
                        aiResponse: nextMessage.content
                    ))
                    i += 2 // Skip both messages
                } else {
                    i += 1 // Skip lone user message
                }
            } else {
                i += 1 // Skip AI message or continue
            }
        }
        
        // Add temporary AI message for streaming updates
        let aiMessage = ChatBubbleMessage(content: "", isFromUser: false)
        chatMessages.append(aiMessage)
        let aiMessageIndex = chatMessages.count - 1
        
        // Send to chat API with streaming support
        TranslatorClient.shared.chat(
            message: message,
            originalText: originalText,
            translatedText: translated,
            conversationHistory: conversationHistory,
            onStreamUpdate: { [weak self] streamContent in
                DispatchQueue.main.async {
                    // Update the AI message content with streaming data
                    if let strongSelf = self, aiMessageIndex < strongSelf.chatMessages.count {
                        strongSelf.chatMessages[aiMessageIndex] = ChatBubbleMessage(
                            content: streamContent,
                            isFromUser: false
                        )
                    }
                }
            },
            completion: { [weak self] result in
                DispatchQueue.main.async {
                    self?.isChatLoading = false
                    
                    switch result {
                    case .success(let finalResponse):
                        // Update with final response if different
                        if let strongSelf = self, aiMessageIndex < strongSelf.chatMessages.count {
                            strongSelf.chatMessages[aiMessageIndex] = ChatBubbleMessage(
                                content: finalResponse,
                                isFromUser: false
                            )
                        }
                    case .failure(let error):
                        // Replace the empty AI message with error message
                        if let strongSelf = self, aiMessageIndex < strongSelf.chatMessages.count {
                            strongSelf.chatMessages[aiMessageIndex] = ChatBubbleMessage(
                                content: "Error: \(error.localizedDescription)",
                                isFromUser: false
                            )
                        }
                    }
                }
            }
        )
    }
}

struct TranslationResultView: View {
    let original: String
    @ObservedObject var viewModel: TranslationResultViewModel
    let onCopy: (String) -> Void
    let onClose: () -> Void
    let onUpgradePrompt: () -> Void
    
    @State private var showingCopySuccess = false
    
    init(original: String, translated: String, isStreaming: Bool, onCopy: @escaping (String) -> Void, onClose: @escaping () -> Void, onUpgradePrompt: @escaping () -> Void) {
        self.original = original
        self.viewModel = TranslationResultViewModel(translated: translated, isStreaming: isStreaming, originalText: original)
        self.onCopy = onCopy
        self.onClose = onClose
        self.onUpgradePrompt = onUpgradePrompt
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // 标题栏（可拖动）
            HStack {
                Image(systemName: "hand.draw")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.6))
                    .help("Drag to move window")
                
                Text(viewModel.showingChat ? "Follow-up Question" : "Translation Result")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Follow-up Question toggle button (Pro/Max only)
                if SessionManager.shared.hasFollowupQuestionAccess() {
                    Button(action: {
                        viewModel.toggleChat()
                    }) {
                        Image(systemName: viewModel.showingChat ? "text.bubble.fill" : "text.bubble")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Toggle Follow-up Question")
                    .onHover { isHovered in
                        if isHovered {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                } else {
                    // Show upgrade hint for free users
                    Button(action: {
                        onUpgradePrompt()
                    }) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Follow-up Question (Pro/Max feature) - Click to upgrade")
                    .onHover { isHovered in
                        if isHovered {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                }
                
                // 复制按钮
                Button(action: {
                    onCopy(viewModel.translated)
                    showCopyFeedback()
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Copy to clipboard")
                .onHover { isHovered in
                    if isHovered {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { isHovered in
                    if isHovered {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
            .padding(.vertical, 2)
            .onHover { isHovered in
                if isHovered {
                    NSCursor.openHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            
            // Main content area with proportional layout when chat is active
            if viewModel.showingChat && SessionManager.shared.hasFollowupQuestionAccess() {
                // When chat is active and user has access: 1:2 ratio (translation:chat) in 600px window
                VStack(spacing: 0) {
                    // Translation content (200px out of 600px = 1/3 of total window)
                    TranslationContentView(original: original, viewModel: viewModel)
                        .frame(height: 200) // Fixed height for consistent 1:2 ratio
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    // Chat section (400px out of 600px = 2/3 of total window) 
                    ExpandedChatSection(viewModel: viewModel)
                        .frame(maxHeight: .infinity) // Takes remaining space (~396px after divider)
                }
            } else {
                // When chat is inactive or user doesn't have access: full space for translation
                TranslationContentView(original: original, viewModel: viewModel)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
        .overlay(
            // 复制成功提示
            Group {
                if showingCopySuccess {
                    Text("Copied")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.green)
                        )
                        .foregroundColor(.white)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showingCopySuccess),
            alignment: .center
        )
    }
    
    private func showCopyFeedback() {
        showingCopySuccess = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            showingCopySuccess = false
        }
    }
}

// MARK: - Translation Content View
struct TranslationContentView: View {
    let original: String
    @ObservedObject var viewModel: TranslationResultViewModel
    
    // Process translation text to handle newlines and basic formatting without markdown rendering
    // processedTranslationText function removed - now handled by TranslationMarkdownText
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 原文 - blockquote风格
            HStack(alignment: .center, spacing: 12) {
                // 左侧引用线
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 3, height: 20)
                    .cornerRadius(1.5)
                
                // 原文内容 - 只显示一行作为参考
                Text(original)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1) // Always show only first line
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            
            // 译文
            VStack(alignment: .leading, spacing: 4) {
                ScrollView {
                    HStack(alignment: .top) {
                        // Use TranslationMarkdownText for better formatting
                        TranslationMarkdownText(markdown: viewModel.translated)
                            .textSelection(.enabled)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4) // Add vertical padding for better visual separation
                        
                        // 流式翻译指示器
                        if viewModel.isStreaming {
                            Text("|")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.blue)
                                .opacity(0.8)
                                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: viewModel.isStreaming)
                                .padding(.top, 4) // Align with text content
                        }
                    }
                }
                .frame(minHeight: 30, maxHeight: viewModel.showingChat ? 180 : 400) // More space when chat is active
                
                // 流式状态指示
                if viewModel.isStreaming {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Translating...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                }
            }
        }
        .frame(maxHeight: viewModel.showingChat ? 200 : .infinity) // Increased height for 1:2 ratio (200px out of 600px)
    }
}

// MARK: - Chat Input Section (shows below translation)
struct ChatInputSection: View {
    @ObservedObject var viewModel: TranslationResultViewModel
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            Divider()
                .padding(.top, 8)
            
            // Chat messages (compact view - only recent messages)
            if !viewModel.chatMessages.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(viewModel.chatMessages.suffix(2)) { message in
                                CompactChatMessageView(message: message)
                            }
                            
                            // Loading indicator
                            if viewModel.isChatLoading {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("AI is thinking...")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .id("loading")
                            }
                            
                            // Bottom anchor
                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                        .padding(.horizontal, 4)
                    }
                    .frame(maxHeight: 120) // Compact height to show only recent messages
                    .onChange(of: viewModel.chatMessages.count) { _ in
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                    .onChange(of: viewModel.isChatLoading) { isLoading in
                        if isLoading {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo("loading", anchor: .bottom)
                            }
                        }
                    }
                }
            }
            
            // Input area
            HStack(spacing: 8) {
                TextField("Ask follow-up questions about this translation...", text: $inputText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($isInputFocused)
                    .onSubmit {
                        sendMessage()
                    }
                
                Button("Send") {
                    sendMessage()
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isChatLoading)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 4)
        }
        .onAppear {
            isInputFocused = true
        }
    }
    
    private func sendMessage() {
        let message = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty && !viewModel.isChatLoading else { return }
        
        inputText = ""
        viewModel.sendChatMessage(message)
    }
}

// MARK: - Expanded Chat Section (2/3 of window space)
struct ExpandedChatSection: View {
    @ObservedObject var viewModel: TranslationResultViewModel
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            // Chat messages (expanded view - shows all messages)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(viewModel.chatMessages) { message in
                            ChatMessageView(message: message)
                        }
                        
                        // Loading indicator
                        if viewModel.isChatLoading {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("AI is thinking...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .id("loading")
                        }
                        
                        // Bottom anchor
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity) // Take all available space
                .onChange(of: viewModel.chatMessages.count) { _ in
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.isChatLoading) { isLoading in
                    if isLoading {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("loading", anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
                .padding(.horizontal, 8)
            
            // Input area (fixed at bottom)
            HStack(spacing: 10) {
                TextField("Ask follow-up questions about this translation...", text: $inputText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($isInputFocused)
                    .onSubmit {
                        sendMessage()
                    }
                
                Button("Send") {
                    sendMessage()
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isChatLoading)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
        .frame(maxHeight: .infinity) // Fill available space
        .onAppear {
            isInputFocused = true
        }
    }
    
    private func sendMessage() {
        let message = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty && !viewModel.isChatLoading else { return }
        
        inputText = ""
        viewModel.sendChatMessage(message)
    }
}

// MARK: - Compact Chat Message View (for input section)
struct CompactChatMessageView: View {
    let message: ChatBubbleMessage
    
    var body: some View {
        HStack {
            if message.isFromUser {
                Spacer()
            }
            
            VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 2) {
                if message.isFromUser {
                    // User messages - handle newlines properly
                    Text(message.content)
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue)
                        )
                        .textSelection(.enabled)
                        .lineLimit(3) // Limit lines for compact view
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // AI messages - markdown rendering
                    MarkdownText(markdown: message.content)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                        .lineSpacing(3) // Increased line spacing for better readability
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                        .textSelection(.enabled)
                        // Remove lineLimit to allow full content display
                }
                
                Text(formatTime(message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .opacity(0.6)
                    .padding(.horizontal, 2)
            }
            .frame(maxWidth: 340, alignment: message.isFromUser ? .trailing : .leading)
            
            if !message.isFromUser {
                Spacer()
            }
        }
        .padding(.vertical, 2)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Chat Message View
struct ChatMessageView: View {
    let message: ChatBubbleMessage
    
    var body: some View {
        HStack {
            if message.isFromUser {
                Spacer()
            }
            
            VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 4) {
                if message.isFromUser {
                    // User messages - handle newlines properly
                    Text(message.content)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.blue)
                        )
                        .textSelection(.enabled)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // AI messages - markdown rendering
                    MarkdownText(markdown: message.content)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .lineSpacing(3) // Add line spacing for better readability
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                        .textSelection(.enabled)
                }
                
                Text(formatTime(message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .opacity(0.7)
                    .padding(.horizontal, 4)
            }
            .frame(maxWidth: 480, alignment: message.isFromUser ? .trailing : .leading)
            
            if !message.isFromUser {
                Spacer()
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Markdown Text Renderer (Optimized for better formatting)
struct MarkdownText: View {
    let markdown: String
    
    // Preprocess content to handle newlines properly
    private var processedText: String {
        var result = markdown
        
        // Handle escaped newlines if they exist
        if result.contains("\\n") {
            result = result.replacingOccurrences(of: "\\n", with: "\n")
        }
        
        // Normalize different line break formats to standard \n
        result = result.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "\n")
        
        // Normalize smart quotes to standard quotes
        result = result.replacingOccurrences(of: "\u{201C}", with: "\"")
        result = result.replacingOccurrences(of: "\u{201D}", with: "\"")
        result = result.replacingOccurrences(of: "\u{2018}", with: "'")
        result = result.replacingOccurrences(of: "\u{2019}", with: "'")
        
        return result
    }
    
    var body: some View {
        // Use custom rendering that properly handles newlines
        renderTextWithNewlines(processedText)
    }
    
    // Custom text renderer that properly handles \n and \n\n
    private func renderTextWithNewlines(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(parseTextBlocks(text).enumerated()), id: \.offset) { index, block in
                switch block.type {
                case .paragraph:
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(block.lines.enumerated()), id: \.offset) { lineIndex, line in
                            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                                if #available(macOS 12.0, *) {
                                    // Try to render with markdown for formatting
                                    if let attributedString = try? AttributedString(markdown: line) {
                                        Text(attributedString)
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                    } else {
                                        Text(line)
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                } else {
                                    Text(line)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding(.bottom, block.isLastParagraph ? 0 : 8) // Add spacing between paragraphs
                    
                case .separator:
                    Divider()
                        .padding(.vertical, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // Parse text into blocks handling \n and \n\n correctly
    private func parseTextBlocks(_ text: String) -> [TextBlock] {
        var blocks: [TextBlock] = []
        
        // Split by double newlines to get paragraphs
        let paragraphs = text.components(separatedBy: "\n\n")
        
        for (index, paragraph) in paragraphs.enumerated() {
            let trimmedParagraph = paragraph.trimmingCharacters(in: .whitespaces)
            
            if trimmedParagraph.isEmpty {
                continue
            }
            
            // Check if it's a horizontal rule
            if trimmedParagraph == "---" {
                blocks.append(TextBlock(type: .separator, lines: [], isLastParagraph: false))
            } else {
                // Split paragraph by single newlines to get lines
                let lines = paragraph.components(separatedBy: "\n")
                let isLast = (index == paragraphs.count - 1)
                blocks.append(TextBlock(type: .paragraph, lines: lines, isLastParagraph: isLast))
            }
        }
        
        return blocks
    }
    
    // Helper structures for text parsing
    private struct TextBlock {
        enum BlockType {
            case paragraph
            case separator
        }
        
        let type: BlockType
        let lines: [String]
        let isLastParagraph: Bool
    }
}

// MARK: - Translation Markdown Text Renderer (based on ImageMarkdownText)
struct TranslationMarkdownText: View {
    let markdown: String

    // Preprocess content to handle newlines properly
    private var processedText: String {
        var result = markdown

        // Debug logging to understand what we're processing
        Logger.debug("🎨 TranslationMarkdownText processing text (length: \(result.count))")

        // Check what kind of newlines we have before processing
        if result.contains("\n\n") {
            Logger.debug("✅ Text already contains real \\n\\n")
        } else if result.contains("\\n\\n") {
            Logger.debug("⚠️ Text contains escaped \\\\n\\\\n - will convert to real newlines")
        }

        // Handle escaped newlines if they exist
        // IMPORTANT: Process \\n\\n first before single \\n to preserve paragraph breaks
        if result.contains("\\n\\n") {
            result = result.replacingOccurrences(of: "\\n\\n", with: "\n\n")
            Logger.debug("📝 Converted \\\\n\\\\n to real paragraph breaks")
        } else if result.contains("\\n") {
            result = result.replacingOccurrences(of: "\\n", with: "\n")
            Logger.debug("📝 Converted \\\\n to real newlines")
        }

        // Normalize different line break formats to standard \n
        result = result.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "\n")

        // Normalize smart quotes to standard quotes
        result = result.replacingOccurrences(of: "\u{201C}", with: "\"")
        result = result.replacingOccurrences(of: "\u{201D}", with: "\"")
        result = result.replacingOccurrences(of: "\u{2018}", with: "'")
        result = result.replacingOccurrences(of: "\u{2019}", with: "'")

        // Final debug check
        if result.contains("\n\n") {
            let paragraphs = result.components(separatedBy: "\n\n")
            Logger.debug("📊 After processing: \(paragraphs.count) paragraphs found")
        }

        return result
    }

    var body: some View {
        // Use custom rendering that properly handles newlines
        renderTextWithNewlines(processedText)
    }

    // Custom text renderer that properly handles markdown headers and formatting
    private func renderTextWithNewlines(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parseMarkdownElements(text).enumerated()), id: \.offset) { index, element in
                Group {
                    switch element.type {
                    case .header:
                        Text(element.content)
                            .font(.system(size: 15, weight: .semibold))
                            .fontWeight(.bold)
                            .padding(.vertical, 2)
                    case .paragraph:
                        // Use custom text rendering with better bold formatting
                        renderFormattedText(element.content)
                            .font(.system(size: 14))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(6)
                    case .listItem:
                        // Render list item with bullet point
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                                .padding(.top, 1)

                            renderFormattedText(element.content)
                                .font(.system(size: 14))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineSpacing(6)
                        }
                        .padding(.vertical, 1)
                    case .separator:
                        Divider()
                            .padding(.vertical, 4)
                    case .emptyLine:
                        // Preserve empty lines as vertical spacing with more visible spacing
                        Spacer()
                            .frame(height: 20) // More visible paragraph spacing
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Render text with proper bold formatting
    private func renderFormattedText(_ text: String) -> Text {
        // Parse bold text patterns manually for better control
        let parts = parseBoldText(text)

        if parts.count == 1 && !parts[0].isBold {
            // Simple case: no formatting needed
            return Text(parts[0].content)
        }

        // Build attributed text by combining parts
        var result = Text("")
        for part in parts {
            if part.isBold {
                result = result + Text(part.content).fontWeight(.bold)
            } else {
                result = result + Text(part.content)
            }
        }

        return result
    }

    // Parse text for bold formatting (** text **)
    private func parseBoldText(_ text: String) -> [TextPart] {
        var parts: [TextPart] = []
        var currentText = ""
        var i = text.startIndex

        while i < text.endIndex {
            if i < text.index(text.endIndex, offsetBy: -1) &&
               text[i] == "*" && text[text.index(after: i)] == "*" {

                // Found start of potential bold section
                if !currentText.isEmpty {
                    parts.append(TextPart(content: currentText, isBold: false))
                    currentText = ""
                }

                // Look for closing **
                let startIndex = text.index(i, offsetBy: 2)
                var endIndex = startIndex
                var foundClosing = false

                while endIndex < text.index(text.endIndex, offsetBy: -1) {
                    if text[endIndex] == "*" && text[text.index(after: endIndex)] == "*" {
                        foundClosing = true
                        break
                    }
                    endIndex = text.index(after: endIndex)
                }

                if foundClosing {
                    // Extract bold content
                    let boldContent = String(text[startIndex..<endIndex])
                    if !boldContent.isEmpty {
                        parts.append(TextPart(content: boldContent, isBold: true))
                    }
                    i = text.index(endIndex, offsetBy: 2) // Skip closing **
                } else {
                    // No closing **, treat as regular text
                    currentText.append(text[i])
                    i = text.index(after: i)
                }
            } else {
                currentText.append(text[i])
                i = text.index(after: i)
            }
        }

        // Add remaining text
        if !currentText.isEmpty {
            parts.append(TextPart(content: currentText, isBold: false))
        }

        return parts.isEmpty ? [TextPart(content: text, isBold: false)] : parts
    }

    // Parse text into markdown elements (headers, paragraphs, separators)
    private func parseMarkdownElements(_ text: String) -> [MarkdownElement] {
        var elements: [MarkdownElement] = []

        // Debug logging
        Logger.debug("🔍 parseMarkdownElements: Processing text with length \(text.count)")

        // Split by double newlines to preserve paragraph breaks
        let paragraphs = text.components(separatedBy: "\n\n")
        Logger.debug("📊 Found \(paragraphs.count) paragraphs in markdown")

        for (index, paragraph) in paragraphs.enumerated() {
            // Skip completely empty paragraphs
            if paragraph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Logger.debug("⏭️ Skipping empty paragraph at index \(index)")
                continue
            }

            Logger.debug("📝 Processing paragraph \(index + 1)/\(paragraphs.count) with \(paragraph.count) chars")

            // Process each paragraph line by line
            let lines = paragraph.components(separatedBy: "\n")
            var currentParagraphLines: [String] = []

            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)

                // Check if it's a horizontal rule
                if trimmedLine == "---" {
                    // Add any accumulated paragraph content first
                    if !currentParagraphLines.isEmpty {
                        let content = currentParagraphLines.joined(separator: "\n")
                        elements.append(MarkdownElement(type: .paragraph, content: content))
                        currentParagraphLines.removeAll()
                    }
                    elements.append(MarkdownElement(type: .separator, content: ""))
                    continue
                }

                // Check if it's a header (starts with #)
                if trimmedLine.hasPrefix("#") {
                    // Add any accumulated paragraph content first
                    if !currentParagraphLines.isEmpty {
                        let content = currentParagraphLines.joined(separator: "\n")
                        elements.append(MarkdownElement(type: .paragraph, content: content))
                        currentParagraphLines.removeAll()
                    }

                    // Extract header content (remove # characters and leading whitespace)
                    var headerContent = trimmedLine
                    while headerContent.hasPrefix("#") {
                        headerContent = String(headerContent.dropFirst())
                    }
                    headerContent = headerContent.trimmingCharacters(in: .whitespaces)

                    if !headerContent.isEmpty {
                        elements.append(MarkdownElement(type: .header, content: headerContent))
                    }
                    continue
                }

                // Check if it's a list item (starts with -)
                if trimmedLine.hasPrefix("-") {
                    // Add any accumulated paragraph content first
                    if !currentParagraphLines.isEmpty {
                        let content = currentParagraphLines.joined(separator: "\n")
                        elements.append(MarkdownElement(type: .paragraph, content: content))
                        currentParagraphLines.removeAll()
                    }

                    // Extract list item content safely (remove - and leading whitespace)
                    var listItemContent = ""
                    if trimmedLine.hasPrefix("-") && trimmedLine.count > 1 {
                        listItemContent = String(trimmedLine.dropFirst()).trimmingCharacters(in: .whitespaces)
                    }

                    if !listItemContent.isEmpty {
                        elements.append(MarkdownElement(type: .listItem, content: listItemContent))
                    }
                    continue
                }

                // Regular line - add to current paragraph (preserve original line with spacing)
                currentParagraphLines.append(line)
            }

            // Add any remaining paragraph content
            if !currentParagraphLines.isEmpty {
                let content = currentParagraphLines.joined(separator: "\n")
                elements.append(MarkdownElement(type: .paragraph, content: content))
                Logger.debug("📄 Added paragraph with \(currentParagraphLines.count) lines")
            }

            // IMPORTANT: Add empty line after each paragraph (except the last one) to preserve paragraph spacing
            if index < paragraphs.count - 1 {
                Logger.debug("➕ Adding empty line after paragraph \(index + 1)")
                elements.append(MarkdownElement(type: .emptyLine, content: ""))
            }
        }

        // Log summary of what we parsed
        Logger.debug("📊 Parsed markdown summary: \(elements.count) total elements")
        let paragraphCount = elements.filter { $0.type == .paragraph }.count
        let emptyLineCount = elements.filter { $0.type == .emptyLine }.count
        let headerCount = elements.filter { $0.type == .header }.count
        let listCount = elements.filter { $0.type == .listItem }.count
        Logger.debug("  - Paragraphs: \(paragraphCount)")
        Logger.debug("  - Empty lines: \(emptyLineCount)")
        Logger.debug("  - Headers: \(headerCount)")
        Logger.debug("  - List items: \(listCount)")

        return elements
    }

    // Helper structures for markdown parsing
    private struct MarkdownElement {
        enum ElementType {
            case header
            case paragraph
            case separator
            case listItem
            case emptyLine
        }

        let type: ElementType
        let content: String
    }

    // Helper structure for text formatting
    private struct TextPart {
        let content: String
        let isBold: Bool
    }
}