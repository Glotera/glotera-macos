import Cocoa
import SwiftUI

/// Grammarly-style logo bar that appears when hovering near screen edge
class GloteraLogoBar: NSWindow {
    private var hostingView: NSHostingView<GloteraLogoBarView>?
    private var currentScreen: NSScreen?
    private var isAnimating: Bool = false
    private weak var mouseTracker: EdgeMouseTracker?
    
    // Logo bar appearance settings
    private let logoBarWidth: CGFloat = 120
    private let logoBarHeight: CGFloat = 40
    private let screenEdgeOffset: CGFloat = 10
    
    // Callback for when logo bar is clicked
    var onLogoClick: (() -> Void)?
    
    init() {
        // Initial frame - will be positioned at runtime
        let initialFrame = NSRect(x: 0, y: 0, width: logoBarWidth, height: logoBarHeight)
        
        super.init(
            contentRect: initialFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        // Configure window properties for floating logo bar
        self.level = .statusBar  // Use higher level than translation window to ensure visibility
        self.isOpaque = false
        self.backgroundColor = NSColor.clear
        self.hasShadow = true
        self.isMovableByWindowBackground = false
        self.isReleasedWhenClosed = false
        self.ignoresMouseEvents = false
        
        setupContent()
        Logger.info("GloteraLogoBar initialized")
    }
    
    private func setupContent() {
        let logoBarView = GloteraLogoBarView { [weak self] in
            self?.handleLogoClick()
        }
        
        hostingView = NSHostingView(rootView: logoBarView)
        self.contentView = hostingView
    }
    
    /// Show the logo bar at the right edge of the screen
    func showAtRightEdge(on screen: NSScreen? = nil) {
        guard !isAnimating else { return }
        
        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = targetScreen else {
            Logger.error("No screen available for logo bar display")
            return
        }
        
        currentScreen = screen
        let screenFrame = screen.visibleFrame
        
        // Position logo bar at the right edge, vertically centered
        let logoBarX = screenFrame.maxX - logoBarWidth - screenEdgeOffset
        let logoBarY = screenFrame.midY - (logoBarHeight / 2)
        let targetFrame = NSRect(x: logoBarX, y: logoBarY, width: logoBarWidth, height: logoBarHeight)
        
        // Start from off-screen position (right edge)
        let startFrame = NSRect(x: screenFrame.maxX, y: logoBarY, width: logoBarWidth, height: logoBarHeight)
        self.setFrame(startFrame, display: false)
        
        // Show window and animate to target position
        self.makeKeyAndOrderFront(nil)
        isAnimating = true
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(targetFrame, display: true)
        }) {
            self.isAnimating = false
            Logger.debug("Logo bar animated into view")
        }
        
        Logger.info("Logo bar shown at right edge of screen")
    }
    
    /// Hide the logo bar with animation
    func hideWithAnimation() {
        guard !isAnimating, self.isVisible else { return }
        
        isAnimating = true
        
        let currentFrame = self.frame
        let hideFrame = NSRect(
            x: (currentScreen?.visibleFrame.maxX ?? currentFrame.maxX) + logoBarWidth,
            y: currentFrame.origin.y,
            width: logoBarWidth,
            height: logoBarHeight
        )
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().setFrame(hideFrame, display: true)
        }) {
            self.orderOut(nil)
            self.isAnimating = false
            Logger.debug("Logo bar animated out of view")
        }
        
        Logger.info("Logo bar hidden")
    }
    
    /// Handle logo bar click
    private func handleLogoClick() {
        Logger.info("Logo bar clicked")
        onLogoClick?()
    }
    
    /// Update position for multi-monitor support
    func updatePositionForCurrentScreen() {
        guard let currentScreen = currentScreen else { return }
        
        // Check if window is still on the same screen
        let windowCenter = NSPoint(x: frame.midX, y: frame.midY)
        if !currentScreen.frame.contains(windowCenter) {
            // Window moved to different screen, find the new screen
            for screen in NSScreen.screens {
                if screen.frame.contains(windowCenter) {
                    Logger.info("Logo bar moved to different screen")
                    showAtRightEdge(on: screen)
                    break
                }
            }
        }
    }
    
    /// Set mouse tracker reference for cleanup
    func setMouseTracker(_ tracker: EdgeMouseTracker) {
        self.mouseTracker = tracker
    }
}

/// SwiftUI view for the logo bar content
struct GloteraLogoBarView: View {
    let onLogoClick: () -> Void
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Glotera logo/icon - use same icon as status bar
            if let nsImage = NSImage(named: "StatusIcon") {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .colorInvert() // Invert colors to make it white
            } else {
                // Fallback to system icon if custom icon not found
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
            }
            
            // App name
            Text("Glotera")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.2, green: 0.6, blue: 1.0),  // Glotera blue
                            Color(red: 0.1, green: 0.4, blue: 0.8)   // Darker blue
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(
                    color: .black.opacity(isHovered ? 0.3 : 0.2),
                    radius: isHovered ? 8 : 4,
                    x: 0,
                    y: 2
                )
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isHovered)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onLogoClick()
        }
        .frame(width: 120, height: 40)
    }
}

/// Mouse tracker for detecting cursor movement near screen edges
class EdgeMouseTracker: NSObject {
    static let shared = EdgeMouseTracker()
    
    private var eventMonitor: Any?
    private var isTracking: Bool = false
    private var currentScreen: NSScreen?
    
    // Edge detection settings
    private let edgeThreshold: CGFloat = 50  // Distance from edge to trigger
    private let edgeWidth: CGFloat = 20      // Width of the edge zone
    
    // Callbacks
    var onRightEdgeHover: ((NSScreen) -> Void)?
    var onEdgeExit: (() -> Void)?
    
    private override init() {
        super.init()
    }
    
    deinit {
        stopTracking()
    }
    
    /// Start tracking mouse movement for edge detection
    func startTracking() {
        guard !isTracking else { return }
        
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.handleMouseEvent(event)
        }
        
        isTracking = true
        Logger.info("Edge mouse tracking started")
    }
    
    /// Stop tracking mouse movement
    func stopTracking() {
        guard isTracking else { return }
        
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        
        isTracking = false
        Logger.info("Edge mouse tracking stopped")
    }
    
    /// Handle mouse movement events
    private func handleMouseEvent(_ event: NSEvent) {
        let mouseLocation = NSEvent.mouseLocation
        
        // Find which screen the mouse is on
        guard let screen = screenContaining(point: mouseLocation) else { return }
        
        let screenFrame = screen.visibleFrame
        let distanceFromRightEdge = screenFrame.maxX - mouseLocation.x
        
        // Check if mouse is near the right edge
        if distanceFromRightEdge <= edgeThreshold {
            // Mouse is near right edge
            if currentScreen != screen {
                currentScreen = screen
                Logger.debug("Mouse near right edge of screen: \(screen.localizedName)")
                onRightEdgeHover?(screen)
            }
        } else {
            // Mouse moved away from edge
            if currentScreen != nil {
                currentScreen = nil
                Logger.debug("Mouse moved away from screen edge")
                onEdgeExit?()
            }
        }
    }
    
    /// Find the screen containing the given point
    private func screenContaining(point: NSPoint) -> NSScreen? {
        return NSScreen.screens.first { screen in
            screen.frame.contains(point)
        }
    }
    
    /// Check if tracking is active
    func isTrackingActive() -> Bool {
        return isTracking
    }
}

/// Manager class to coordinate logo bar and mouse tracking
class GloteraLogoBarManager: NSObject {
    static let shared = GloteraLogoBarManager()
    
    private var logoBar: GloteraLogoBar?
    private let mouseTracker = EdgeMouseTracker.shared
    private var hideTimer: Timer?
    
    // State management
    private var isEnabled: Bool = false
    private var isLogoBarVisible: Bool = false
    
    // Callbacks
    var onLogoBarClick: (() -> Void)?
    
    private override init() {
        super.init()
        setupMouseTracker()
    }
    
    deinit {
        disable()
    }
    
    /// Enable logo bar functionality
    func enable() {
        guard !isEnabled else { return }
        
        isEnabled = true
        mouseTracker.startTracking()
        Logger.info("Glotera logo bar manager enabled")
    }
    
    /// Disable logo bar functionality
    func disable() {
        guard isEnabled else { return }
        
        isEnabled = false
        mouseTracker.stopTracking()
        hideLogoBar()
        hideTimer?.invalidate()
        hideTimer = nil
        Logger.info("Glotera logo bar manager disabled")
    }
    
    /// Setup mouse tracker callbacks
    private func setupMouseTracker() {
        mouseTracker.onRightEdgeHover = { [weak self] screen in
            self?.showLogoBar(on: screen)
        }
        
        mouseTracker.onEdgeExit = { [weak self] in
            self?.scheduleHideLogoBar()
        }
    }
    
    /// Show logo bar on specified screen
    private func showLogoBar(on screen: NSScreen) {
        guard isEnabled else { return }
        
        // Cancel any pending hide timer
        hideTimer?.invalidate()
        hideTimer = nil
        
        if logoBar == nil {
            logoBar = GloteraLogoBar()
            logoBar?.setMouseTracker(mouseTracker)
            logoBar?.onLogoClick = { [weak self] in
                self?.handleLogoBarClick()
            }
        }
        
        if !isLogoBarVisible {
            logoBar?.showAtRightEdge(on: screen)
            isLogoBarVisible = true
        }
    }
    
    /// Schedule logo bar to hide after delay
    private func scheduleHideLogoBar() {
        guard isEnabled else { return }
        
        // Hide after 2 seconds of no hover - but only hide the logo bar, not the translation window
        hideTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.hideLogoBarOnly()
        }
    }
    
    /// Hide only the logo bar without affecting translation window
    private func hideLogoBarOnly() {
        guard isLogoBarVisible else { return }
        
        logoBar?.hideWithAnimation()
        isLogoBarVisible = false
        Logger.debug("Logo bar hidden due to no hover - translation window remains if open")
    }
    
    /// Hide logo bar immediately
    private func hideLogoBar() {
        guard isLogoBarVisible else { return }
        
        logoBar?.hideWithAnimation()
        isLogoBarVisible = false
    }
    
    /// Handle logo bar click
    private func handleLogoBarClick() {
        Logger.info("Logo bar clicked - triggering callback")
        onLogoBarClick?()
    }
    
    /// Check if logo bar is currently enabled
    func isLogoBarEnabled() -> Bool {
        return isEnabled
    }
    
    /// Check if logo bar is currently visible
    func isLogoBarCurrentlyVisible() -> Bool {
        return isLogoBarVisible
    }
}