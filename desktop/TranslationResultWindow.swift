import Cocoa
import SwiftUI

class TranslationResultWindow: NSWindow {
    private var hostingView: NSHostingView<TranslationResultView>?
    private var clickMonitor: Any?
    
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
    
    // 计算窗口大小以适应内容
    private static func calculateWindowSize(original: String, translated: String) -> NSSize {
        let maxWidth: CGFloat = 500
        let minWidth: CGFloat = 350
        let padding: CGFloat = 32 // 左右各16的padding
        let verticalSpacing: CGFloat = 120 // 标题栏、间距等的固定高度
        
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
        let minTextHeight: CGFloat = 30
        let maxTextHeight: CGFloat = 150 // 增加最大文本高度
        let finalOriginalHeight = min(max(originalHeight + 20, minTextHeight), maxTextHeight)
        let finalTranslatedHeight = min(max(translatedHeight + 20, minTextHeight), maxTextHeight)
        
        // 计算总高度：固定元素 + 两个文本框的高度 + 额外间距
        let totalHeight = verticalSpacing + finalOriginalHeight + finalTranslatedHeight + 50 // 增加额外间距
        
        // 限制最大高度，但提供更多空间
        let maxHeight: CGFloat = 600
        let finalHeight = min(totalHeight, maxHeight)
        
        return NSSize(width: maxWidth, height: max(finalHeight, 200)) // 增加最小高度
    }
    
    private func setupContent(original: String, translated: String) {
        let resultView = TranslationResultView(
            original: original,
            translated: translated,
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
        
        print("[LOG] Translation result window shown at \(resultPoint) (screen: \(screenFrame))")
    }
    
    func hide() {
        self.orderOut(nil)
        
        // 清理点击监听
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        
        print("[LOG] Translation result window hidden")
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
        print("[LOG] Copied to clipboard: \(text)")
        
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
}

struct TranslationResultView: View {
    let original: String
    let translated: String
    let onCopy: (String) -> Void
    let onClose: () -> Void
    
    @State private var showingCopySuccess = false
    
    var body: some View {
        VStack(spacing: 16) {
            // 标题栏（可拖动）
            HStack {
                Image(systemName: "hand.draw")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.6))
                    .help("拖动移动窗口")
                
                Text("翻译结果")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
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
            .padding(.top, 4)
            .padding(.bottom, 4)
            .onHover { isHovered in
                if isHovered {
                    NSCursor.openHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            
            // 原文
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("原文:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button(action: {
                        onCopy(original)
                        showCopyFeedback()
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("复制原文")
                }
                
                ScrollView {
                    Text(original)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.horizontal, 4)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .frame(minHeight: 30, maxHeight: 150)
            }
            
            // 译文
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("译文:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button(action: {
                        onCopy(translated)
                        showCopyFeedback()
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("复制译文")
                }
                
                ScrollView {
                    Text(translated)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.horizontal, 4)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.selectedContentBackgroundColor).opacity(0.1))
                )
                .frame(minHeight: 30, maxHeight: 150)
            }
            
            Spacer()
        }
        .padding(16)
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
                    Text("已复制")
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