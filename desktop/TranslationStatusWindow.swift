import Cocoa

class TranslationStatusWindow: NSWindow {
    private let statusLabel = NSTextField()
    private var hideTimer: Timer?
    
    static let shared = TranslationStatusWindow()
    
    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 50),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        setupWindow()
        setupUI()
    }
    
    private func setupWindow() {
        // 设置窗口属性
        self.backgroundColor = NSColor.clear
        self.isOpaque = false
        self.hasShadow = true
        self.level = .floating
        self.isMovable = false
        self.canHide = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        
        // 设置内容视图的背景和圆角
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        self.contentView?.layer?.cornerRadius = 12
        self.contentView?.layer?.masksToBounds = true
        
        // 添加阴影效果
        self.contentView?.layer?.shadowColor = NSColor.black.cgColor
        self.contentView?.layer?.shadowOffset = CGSize(width: 0, height: -2)
        self.contentView?.layer?.shadowRadius = 8
        self.contentView?.layer?.shadowOpacity = 0.3
    }
    
    private func setupUI() {
        guard let contentView = self.contentView else { return }
        
        // 配置状态标签
        statusLabel.isEditable = false
        statusLabel.isSelectable = false
        statusLabel.isBordered = false
        statusLabel.backgroundColor = NSColor.clear
        statusLabel.textColor = NSColor.white
        statusLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        statusLabel.alignment = .center
        statusLabel.stringValue = "Translating..."
        
        contentView.addSubview(statusLabel)
        
        // 设置约束
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20)
        ])
    }
    
    // 显示翻译中状态
    func showTranslating(near element: AXUIElement? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.statusLabel.stringValue = "Translating..."
            self.statusLabel.textColor = NSColor.white
            self.contentView?.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.9).cgColor
            
            self.positionWindow(near: element)
            self.orderFrontRegardless()
            self.makeKeyAndOrderFront(nil)
            
            print("[LOG] Showing translation status window")
        }
    }
    
    // 显示翻译成功状态
    func showSuccess() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.statusLabel.stringValue = "Translation successful"
            self.statusLabel.textColor = NSColor.white
            self.contentView?.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.9).cgColor
            
            print("[LOG] Translation successful - hiding in 1 second")
            
            // 1秒后自动隐藏
            self.hideTimer?.invalidate()
            self.hideTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
                self.hideWindow()
            }
        }
    }
    
    // 显示翻译失败状态
    func showFailure() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.statusLabel.stringValue = "Translation failed"
            self.statusLabel.textColor = NSColor.white
            self.contentView?.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.9).cgColor
            
            print("[LOG] Translation failed - hiding in 2 seconds")
            
            // 2秒后自动隐藏
            self.hideTimer?.invalidate()
            self.hideTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                self.hideWindow()
            }
        }
    }
    
    // 隐藏窗口
    func hideWindow() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.hideTimer?.invalidate()
            self.hideTimer = nil
            self.orderOut(nil)
            
            print("[LOG] Translation status window hidden")
        }
    }
    
    // 定位窗口位置（在焦点元素附近或屏幕中央）
    private func positionWindow(near element: AXUIElement?) {
        var targetRect = NSRect.zero
        
        if let element = element {
            // 尝试获取元素的位置和大小
            var position: CFTypeRef?
            var size: CFTypeRef?
            
            if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
               AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success {
                
                var point = CGPoint.zero
                var elementSize = CGSize.zero
                
                if let position = position,
                   AXValueGetValue(position as! AXValue, .cgPoint, &point) {
                    if let size = size,
                       AXValueGetValue(size as! AXValue, .cgSize, &elementSize) {
                        targetRect = NSRect(x: point.x, y: point.y, width: elementSize.width, height: elementSize.height)
                        print("[LOG] Element position: \(targetRect)")
                    }
                }
            }
        }
        
        let screenFrame = NSScreen.main?.frame ?? NSRect.zero
        var windowFrame = self.frame
        
        if !targetRect.isEmpty {
            // 在输入框上方20像素处显示，水平居中对齐
            windowFrame.origin.x = targetRect.midX - windowFrame.width / 2
            windowFrame.origin.y = targetRect.minY - windowFrame.height - 20
            
            // 确保窗口在屏幕范围内 - 水平方向调整
            if windowFrame.maxX > screenFrame.maxX {
                windowFrame.origin.x = screenFrame.maxX - windowFrame.width - 10
            }
            if windowFrame.minX < screenFrame.minX {
                windowFrame.origin.x = screenFrame.minX + 10
            }
            
            // 垂直方向调整 - 如果上方空间不够，显示在下方
            if windowFrame.minY < screenFrame.minY {
                // 上方空间不够，显示在输入框下方
                windowFrame.origin.y = targetRect.maxY + 20
                print("[LOG] Not enough space above, showing below input")
            }
            
            // 如果下方也不够空间，则显示在屏幕顶部
            if windowFrame.maxY > screenFrame.maxY {
                windowFrame.origin.y = screenFrame.maxY - windowFrame.height - 10
                print("[LOG] Not enough space below, showing at screen top")
            }
            
            print("[LOG] Status window positioned at: \(windowFrame)")
        } else {
            // 默认在屏幕中央上方显示
            windowFrame.origin.x = screenFrame.midX - windowFrame.width / 2
            windowFrame.origin.y = screenFrame.midY + 100
            print("[LOG] Using default center position")
        }
        
        self.setFrame(windowFrame, display: true)
    }
} 