import Cocoa
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

class ScreenshotManager: NSObject {
    static let shared = ScreenshotManager()

    private var screenshotWindow: NSWindow?  // Changed to NSWindow to support both window types
    private var completionHandler: ((NSImage?) -> Void)?
    private var hiddenWindows: [NSWindow] = []
    private var recoveryTimer: Timer?
    private var storedScreenImage: NSImage?  // Store clean screenshot before showing overlay

    override init() {
        super.init()
    }

    // Main method to trigger screenshot selection using pre-captured image
    func captureScreenshotWithSelectionUsingPreCapture(_ preCapture: NSImage, completion: @escaping (NSImage?) -> Void) {
        Logger.info("Starting screenshot selection using pre-captured image")
        completionHandler = completion

        // Use the pre-captured image (captured at hotkey detection)
        self.storedScreenImage = preCapture
        Logger.info("Using pre-captured screenshot from hotkey detection")

        // Only hide Glotera's own windows (keep other applications visible for user to see)
        hideGloteraWindows()

        // Create and show transparent selection overlay
        DispatchQueue.main.async {
            self.showTransparentSelectionWindow()
        }
    }

    // Legacy method to trigger screenshot selection (captures at selection time)
    func captureScreenshotWithSelection(completion: @escaping (NSImage?) -> Void) {
        Logger.info("Starting screenshot capture with selection - keeping apps visible")
        completionHandler = completion

        // Only hide Glotera's own windows (keep other applications visible)
        hideGloteraWindows()

        // Create and show transparent selection overlay
        DispatchQueue.main.async {
            self.showTransparentSelectionWindow()
        }
    }

    private func hideGloteraWindows() {
        // Clear previous state
        hiddenWindows.removeAll()

        // Only hide Glotera's own visible windows (not other applications)
        for window in NSApp.windows {
            if window.isVisible && window.canBecomeKey && !window.isKind(of: ScreenshotSelectionWindow.self) {
                hiddenWindows.append(window)
                window.orderOut(nil)
            }
        }

        Logger.info("Hidden \(hiddenWindows.count) Glotera windows for screenshot (keeping other apps visible)")

        // Set up emergency recovery timer (30 seconds timeout)
        recoveryTimer?.invalidate()
        recoveryTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            Logger.warn("Screenshot emergency timeout - forcing window recovery")
            self?.forceRestoreWindows()
        }
    }

    private func restoreGloteraWindows() {
        // Cancel recovery timer
        recoveryTimer?.invalidate()
        recoveryTimer = nil

        // Restore only the Glotera windows we actually hid
        for window in hiddenWindows {
            if window.isKind(of: NSWindow.self) && window != screenshotWindow {
                window.orderFront(nil)
            }
        }

        Logger.info("Restored \(hiddenWindows.count) Glotera windows after screenshot")
        hiddenWindows.removeAll()
    }


    private func forceRestoreWindows() {
        Logger.warn("Force restoring windows due to timeout or error")

        // Remove emergency escape monitor first
        removeEmergencyEscapeMonitor()

        // Close screenshot window if it exists
        screenshotWindow?.orderOut(nil)
        screenshotWindow = nil

        // Restore Glotera's hidden windows
        restoreGloteraWindows()

        // Clear stored image
        storedScreenImage = nil

        // Call completion handler with nil to indicate cancellation
        if let handler = completionHandler {
            handler(nil)
            completionHandler = nil
        }
    }

    private func showTransparentSelectionWindow() {
        // Create transparent selection overlay that doesn't hide the real applications
        screenshotWindow = TransparentSelectionWindow { [weak self] selectedRect in
            self?.handleTransparentScreenshotSelection(selectedRect: selectedRect)
        }

        guard let window = screenshotWindow else {
            Logger.error("Failed to create transparent selection window")
            forceRestoreWindows() // Ensure recovery on error
            return
        }

        window.makeKeyAndOrderFront(nil)
        window.level = .floating // Overlay above other apps but not too high
        window.makeFirstResponder(window.contentView) // Ensure proper keyboard focus

        // Set up immediate ESC key monitoring for emergency exit
        setupEmergencyEscapeMonitor()

        Logger.info("Transparent selection overlay shown - real applications remain visible")
    }

    private var emergencyEscapeMonitor: Any?

    private func setupEmergencyEscapeMonitor() {
        // Set up global ESC key monitor for immediate exit
        emergencyEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC key
                Logger.info("Emergency ESC key detected - forcing immediate exit")
                DispatchQueue.main.async {
                    self?.forceRestoreWindows()
                }
            }
        }
    }

    private func removeEmergencyEscapeMonitor() {
        if let monitor = emergencyEscapeMonitor {
            NSEvent.removeMonitor(monitor)
            emergencyEscapeMonitor = nil
            Logger.debug("Emergency ESC key monitor removed")
        }
    }

    private func handleTransparentScreenshotSelection(selectedRect: NSRect?) {
        // Cleanup UI first
        removeEmergencyEscapeMonitor()
        screenshotWindow?.orderOut(nil)
        screenshotWindow = nil
        restoreGloteraWindows()

        guard let rect = selectedRect, !rect.isEmpty else {
            Logger.info("Screenshot selection cancelled or empty")
            completionHandler?(nil)
            completionHandler = nil
            return
        }

        Logger.info("Selected area: \(rect), capturing current screen state...")

        // CRITICAL: Get the screen that contains the selection area, not the mouse location
        // The selection area might be on a different screen than where the mouse currently is
        let currentScreen = NSScreen.screens.first { screen in
            NSMouseInRect(NSPoint(x: rect.origin.x + rect.width/2, y: rect.origin.y + rect.height/2), screen.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens.first!
        
        Logger.info("🎯 Using screen for selection: \(currentScreen.frame)")
        Logger.info("📦 Selection center: (\(rect.origin.x + rect.width/2), \(rect.origin.y + rect.height/2))")

        // Capture the current screen state AFTER user selection
        // This ensures we get the actual content the user sees
        guard let currentScreenImage = captureScreenForSpecificScreen(currentScreen) else {
            Logger.error("Failed to capture current screen state")
            completionHandler?(nil)
            completionHandler = nil
            return
        }

        // Convert screen coordinates to image coordinates
        let imageRect = convertScreenRectToImageRect(rect, for: currentScreen, imageSize: currentScreenImage.size)

        // DEBUG: Save detailed information about coordinates and image
        Logger.info("🔍 DEBUGGING COORDINATE SYSTEM:")
        Logger.info("📱 Screen frame: \(currentScreen.frame)")
        Logger.info("🖼️ Image size: \(currentScreenImage.size)")
        Logger.info("📦 Screen selection rect: \(rect)")
        Logger.info("🖼️ Image selection rect: \(imageRect)")
        Logger.info("🖱️ Mouse location: \(NSEvent.mouseLocation)")

        // Save the original screenshot with selection rectangle for verification
        saveDebugImage(currentScreenImage, name: "original_screenshot", rect: imageRect)

        guard let croppedImage = cropImage(currentScreenImage, toRect: imageRect) else {
            Logger.error("Failed to crop selected area from current screenshot")
            completionHandler?(nil)
            completionHandler = nil
            return
        }

        // DEBUG: Save the cropped result
        saveDebugImageSimple(croppedImage, name: "cropped_result")

        Logger.info("Successfully cropped from current screen state with size: \(imageRect)")

        if let handler = completionHandler {
            handler(croppedImage)
            completionHandler = nil
        }
    }

    private func captureFullScreenInternal() -> NSImage? {
        Logger.info("🎯 Attempting multiple screenshot methods...")

        // Method 1: Try CGWindowListCreateImage first (captures all windows)
        if let windowImage = captureScreenUsingWindowList() {
            Logger.info("✅ Screenshot successful using CGWindowListCreateImage")
            return windowImage
        }

        // Method 2: Fallback to CGDisplayCreateImage
        Logger.warn("⚠️ CGWindowListCreateImage failed, trying CGDisplayCreateImage...")
        return captureScreenUsingDisplayImage()
    }
    
    // Public version for testing
    func captureFullScreen() -> NSImage? {
        return captureFullScreenInternal()
    }

    private func captureScreenUsingWindowList() -> NSImage? {
        // For multi-monitor setup, get the screen containing the mouse cursor
        let mouseLocation = NSEvent.mouseLocation
        let currentScreen = NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens.first!

        Logger.info("🖥️ Capturing from screen: \(currentScreen.frame) for mouse at: \(mouseLocation)")
        let screenRect = currentScreen.frame
        let cgRect = CGRect(
            x: screenRect.origin.x,
            y: screenRect.origin.y,
            width: screenRect.size.width,
            height: screenRect.size.height
        )

        // Try multiple capture strategies in order of preference
        let captureStrategies: [(String, CGWindowListOption)] = [
            // Strategy 1: Capture all windows on screen (most comprehensive)
            ("AllOnScreen", [.optionAll, .optionOnScreenOnly]),
            
            // Strategy 2: Capture on-screen windows including current window
            ("OnScreenIncluding", [.optionOnScreenOnly, .optionIncludingWindow]),
            
            // Strategy 3: Capture windows above current window
            ("OnScreenAbove", [.optionOnScreenAboveWindow]),
            
            // Strategy 4: Basic on-screen only
            ("OnScreenBasic", [.optionOnScreenOnly])
        ]
        
        for (strategyName, options) in captureStrategies {
            Logger.info("Trying capture strategy: \(strategyName)")
            
            if let cgImage = CGWindowListCreateImage(cgRect, options, kCGNullWindowID, [.bestResolution, .nominalResolution]) {
                let screenSize = CGSize(width: cgImage.width, height: cgImage.height)
                let image = NSImage(cgImage: cgImage, size: screenSize)
                
                Logger.info("✅ Screenshot successful using strategy \(strategyName): \(cgImage.width)x\(cgImage.height) pixels")
                
                // For the first successful capture, return it immediately
                // The user will see the actual content when selecting
                Logger.info("✅ Using first successful capture strategy: \(strategyName)")
                return image
            } else {
                Logger.warn("❌ Strategy \(strategyName) failed to create image")
            }
        }
        
        Logger.error("All window capture strategies failed")
        return nil
    }

    private func captureScreenUsingDisplayImage() -> NSImage? {
        guard let displayID = CGMainDisplayID() as CGDirectDisplayID? else {
            Logger.error("Failed to get main display ID")
            return nil
        }

        // Use high-quality display capture as fallback
        guard let cgImage = CGDisplayCreateImage(displayID) else {
            Logger.error("Failed to create CGImage from display")
            return nil
        }

        let screenSize = CGSize(width: cgImage.width, height: cgImage.height)
        let image = NSImage(cgImage: cgImage, size: screenSize)

        Logger.info("✅ Captured screen using CGDisplayCreateImage: \(cgImage.width)x\(cgImage.height) pixels")
        Logger.warn("⚠️ Using display capture fallback - may show desktop background instead of application content")
        return image
    }

    private func cropImage(_ image: NSImage, toRect rect: NSRect) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Logger.error("Failed to get CGImage from NSImage")
            return nil
        }

        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        Logger.info("🔄 CROP ANALYSIS:")
        Logger.info("📦 Selection rect (pixels): \(rect)")
        Logger.info("🖼️ Image dimensions (pixels): \(imageWidth) x \(imageHeight)")

        // CRITICAL: The selection rect is already in pixels (converted by convertScreenRectToImageRect)
        // No need to scale again - use directly
        let cropRect = CGRect(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.width,
            height: rect.height
        )

        Logger.info("📐 Crop rect (pixels): \(cropRect)")

        // Clamp the crop rectangle to image bounds
        let clampedX = max(0, min(cropRect.origin.x, imageWidth - 1))
        let clampedY = max(0, min(cropRect.origin.y, imageHeight - 1))
        let clampedWidth = min(cropRect.width, imageWidth - clampedX)
        let clampedHeight = min(cropRect.height, imageHeight - clampedY)

        let clampedCropRect = CGRect(
            x: clampedX,
            y: clampedY,
            width: clampedWidth,
            height: clampedHeight
        )

        Logger.info("🔒 Clamped crop rect: \(clampedCropRect)")

        if clampedCropRect.width < 1 || clampedCropRect.height < 1 {
            Logger.error("❌ Crop rectangle is too small after clamping")
            return nil
        }

        guard let croppedCGImage = cgImage.cropping(to: clampedCropRect) else {
            Logger.error("❌ Failed to crop CGImage with rect: \(clampedCropRect)")
            return nil
        }

        // Create NSImage with proper size (in points)
        // Since we're already working with pixel coordinates, the cropped image is already the correct size
        let croppedSize = CGSize(
            width: CGFloat(croppedCGImage.width),
            height: CGFloat(croppedCGImage.height)
        )
        let croppedImage = NSImage(cgImage: croppedCGImage, size: croppedSize)

        Logger.info("✅ Successfully cropped image to size: \(croppedSize) (points)")
        return croppedImage
    }

    // Save image to local directory with compression
    func saveImageToLocal(_ image: NSImage, quality: Float = 0.8) -> URL? {
        // Create screenshots directory in app support
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            Logger.error("Failed to get application support directory")
            return nil
        }

        let screenshotsDir = appSupportURL.appendingPathComponent("Glotera/Screenshots")

        // Create directory if it doesn't exist
        do {
            try fileManager.createDirectory(at: screenshotsDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            Logger.error("Failed to create screenshots directory: \(error)")
            return nil
        }

        // Generate unique filename
        let timestamp = DateFormatter().string(from: Date()).replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: ":", with: "-")
        let filename = "screenshot_\(timestamp).png"
        let fileURL = screenshotsDir.appendingPathComponent(filename)

        // Convert to PNG with compression
        guard let compressedData = compressPNGImage(image, quality: quality) else {
            Logger.error("Failed to compress image to PNG")
            return nil
        }

        // Save to file
        do {
            try compressedData.write(to: fileURL)
            Logger.info("Screenshot saved to: \(fileURL.path)")
            return fileURL
        } catch {
            Logger.error("Failed to save screenshot: \(error)")
            return nil
        }
    }

    // Convert NSImage to base64 string with compression
    func convertImageToBase64(_ image: NSImage, quality: Float = 0.8) -> String? {
        guard let pngData = compressPNGImage(image, quality: quality) else {
            Logger.error("Failed to convert image to PNG data")
            return nil
        }

        let base64String = pngData.base64EncodedString()
        Logger.info("Converted image to base64, size: \(pngData.count) bytes")
        return base64String
    }

    private func compressPNGImage(_ image: NSImage, quality: Float) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            Logger.error("Failed to create bitmap representation")
            return nil
        }

        // Compress using JPEG first, then convert to PNG for better compression
        let properties: [NSBitmapImageRep.PropertyKey: Any] = [
            .compressionFactor: quality
        ]

        guard let pngData = bitmapRep.representation(using: .png, properties: properties) else {
            Logger.error("Failed to create PNG representation")
            return nil
        }

        Logger.debug("Compressed image to \(pngData.count) bytes with quality: \(quality)")
        return pngData
    }

    // Test method to save a direct screenshot to desktop (for debugging)
    func testDirectScreenshotToDesktop() {
        Logger.info("🧪 Testing direct screenshot to desktop...")

        guard let screenshot = captureFullScreenInternal() else {
            Logger.error("❌ Failed to capture test screenshot")
            return
        }

        // Save to desktop
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let testFileURL = desktopURL.appendingPathComponent("glotera_test_screenshot.png")

        guard let tiffData = screenshot.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            Logger.error("❌ Failed to convert screenshot to PNG")
            return
        }

        do {
            try pngData.write(to: testFileURL)
            Logger.info("✅ Test screenshot saved to: \(testFileURL.path)")
        } catch {
            Logger.error("❌ Failed to save test screenshot: \(error)")
        }
    }

    // Enhanced diagnostic method to test different capture methods
    func diagnoseDifferentCaptureMethods() {
        Logger.info("🔍 Starting comprehensive screenshot capture diagnosis...")
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        
        // Test Method 1: CGWindowListCreateImage with different options
        testCGWindowListCreateImageOptions(saveToDesktop: desktopURL)
        
        // Test Method 2: CGDisplayCreateImage
        testCGDisplayCreateImage(saveToDesktop: desktopURL)
        
        // Test Method 3: Check screen recording permissions
        checkScreenRecordingPermissions()
        
        Logger.info("🔍 Screenshot diagnosis completed. Check desktop for test images.")
    }
    
    private func testCGWindowListCreateImageOptions(saveToDesktop: URL) {
        Logger.info("📸 Testing CGWindowListCreateImage with different options...")
        
        guard let mainScreen = NSScreen.main else {
            Logger.error("❌ Failed to get main screen")
            return
        }
        
        let screenRect = mainScreen.frame
        let cgRect = CGRect(
            x: screenRect.origin.x,
            y: screenRect.origin.y,
            width: screenRect.size.width,
            height: screenRect.size.height
        )
        
        // Test different option combinations
        let testConfigs: [(String, CGWindowListOption)] = [
            ("OnScreenOnly", [.optionOnScreenOnly]),
            ("OnScreenOnly_IncludingWindow", [.optionOnScreenOnly, .optionIncludingWindow]),
            ("All_IncludingWindow", [.optionAll, .optionIncludingWindow]),
            ("OnScreenBelowWindow", [.optionOnScreenBelowWindow]),
            ("OnScreenAboveWindow", [.optionOnScreenAboveWindow])
        ]
        
        for (name, options) in testConfigs {
            Logger.info("🧪 Testing CGWindowListCreateImage with options: \(name)")
            
            guard let cgImage = CGWindowListCreateImage(cgRect, options, kCGNullWindowID, []) else {
                Logger.error("❌ Failed to create image with options: \(name)")
                continue
            }
            
            let image = NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
            saveTestImage(image, name: "windowlist_\(name)", to: saveToDesktop)
        }
    }
    
    private func testCGDisplayCreateImage(saveToDesktop: URL) {
        Logger.info("📺 Testing CGDisplayCreateImage...")
        
        guard let displayID = CGMainDisplayID() as CGDirectDisplayID? else {
            Logger.error("❌ Failed to get main display ID")
            return
        }
        
        guard let cgImage = CGDisplayCreateImage(displayID) else {
            Logger.error("❌ Failed to create display image")
            return
        }
        
        let image = NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
        saveTestImage(image, name: "display_capture", to: saveToDesktop)
    }
    
    private func checkScreenRecordingPermissions() {
        Logger.info("🔒 Checking screen recording permissions...")
        
        if #available(macOS 10.15, *) {
            // Test if we can capture a small area to check permissions
            let testRect = CGRect(x: 0, y: 0, width: 100, height: 100)
            let options: CGWindowListOption = [.optionOnScreenOnly]
            
            if let testImage = CGWindowListCreateImage(testRect, options, kCGNullWindowID, []) {
                Logger.info("✅ Screen recording permissions appear to be granted (can capture test area)")
            } else {
                Logger.warn("⚠️ Screen recording permissions may not be granted or there's another issue")
            }
        } else {
            Logger.info("📝 Running on macOS < 10.15, screen recording permissions not required")
        }
    }
    
    private func saveTestImage(_ image: NSImage, name: String, to directory: URL) {
        let fileURL = directory.appendingPathComponent("glotera_test_\(name).png")
        
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            Logger.error("❌ Failed to convert \(name) image to PNG")
            return
        }
        
        do {
            try pngData.write(to: fileURL)
            Logger.info("✅ \(name) image saved to: \(fileURL.path)")
        } catch {
            Logger.error("❌ Failed to save \(name) image: \(error)")
        }
    }
    
    // MARK: - Image Quality Analysis
    
    /// Check if a captured image contains meaningful content (not just desktop background)
    private func isImageMeaningful(_ cgImage: CGImage) -> Bool {
        // Simple heuristic: check color diversity and edge density
        // A meaningful screenshot should have varied colors and edges
        
        let width = cgImage.width
        let height = cgImage.height
        
        // Sample a grid of pixels to analyze color diversity
        let sampleSize = min(width, height, 100) // Sample up to 100x100 grid
        let stepX = max(1, width / sampleSize)
        let stepY = max(1, height / sampleSize)
        
        var colorSet = Set<UInt32>()
        var totalSamples = 0
        
        // Create a bitmap context to sample pixels
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Logger.warn("Failed to create bitmap context for image analysis")
            return true // Assume meaningful if we can't analyze
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = context.data else {
            Logger.warn("Failed to get pixel data for image analysis")
            return true // Assume meaningful if we can't analyze
        }
        
        let pixelData = data.bindMemory(to: UInt32.self, capacity: width * height)
        
        // Sample pixels in a grid pattern
        for y in stride(from: 0, to: height, by: stepY) {
            for x in stride(from: 0, to: width, by: stepX) {
                let pixelIndex = y * width + x
                if pixelIndex < width * height {
                    let pixel = pixelData[pixelIndex]
                    // Mask out alpha channel and add to color set
                    colorSet.insert(pixel & 0x00FFFFFF)
                    totalSamples += 1
                }
            }
        }
        
        let uniqueColors = colorSet.count
        let colorDiversity = Double(uniqueColors) / Double(totalSamples)
        
        Logger.debug("Image analysis: \(uniqueColors) unique colors out of \(totalSamples) samples (diversity: \(String(format: "%.2f", colorDiversity)))")
        
        // Consider an image meaningful if it has reasonable color diversity
        // Desktop backgrounds typically have lower diversity than application content
        let meaningfulThreshold = 0.1 // At least 10% color diversity
        let isMeaningful = colorDiversity > meaningfulThreshold
        
        Logger.debug("Image is \(isMeaningful ? "meaningful" : "likely background only") (diversity: \(String(format: "%.2f", colorDiversity)) vs threshold: \(meaningfulThreshold))")
        
        return isMeaningful
    }

    // MARK: - Debug Methods

    // Debug method to save images with selection rectangle overlay
    private func saveDebugImage(_ image: NSImage, name: String, rect: NSRect) {
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let debugFileURL = desktopURL.appendingPathComponent("glotera_debug_\(name).png")

        // Create a copy of the image with selection rectangle drawn on it
        let imageWithRect = addSelectionRectToImage(image, rect: rect)

        guard let tiffData = imageWithRect.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            Logger.error("❌ Failed to convert debug image \(name) to PNG")
            return
        }

        do {
            try pngData.write(to: debugFileURL)
            Logger.info("🐛 Debug image saved: \(debugFileURL.path)")
        } catch {
            Logger.error("❌ Failed to save debug image \(name): \(error)")
        }
    }

    // Debug method to save images without overlay
    private func saveDebugImageSimple(_ image: NSImage, name: String) {
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let debugFileURL = desktopURL.appendingPathComponent("glotera_debug_\(name).png")

        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            Logger.error("❌ Failed to convert debug image \(name) to PNG")
            return
        }

        do {
            try pngData.write(to: debugFileURL)
            Logger.info("🐛 Debug image saved: \(debugFileURL.path)")
        } catch {
            Logger.error("❌ Failed to save debug image \(name): \(error)")
        }
    }

    // Add selection rectangle overlay to image for debugging
    private func addSelectionRectToImage(_ image: NSImage, rect: NSRect) -> NSImage {
        let newImage = NSImage(size: image.size)
        newImage.lockFocus()

        // Draw original image
        image.draw(at: NSPoint.zero, from: NSRect(origin: .zero, size: image.size), operation: .sourceOver, fraction: 1.0)

        // Draw selection rectangle in red
        NSColor.red.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 4.0
        path.stroke()

        // Add text label with selection info
        let text = "Selected: (\(Int(rect.origin.x)),\(Int(rect.origin.y))) \(Int(rect.width))x\(Int(rect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.red,
            .font: NSFont.boldSystemFont(ofSize: 16),
            .backgroundColor: NSColor.white.withAlphaComponent(0.8)
        ]
        let textRect = NSRect(x: rect.origin.x, y: rect.origin.y - 25, width: 400, height: 20)
        text.draw(in: textRect, withAttributes: attributes)

        newImage.unlockFocus()
        return newImage
    }

    // Test method to verify screenshot functionality
    func testScreenshotFunctionality() {
        Logger.info("🧪 Testing screenshot functionality...")
        
        // Test 1: Direct screenshot capture
        if let screenshot = captureFullScreenInternal() {
            Logger.info("✅ Direct screenshot capture successful: \(screenshot.size)")
            saveDebugImageSimple(screenshot, name: "test_direct_capture")
        } else {
            Logger.error("❌ Direct screenshot capture failed")
        }
        
        // Test 2: Test the full workflow
        captureScreenshotWithSelection { image in
            if let image = image {
                Logger.info("✅ Full screenshot workflow successful: \(image.size)")
                self.saveDebugImageSimple(image, name: "test_workflow_result")
            } else {
                Logger.error("❌ Full screenshot workflow failed")
            }
        }
    }
    
    // Capture screenshot for a specific screen
    private func captureScreenForSpecificScreen(_ screen: NSScreen) -> NSImage? {
        Logger.info("🎯 Capturing screenshot for specific screen: \(screen.frame)")
        
        let screenRect = screen.frame
        let cgRect = CGRect(
            x: screenRect.origin.x,
            y: screenRect.origin.y,
            width: screenRect.size.width,
            height: screenRect.size.height
        )

        // Try multiple capture strategies for the specific screen
        let captureStrategies: [(String, CGWindowListOption)] = [
            // Strategy 1: Capture all windows on screen (most comprehensive)
            ("AllOnScreen", [.optionAll, .optionOnScreenOnly]),
            
            // Strategy 2: Capture on-screen windows including current window
            ("OnScreenIncluding", [.optionOnScreenOnly, .optionIncludingWindow]),
            
            // Strategy 3: Capture windows above current window
            ("OnScreenAbove", [.optionOnScreenAboveWindow]),
            
            // Strategy 4: Basic on-screen only
            ("OnScreenBasic", [.optionOnScreenOnly])
        ]
        
        for (strategyName, options) in captureStrategies {
            Logger.info("Trying capture strategy for specific screen: \(strategyName)")
            
            if let cgImage = CGWindowListCreateImage(cgRect, options, kCGNullWindowID, [.bestResolution, .nominalResolution]) {
                let screenSize = CGSize(width: cgImage.width, height: cgImage.height)
                let image = NSImage(cgImage: cgImage, size: screenSize)
                
                Logger.info("✅ Screenshot successful for specific screen using strategy \(strategyName): \(cgImage.width)x\(cgImage.height) pixels")
                
                // For the first successful capture, return it immediately
                // This ensures we get the current screen state
                Logger.info("✅ Using first successful capture strategy: \(strategyName)")
                return image
            } else {
                Logger.warn("❌ Strategy \(strategyName) failed for specific screen")
            }
        }
        
        Logger.error("All window capture strategies failed for specific screen")
        return nil
    }

    // Convert screen coordinates to image coordinates for a specific screen
    private func convertScreenRectToImageRect(_ screenRect: NSRect, for screen: NSScreen, imageSize: NSSize) -> NSRect {
        Logger.info("🔄 Converting screen coordinates to image coordinates:")
        Logger.info("📦 Screen rect (points): \(screenRect)")
        Logger.info("🖥️ Screen frame (points): \(screen.frame)")
        Logger.info("🖼️ Image size (pixels): \(imageSize)")
        
        // CRITICAL: The screen rect is in global screen coordinates (points)
        // We need to convert it to local screen coordinates (relative to the screen's origin)
        let screenOrigin = screen.frame.origin
        
        // Convert global screen coordinates to local screen coordinates (still in points)
        let localRect = NSRect(
            x: screenRect.origin.x - screenOrigin.x,
            y: screenRect.origin.y - screenOrigin.y,
            width: screenRect.width,
            height: screenRect.height
        )
        
        Logger.info("🖥️ Local screen rect (points): \(localRect)")
        
        // CRITICAL: Convert from points to pixels using backingScaleFactor
        let scaleFactor = screen.backingScaleFactor
        Logger.info("📊 Screen scale factor: \(scaleFactor)")
        
        let scaledRect = NSRect(
            x: localRect.origin.x * scaleFactor,
            y: localRect.origin.y * scaleFactor,
            width: localRect.width * scaleFactor,
            height: localRect.height * scaleFactor
        )

        let imageHeight = imageSize.height > 0 ? imageSize.height : screen.frame.height * scaleFactor
        let flippedY = imageHeight - (scaledRect.origin.y + scaledRect.height)
        let imageRect = NSRect(
            x: scaledRect.origin.x,
            y: flippedY,
            width: scaledRect.width,
            height: scaledRect.height
        )

        Logger.info("🖼️ Image rect (pixels): \(imageRect)")

        // Ensure the rect is within image bounds while keeping its size
        let maxX = max(0, imageSize.width - imageRect.width)
        let maxY = max(0, imageHeight - imageRect.height)
        let clampedRect = NSRect(
            x: min(max(imageRect.origin.x, 0), maxX),
            y: min(max(imageRect.origin.y, 0), maxY),
            width: imageRect.width,
            height: imageRect.height
        )
        
        Logger.info("🔒 Clamped image rect (pixels): \(clampedRect)")
        return clampedRect
    }

    // Test method specifically for multi-monitor environments
    func testMultiMonitorScreenshot() {
        Logger.info("🖥️ Testing multi-monitor screenshot functionality...")
        
        // Get all screens
        let screens = NSScreen.screens
        Logger.info("📺 Found \(screens.count) screens:")
        
        for (index, screen) in screens.enumerated() {
            Logger.info("  Screen \(index): \(screen.frame)")
        }
        
        // Get current screen (where mouse is)
        let mouseLocation = NSEvent.mouseLocation
        let currentScreen = screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main ?? screens.first!
        
        Logger.info("🖱️ Mouse at: \(mouseLocation)")
        Logger.info("🎯 Current screen: \(currentScreen.frame)")
        
        // Test capturing the current screen
        if let screenshot = captureScreenForSpecificScreen(currentScreen) {
            Logger.info("✅ Current screen capture successful: \(screenshot.size)")
            saveDebugImageSimple(screenshot, name: "test_current_screen")
        } else {
            Logger.error("❌ Current screen capture failed")
        }
        
        // Test coordinate conversion
        let testRect = NSRect(x: 100, y: 100, width: 200, height: 150)
        let convertedRect = convertScreenRectToImageRect(testRect, for: currentScreen, imageSize: NSSize(width: 1920, height: 1080))
        Logger.info("🔄 Test coordinate conversion:")
        Logger.info("  Screen rect: \(testRect)")
        Logger.info("  Image rect: \(convertedRect)")
    }
    
    // Debug method to test screenshot with specific coordinates
    func testScreenshotWithCoordinates(_ rect: NSRect) {
        Logger.info("🧪 Testing screenshot with specific coordinates: \(rect)")
        
        // Get current screen
        let mouseLocation = NSEvent.mouseLocation
        let currentScreen = NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens.first!
        
        Logger.info("🖥️ Using screen: \(currentScreen.frame)")
        Logger.info("📦 Input rect: \(rect)")
        
        // Capture screenshot
        if let screenshot = captureScreenForSpecificScreen(currentScreen) {
            Logger.info("✅ Screenshot captured: \(screenshot.size)")
            
            // Convert coordinates
            let imageRect = convertScreenRectToImageRect(rect, for: currentScreen, imageSize: screenshot.size)
            Logger.info("🖼️ Converted image rect: \(imageRect)")
            
            // Save debug images
            saveDebugImage(screenshot, name: "debug_full_screenshot", rect: imageRect)
            
            // Crop the specific area
            if let croppedImage = cropImage(screenshot, toRect: imageRect) {
                Logger.info("✅ Cropped image: \(croppedImage.size)")
                saveDebugImageSimple(croppedImage, name: "debug_cropped_result")
            } else {
                Logger.error("❌ Failed to crop image")
            }
        } else {
            Logger.error("❌ Failed to capture screenshot")
        }
    }
    
    // Simple test method for debugging - you can call this from anywhere
    func debugScreenshot() {
        Logger.info("🐛 Starting debug screenshot...")
        
        // Test with a small area around the mouse cursor
        let mouseLocation = NSEvent.mouseLocation
        let testRect = NSRect(x: mouseLocation.x - 100, y: mouseLocation.y - 100, width: 200, height: 200)
        
        Logger.info("🖱️ Mouse at: \(mouseLocation)")
        Logger.info("📦 Test rect: \(testRect)")
        
        testScreenshotWithCoordinates(testRect)
    }
    
    // Comprehensive test for all three issues
    func testAllScreenshotIssues() {
        Logger.info("🧪 Testing all screenshot issues...")
        
        // Get current screen info
        let mouseLocation = NSEvent.mouseLocation
        let currentScreen = NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens.first!
        
        Logger.info("🖥️ Current screen: \(currentScreen.frame)")
        Logger.info("📊 Screen scale factor: \(currentScreen.backingScaleFactor)")
        Logger.info("🖱️ Mouse location: \(mouseLocation)")
        
        // Test 1: Point vs Pixel conversion
        let testRect = NSRect(x: mouseLocation.x - 50, y: mouseLocation.y - 50, width: 100, height: 100)
        Logger.info("📦 Test rect (points): \(testRect)")
        
        // Test 2: Scale factor application
        let scaledRect = NSRect(
            x: testRect.origin.x * currentScreen.backingScaleFactor,
            y: testRect.origin.y * currentScreen.backingScaleFactor,
            width: testRect.width * currentScreen.backingScaleFactor,
            height: testRect.height * currentScreen.backingScaleFactor
        )
        Logger.info("📐 Scaled rect (pixels): \(scaledRect)")
        
        // Test 3: Multi-screen consistency
        let selectionCenter = NSPoint(x: testRect.origin.x + testRect.width/2, y: testRect.origin.y + testRect.height/2)
        let screenForSelection = NSScreen.screens.first { screen in
            NSMouseInRect(selectionCenter, screen.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens.first!
        
        Logger.info("🎯 Screen for selection: \(screenForSelection.frame)")
        Logger.info("✅ Same screen: \(currentScreen == screenForSelection)")
        
        // Perform actual test
        testScreenshotWithCoordinates(testRect)
    }
    
    // Test method to simulate selection with specific coordinates
    func testSelectionWithCoordinates(_ rect: NSRect) {
        Logger.info("🧪 Testing selection with coordinates: \(rect)")
        
        // Get current screen
        let mouseLocation = NSEvent.mouseLocation
        let currentScreen = NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens.first!
        
        Logger.info("🖥️ Using screen: \(currentScreen.frame)")
        Logger.info("📦 Input selection rect: \(rect)")
        
        // Simulate the selection process
        captureScreenshotWithSelection { image in
            if let image = image {
                Logger.info("✅ Selection test successful: \(image.size)")
                self.saveDebugImageSimple(image, name: "test_selection_result")
            } else {
                Logger.error("❌ Selection test failed")
            }
        }
    }
    
    // Debug method to test with the exact coordinates from your screenshot
    func testWithExactCoordinates() {
        Logger.info("🎯 Testing with exact coordinates from your screenshot...")
        
        // Based on your screenshot, the selection shows "Selected: (686,561) 1233x518"
        // But this might be the wrong coordinates. Let's test with a smaller area first
        let mouseLocation = NSEvent.mouseLocation
        let testRect = NSRect(x: mouseLocation.x - 100, y: mouseLocation.y - 100, width: 200, height: 200)
        
        Logger.info("🖱️ Mouse at: \(mouseLocation)")
        Logger.info("📦 Test rect: \(testRect)")
        
        // Test the full workflow
        captureScreenshotWithSelection { image in
            if let image = image {
                Logger.info("✅ Test successful: \(image.size)")
                self.saveDebugImageSimple(image, name: "exact_coordinates_test")
            } else {
                Logger.error("❌ Test failed")
            }
        }
    }
    
    // Test method to verify the coordinate conversion fix
    func testCoordinateConversionFix() {
        Logger.info("🔧 Testing coordinate conversion fix...")
        
        // Test with a small area around the mouse
        let mouseLocation = NSEvent.mouseLocation
        let testRect = NSRect(x: mouseLocation.x - 50, y: mouseLocation.y - 50, width: 100, height: 100)
        
        Logger.info("🖱️ Mouse at: \(mouseLocation)")
        Logger.info("📦 Test selection rect: \(testRect)")
        
        // Simulate the coordinate conversion process
        let currentScreen = NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens.first!
        
        Logger.info("🖥️ Using screen: \(currentScreen.frame)")
        Logger.info("📊 Screen scale factor: \(currentScreen.backingScaleFactor)")
        
        // Convert to image coordinates
        let imageRect = convertScreenRectToImageRect(testRect, for: currentScreen, imageSize: NSSize(width: 1920, height: 1080))
        Logger.info("🖼️ Converted image rect: \(imageRect)")
        
        // Test the full workflow
        captureScreenshotWithSelection { image in
            if let image = image {
                Logger.info("✅ Coordinate conversion test successful: \(image.size)")
                self.saveDebugImageSimple(image, name: "coordinate_conversion_test")
            } else {
                Logger.error("❌ Coordinate conversion test failed")
            }
        }
    }

    // Public cleanup method for manual cleanup if needed
    func cleanup() {
        // Remove emergency escape monitor
        removeEmergencyEscapeMonitor()

        // Cancel any running timers
        recoveryTimer?.invalidate()
        recoveryTimer = nil

        // Close screenshot window
        screenshotWindow?.orderOut(nil)
        screenshotWindow = nil

        // Force restore any hidden Glotera windows
        if !hiddenWindows.isEmpty {
            restoreGloteraWindows()
        }

        // Clear stored image
        storedScreenImage = nil

        // Clear completion handler
        completionHandler = nil

        Logger.info("ScreenshotManager cleanup completed")
    }
}

// MARK: - Transparent Selection Window (Real-time view)
class TransparentSelectionWindow: NSWindow {
    private let selectionView: TransparentSelectionOverlayView
    private let completion: (NSRect?) -> Void

    init(completion: @escaping (NSRect?) -> Void) {
        self.completion = completion

        // For multi-monitor setup, get the screen containing the mouse cursor
        let mouseLocation = NSEvent.mouseLocation
        let currentScreen = NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens.first!

        // CRITICAL: Use the screen's frame in the same coordinate system as mouse events
        let screenFrame = currentScreen.frame
        Logger.info("🖥️ Using screen frame: \(screenFrame) for mouse at: \(mouseLocation)")
        Logger.info("🪟 Window will cover: origin(\(screenFrame.origin.x), \(screenFrame.origin.y)) size(\(screenFrame.size.width) x \(screenFrame.size.height))")
        Logger.info("📊 Screen scale factor: \(currentScreen.backingScaleFactor)")

        // Create transparent selection overlay with screen frame
        // The view frame should match the screen frame exactly
        selectionView = TransparentSelectionOverlayView(frame: NSRect(origin: .zero, size: screenFrame.size))

        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .floating // Overlay above apps but allow them to show through
        self.isOpaque = false
        self.backgroundColor = NSColor.clear
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.hasShadow = false // No shadow for cleaner appearance

        // Set the transparent overlay as content view
        self.contentView = selectionView

        // CRITICAL: Ensure window can receive key events
        self.makeFirstResponder(selectionView)

        // Handle selection completion
        selectionView.onSelectionComplete = { [weak self] selectedRect in
            self?.completion(selectedRect)
        }

        // Handle escape key to cancel
        selectionView.onCancel = { [weak self] in
            self?.completion(nil)
        }
    }

    // Override key events at window level for additional escape routes
    override func keyDown(with event: NSEvent) {
        // IMMEDIATE escape on ESC key - highest priority, no modifiers needed
        if event.keyCode == 53 { // Escape key
            Logger.info("IMMEDIATE ESC key pressed in transparent selection window - exiting now")
            completion(nil)
            return // Don't call super, handle immediately
        }

        // Additional escape mechanisms
        if event.keyCode == 113 && event.modifierFlags.contains(.command) { // Cmd+F1 (emergency exit)
            Logger.info("Emergency exit key combination pressed")
            completion(nil)
            return
        }

        // Space bar as quick escape
        if event.keyCode == 49 { // Space bar
            Logger.info("Space bar pressed in transparent selection window - quick exit")
            completion(nil)
            return
        }

        super.keyDown(with: event)
    }

    // Ensure window can become key to receive keyboard events
    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return true
    }
}

// MARK: - Legacy Screenshot Selection Window (with background image)
class ScreenshotSelectionWindow: NSWindow {
    private let backgroundImageView: NSImageView
    private let selectionView: SelectionOverlayView
    private let completion: (NSRect?) -> Void

    init(backgroundImage: NSImage, completion: @escaping (NSRect?) -> Void) {
        self.completion = completion

        // Get screen bounds
        let screenFrame = NSScreen.main?.frame ?? NSRect.zero

        // Create background image view
        backgroundImageView = NSImageView(frame: screenFrame)
        backgroundImageView.image = backgroundImage
        backgroundImageView.imageScaling = .scaleAxesIndependently

        // Create selection overlay
        selectionView = SelectionOverlayView(frame: screenFrame)

        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .floating // More reasonable level
        self.isOpaque = false
        self.backgroundColor = NSColor.clear
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true

        // Setup content view
        let containerView = NSView(frame: screenFrame)
        containerView.addSubview(backgroundImageView)
        containerView.addSubview(selectionView)

        self.contentView = containerView

        // Handle selection completion
        selectionView.onSelectionComplete = { [weak self] selectedRect in
            self?.completion(selectedRect)
        }

        // Handle escape key to cancel
        selectionView.onCancel = { [weak self] in
            self?.completion(nil)
        }
    }

    // Override key events at window level for additional escape routes
    override func keyDown(with event: NSEvent) {
        // IMMEDIATE escape on ESC key - highest priority, no modifiers needed
        if event.keyCode == 53 { // Escape key
            Logger.info("IMMEDIATE ESC key pressed in screenshot window - exiting now")
            completion(nil)
            return // Don't call super, handle immediately
        }

        // Additional escape mechanisms
        if event.keyCode == 113 && event.modifierFlags.contains(.command) { // Cmd+F1 (emergency exit)
            Logger.info("Emergency exit key combination pressed")
            completion(nil)
            return
        }

        // Space bar as quick escape
        if event.keyCode == 49 { // Space bar
            Logger.info("Space bar pressed in screenshot window - quick exit")
            completion(nil)
            return
        }

        super.keyDown(with: event)
    }

    // Ensure window can become key to receive keyboard events
    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return true
    }
}

// MARK: - Selection Overlay View
class SelectionOverlayView: NSView {
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var selectionRect: NSRect = .zero

    var onSelectionComplete: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw semi-transparent overlay
        NSColor.black.withAlphaComponent(0.3).setFill()
        dirtyRect.fill()

        // Draw selection rectangle (clear area)
        if !selectionRect.isEmpty {
            NSColor.clear.setFill()
            selectionRect.fill()

            // Draw selection border
            NSColor.white.setStroke()
            let borderPath = NSBezierPath(rect: selectionRect)
            borderPath.lineWidth = 2.0
            borderPath.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = event.locationInWindow
        currentPoint = startPoint
        updateSelection()
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = event.locationInWindow
        updateSelection()
    }

    override func mouseUp(with event: NSEvent) {
        if !selectionRect.isEmpty {
            onSelectionComplete?(selectionRect)
        } else {
            onCancel?()
        }
    }

    override func keyDown(with event: NSEvent) {
        // IMMEDIATE escape on ESC key - highest priority
        if event.keyCode == 53 { // Escape key
            Logger.info("IMMEDIATE ESC key pressed in selection overlay - cancelling screenshot")
            onCancel?()
            return // Don't call super, handle immediately
        }

        // Additional escape mechanisms
        if event.keyCode == 12 && event.modifierFlags.contains(.command) { // Cmd+Q
            Logger.info("Cmd+Q pressed in selection overlay")
            onCancel?()
            return
        }

        if event.keyCode == 13 && event.modifierFlags.contains(.command) { // Cmd+W
            Logger.info("Cmd+W pressed in selection overlay")
            onCancel?()
            return
        }

        // Space bar as additional quick escape
        if event.keyCode == 49 { // Space bar
            Logger.info("Space bar pressed in selection overlay - quick cancel")
            onCancel?()
            return
        }

        super.keyDown(with: event)
    }

    override var acceptsFirstResponder: Bool {
        return true
    }

    private func updateSelection() {
        guard let start = startPoint, let current = currentPoint else { return }

        let x = min(start.x, current.x)
        let y = min(start.y, current.y)
        let width = abs(current.x - start.x)
        let height = abs(current.y - start.y)

        selectionRect = NSRect(x: x, y: y, width: width, height: height)
        needsDisplay = true
    }
}

// MARK: - Transparent Selection Overlay View (Real-time applications visible)
class TransparentSelectionOverlayView: NSView {
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var selectionRect: NSRect = .zero

    var onSelectionComplete: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTransparentView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupTransparentView() {
        self.wantsLayer = true
        // COMPLETELY transparent background - applications show through
        self.layer?.backgroundColor = NSColor.clear.cgColor
        // Enable key events
        self.acceptsTouchEvents = true
        self.becomeFirstResponder()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Only draw selection rectangle border if selection exists
        // NO background overlay - keep applications fully visible
        if !selectionRect.isEmpty {
            // Draw selection border with enhanced visibility
            NSColor.white.setStroke()
            let borderPath = NSBezierPath(rect: selectionRect)
            borderPath.lineWidth = 3.0 // Slightly thicker for better visibility
            borderPath.stroke()

            // Add a contrasting inner border for better visibility on any background
            NSColor.black.setStroke()
            let innerBorderPath = NSBezierPath(rect: selectionRect.insetBy(dx: 1.5, dy: 1.5))
            innerBorderPath.lineWidth = 1.0
            innerBorderPath.stroke()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Ensure this view becomes the first responder for key events
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        // Use event location directly - no coordinate conversion needed
        // The transparent window covers the exact same area as the captured image
        let location = event.locationInWindow
        startPoint = location
        currentPoint = startPoint

        Logger.info("🖱️ Mouse down at window location: \(location)")
        Logger.info("🖱️ Window frame: \(window?.frame ?? NSRect.zero)")
        Logger.info("🖱️ View frame: \(frame)")
        updateSelection()
    }

    override func mouseDragged(with event: NSEvent) {
        // Use event location directly - no coordinate conversion needed
        let location = event.locationInWindow
        currentPoint = location
        
        Logger.info("🖱️ Mouse dragged to window location: \(location)")
        Logger.info("🖱️ Current selection rect: \(selectionRect)")
        
        updateSelection()
    }

    override func mouseUp(with event: NSEvent) {
        // Convert selection rectangle to screen coordinates
        // The selection rect is in view coordinates, need to convert to screen coordinates
        let windowFrame = window?.frame ?? NSRect.zero
        
        // CRITICAL: Convert view coordinates to screen coordinates
        // The view coordinates are relative to the view's origin (0,0)
        // We need to add the window's position to get screen coordinates
        let screenRect = NSRect(
            x: windowFrame.origin.x + selectionRect.origin.x,
            y: windowFrame.origin.y + selectionRect.origin.y,
            width: selectionRect.width,
            height: selectionRect.height
        )
        
        Logger.info("🖱️ Mouse up - View selection rect: \(selectionRect)")
        Logger.info("🖱️ Mouse up - Window frame: \(windowFrame)")
        Logger.info("🖱️ Mouse up - Screen selection rect: \(screenRect)")
        Logger.info("🖱️ Mouse up - Mouse location: \(NSEvent.mouseLocation)")
        Logger.info("🖱️ Mouse up - Start point: \(startPoint ?? NSPoint.zero)")
        Logger.info("🖱️ Mouse up - Current point: \(currentPoint ?? NSPoint.zero)")

        if !selectionRect.isEmpty {
            Logger.info("✅ 完成选择，区域大小: \(selectionRect.width) x \(selectionRect.height)")
            onSelectionComplete?(screenRect)
        } else {
            Logger.info("❌ 选择区域为空，取消截图")
            onCancel?()
        }
    }


    override func keyDown(with event: NSEvent) {
        // IMMEDIATE escape on ESC key - highest priority
        if event.keyCode == 53 { // Escape key
            Logger.info("🚨 EMERGENCY ESC key pressed in transparent overlay - IMMEDIATE EXIT!")
            onCancel?()
            return // Don't call super, handle immediately
        }

        // Additional escape mechanisms
        if event.keyCode == 12 && event.modifierFlags.contains(.command) { // Cmd+Q
            Logger.info("Cmd+Q pressed in transparent overlay")
            onCancel?()
            return
        }

        if event.keyCode == 13 && event.modifierFlags.contains(.command) { // Cmd+W
            Logger.info("Cmd+W pressed in transparent overlay")
            onCancel?()
            return
        }

        // Space bar as additional quick escape
        if event.keyCode == 49 { // Space bar
            Logger.info("Space bar pressed in transparent overlay - quick cancel")
            onCancel?()
            return
        }

        super.keyDown(with: event)
    }

    override var acceptsFirstResponder: Bool {
        return true
    }

    private func updateSelection() {
        guard let start = startPoint, let current = currentPoint else { return }

        let x = min(start.x, current.x)
        let y = min(start.y, current.y)
        let width = abs(current.x - start.x)
        let height = abs(current.y - start.y)

        selectionRect = NSRect(x: x, y: y, width: width, height: height)
        needsDisplay = true
    }
}