import Cocoa
import SwiftUI

class TranslationResultWindow: NSWindow {
    private var hostingView: NSHostingView<TranslationResultView>?
    private var clickMonitor: Any?
    private var resultView: TranslationResultView?
    
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
    }
    
    init(originalText: String, targetLanguage: String) {
        // 初始窗口大小，会根据内容动态调整
        let initialSize = NSSize(width: 450, height: 200)
        
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
            }
        )
        
        hostingView = NSHostingView(rootView: resultView!)
        self.contentView = hostingView
        
        // 开始流式翻译
        startStreamTranslation(original: original, to: targetLanguage)
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
        
        // 确保在主线程更新UI
        if Thread.isMainThread {
            resultView.viewModel.updateTranslation(content, isStreaming: true)
            
            // 根据内容动态调整窗口大小
            let newSize = Self.calculateWindowSize(original: resultView.original, translated: content)
            let currentFrame = self.frame
            let newFrame = NSRect(
                x: currentFrame.origin.x,
                y: currentFrame.origin.y + currentFrame.height - newSize.height, // 保持顶部位置
                width: newSize.width,
                height: newSize.height
            )
            self.setFrame(newFrame, display: true, animate: true)
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
    }
    
    func hide() {
        self.orderOut(nil)
        
        // 清理点击监听
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        
        Logger.info("Translation result window hidden")
    }
    
    deinit {
        // 确保在销毁时清理监听
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        Logger.info("Copied to clipboard: \(text)")
        
        // 简短显示复制成功提示
        // 这里可以添加一个临时的"已复制"提示
    }
    
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return false
    }
    
    // 重写方法以控制窗口焦点行为，确保拖动时不会意外隐藏
    override func resignKey() {
        // 不调用super，防止窗口在失去焦点时被自动隐藏
        // 用户需要通过点击关闭按钮或点击外部区域来关闭
    }
    
    // 计算窗口大小以适应内容
    private static func calculateWindowSize(original: String, translated: String) -> NSSize {
        let maxWidth: CGFloat = 450 // 从500减少到450
        let minWidth: CGFloat = 300 // 从350减少到300
        let padding: CGFloat = 24 // 从32减少到24
        let verticalSpacing: CGFloat = 80 // 从120减少到80
        
        // 计算文本所需的高度
        let font = NSFont.systemFont(ofSize: 13)
        let textWidth = maxWidth - padding - 16 // 减去文本框内部padding
        
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
        let minTextHeight: CGFloat = 25 // 从30减少到25
        let maxTextHeight: CGFloat = 120 // 从150减少到120
        let finalOriginalHeight = min(max(originalHeight + 15, minTextHeight), maxTextHeight) // 从20减少到15
        let finalTranslatedHeight = min(max(translatedHeight + 15, minTextHeight), maxTextHeight)
        
        // 计算总高度：固定元素 + 两个文本框的高度 + 额外间距
        let totalHeight = verticalSpacing + finalOriginalHeight + finalTranslatedHeight + 30 // 从50减少到30
        
        // 限制最大高度，但提供更多空间
        let maxHeight: CGFloat = 500 // 从600减少到500
        let finalHeight = min(totalHeight, maxHeight)
        
        return NSSize(width: maxWidth, height: max(finalHeight, 150)) // 从200减少到150
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
            }
        )
        
        hostingView = NSHostingView(rootView: resultView)
        self.contentView = hostingView
    }
}

class TranslationResultViewModel: ObservableObject {
    @Published var translated: String
    @Published var isStreaming: Bool
    
    init(translated: String, isStreaming: Bool) {
        self.translated = translated
        self.isStreaming = isStreaming
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
}

struct TranslationResultView: View {
    let original: String
    @ObservedObject var viewModel: TranslationResultViewModel
    let onCopy: (String) -> Void
    let onClose: () -> Void
    
    @State private var showingCopySuccess = false
    
    init(original: String, translated: String, isStreaming: Bool, onCopy: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        self.original = original
        self.viewModel = TranslationResultViewModel(translated: translated, isStreaming: isStreaming)
        self.onCopy = onCopy
        self.onClose = onClose
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // 标题栏（可拖动）
            HStack {
                Image(systemName: "hand.draw")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.6))
                    .help("Drag to move window")
                
                Text("Translation Result")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
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
            
            // 原文 - 只保留blockquote引用线，去掉背景框
            VStack(alignment: .leading, spacing: 4) {
                // blockquote风格的原文显示
                HStack(alignment: .center, spacing: 12) {
                    // 左侧引用线 - 只保持一行高
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 3, height: 20)
                        .cornerRadius(1.5)
                    
                    // 原文内容 - 只显示一行
                    Text(original)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 12)
            }
            
            // 译文 - 去掉背景框
            VStack(alignment: .leading, spacing: 4) {
                ScrollView {
                    HStack {
                        Text(viewModel.translated)
                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                            .lineSpacing(4)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(.horizontal, 4)
                        
                        // 流式翻译指示器
                        if viewModel.isStreaming {
                            Text("|")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.blue)
                                .opacity(0.8)
                                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: viewModel.isStreaming)
                        }
                    }
                }
                .frame(minHeight: 30, maxHeight: 120)
                
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