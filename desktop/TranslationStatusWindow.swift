import Cocoa
import SwiftUI

class TranslationStatusWindow: NSWindow {
    static let shared = TranslationStatusWindow()
    
    private var statusView: TranslationStatusView?
    
    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = NSColor.clear
        self.hasShadow = true
        self.isMovableByWindowBackground = false
        
        setupContent()
    }
    
    private func setupContent() {
        statusView = TranslationStatusView()
        let hostingView = NSHostingView(rootView: statusView!)
        self.contentView = hostingView
    }
    
    func showTranslating(near element: AXUIElement?) {
        statusView?.updateStatus(.translating)
        
        // 获取合适的显示位置
        let mouseLocation = NSEvent.mouseLocation
        var statusPoint = mouseLocation
        statusPoint.y -= 80 // 显示在鼠标位置下方
        
        // 确保不超出屏幕边界
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
        if statusPoint.x + self.frame.width > screenFrame.maxX {
            statusPoint.x = screenFrame.maxX - self.frame.width - 10
        }
        if statusPoint.y < screenFrame.minY {
            statusPoint.y = screenFrame.minY + 10
        }
        
        self.setFrameTopLeftPoint(statusPoint)
        self.orderFront(nil)  // 不抢夺焦点，避免取消选中状态 
    }
    
    func showSuccess() {
        statusView?.updateStatus(.success)
        
        // 2秒后自动隐藏
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.hideStatus()
        } 
    }
    
    func showFailure() {
        statusView?.updateStatus(.failure)
        
        // 3秒后自动隐藏
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.hideStatus()
        }
         
    }
    
    func hideStatus() {
        self.orderOut(nil) 
    }
    
    // 防止状态窗口抢夺焦点
    override var canBecomeKey: Bool {
        return false
    }
    
    override var canBecomeMain: Bool {
        return false
    }
}

enum TranslationStatus {
    case translating
    case success
    case failure
}

struct TranslationStatusView: View {
    @State private var status: TranslationStatus = .translating
    @State private var rotation: Double = 0
    
    var body: some View {
        HStack(spacing: 12) {
            // 状态图标
            Group {
                switch status {
                case .translating:
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(.blue)
                        .rotationEffect(.degrees(rotation))
                        .onAppear {
                            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                                rotation = 360
                            }
                        }
                case .success:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                case .failure:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
            }
            .font(.system(size: 18))
            
            // 状态文本
            Text(statusText)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }
    
    private var statusText: String {
        switch status {
        case .translating:
            return "Translating..."
        case .success:
            return "Translated!"
        case .failure:
            return "Translation failed"
        }
    }
    
    func updateStatus(_ newStatus: TranslationStatus) {
        withAnimation(.easeInOut(duration: 0.3)) {
            status = newStatus
        }
        
        if newStatus != .translating {
            rotation = 0
        }
    }
} 