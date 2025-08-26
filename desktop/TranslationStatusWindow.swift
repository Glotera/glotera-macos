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
        
        // TranslationStatusWindow is a singleton, no registration needed
    }
    
    private func setupContent() {
        statusView = TranslationStatusView()
        let hostingView = NSHostingView(rootView: statusView!)
        self.contentView = hostingView
    }
    
    func showTranslating(near element: AXUIElement?, mousePoint: CGPoint) {
        statusView?.updateStatus(.translating)
        
        // 1. 初始化位置为鼠标点
        var statusPoint = mousePoint
        
        // 2. 获取状态视图的大小（假设已知或提前设置）
        // 获取 statusView 的实际大小
        let viewWidth = self.frame.width // 默认宽度
        let viewHeight = self.frame.height  // 默认高度
                
    
        
        // 4. 边界检查 - 确保不超出屏幕左边界
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
        let minX = screenFrame.minX;
        let maxX = screenFrame.maxX;
        let minY = screenFrame.minY;
        let maxY = screenFrame.maxY;
        if statusPoint.x < minX {
            statusPoint.x = minX
        }
        
        // 5. 边界检查 - 确保不超出屏幕右边界
        if statusPoint.x + viewWidth > maxX {
            statusPoint.x = maxX - viewWidth
        }
        
        // 6. 边界检查 - 确保不超出屏幕上边界
        if statusPoint.y < minY {
            statusPoint.y = minY
        }
        
        // 垂直位置调整 - 显示在选中文本上方
        
        // 7. 边界检查 - 确保不超出屏幕下边界
        if statusPoint.y + viewHeight > maxY {
            statusPoint.y = maxY - viewHeight - 100
        }
        
        // 8. 设置状态视图位置
        self.setFrameTopLeftPoint(statusPoint)
        self.makeKeyAndOrderFront(nil)
        
        // No interaction recording needed for singleton status window
        
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
    
    func showNetworkError(near mousePoint: CGPoint) {
        statusView?.updateStatus(.networkError)
        
        // Set position
        let viewWidth = self.frame.width
        let viewHeight = self.frame.height
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
        
        var statusPoint = mousePoint
        statusPoint.x = max(screenFrame.minX, min(statusPoint.x, screenFrame.maxX - viewWidth))
        statusPoint.y = max(screenFrame.minY, min(statusPoint.y, screenFrame.maxY - viewHeight))
        
        self.setFrameTopLeftPoint(statusPoint)
        self.makeKeyAndOrderFront(nil)
        
        // Auto hide after 5 seconds (network errors show longer)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.hideStatus()
        }
    }
    
    func showServerError(near mousePoint: CGPoint) {
        statusView?.updateStatus(.serverError)
        
        // Set position
        let viewWidth = self.frame.width
        let viewHeight = self.frame.height
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
        
        var statusPoint = mousePoint
        statusPoint.x = max(screenFrame.minX, min(statusPoint.x, screenFrame.maxX - viewWidth))
        statusPoint.y = max(screenFrame.minY, min(statusPoint.y, screenFrame.maxY - viewHeight))
        
        self.setFrameTopLeftPoint(statusPoint)
        self.makeKeyAndOrderFront(nil)
        
        // Auto hide after 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            self.hideStatus()
        }
    }
    
    func hideStatus() {
        self.orderOut(nil)
        
        // Note: Don't unregister TranslationStatusWindow as it's a singleton
        // that may be reused frequently. MemoryManager will handle cleanup if needed.
    }
    
    // 判断翻译状态栏是否正在显示
    func isStatusVisible() -> Bool {
        return self.isVisible
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
    case networkError
    case serverError
}

struct TranslationStatusView: View {
    @State private var status: TranslationStatus = .translating
    @State private var rotation: Double = 0
    
    var body: some View {
        HStack(spacing: 12) {
            // 状态图标 - 改进版，使用固定大小容器
            Group {
                switch status {
                case .translating:
                    // 创建固定大小的容器，确保旋转不影响布局
                    ZStack {
                        // 固定大小的背景（与非旋转状态一致）
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 24, height: 24)
                        
                        // 旋转的图标 - 分离到单独的视图中
                        RotatingIconView(iconName: "arrow.triangle.2.circlepath", color: .blue)
                    }
                    
                case .success:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .frame(width: 24, height: 24)  // 统一大小
                    
                case .failure:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .frame(width: 24, height: 24)  // 统一大小
                        
                case .networkError:
                    Image(systemName: "wifi.exclamationmark")
                        .foregroundColor(.orange)
                        .frame(width: 24, height: 24)
                        
                case .serverError:
                    Image(systemName: "server.rack")
                        .foregroundColor(.red)
                        .frame(width: 24, height: 24)
                }
            }
            .font(.system(size: 18))
            
            // 状态文本 - 固定大小
            Text(statusText)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
                .fixedSize(horizontal: true, vertical: false)  // 只在水平方向自动调整
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

    // 单独的旋转图标视图，避免影响父布局
    struct RotatingIconView: View {
        let iconName: String
        let color: Color
        @State private var rotation: Double = 0
        
        var body: some View {
            Image(systemName: iconName)
                .foregroundColor(color)
                .rotationEffect(.degrees(rotation))
                .animation(.linear(duration: 1.0).repeatForever(autoreverses: false), value: rotation)
                .onAppear {
                    rotation = 360
                }
                .frame(width: 24, height: 24)  // 确保图标本身有固定大小
        }
    }
    
    private var statusText: String {
        switch status {
        case .translating:
            return "Translating..."
        case .success:
            return "Translated!"
        case .failure:
            return "Translation failed"
        case .networkError:
            return "Network error"
        case .serverError:
            return "Server error"
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
