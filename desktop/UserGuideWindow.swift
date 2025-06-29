import Cocoa

class UserGuideWindow: NSWindowController {
    
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        self.init(window: window)
        
        window.title = "Glotera User Guide"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 600, height: 400)
        
        setupContent()
    }
    
    private func setupContent() {
        guard let window = self.window else { return }
        
        // 创建滚动视图
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        
        // 创建文本视图
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.textColor
        textView.font = NSFont.systemFont(ofSize: 14)
        
        // 设置文本内容
        let content = getUserGuideContent()
        textView.string = content
        
        // 设置文本容器
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        
        // 将文本视图添加到滚动视图
        scrollView.documentView = textView
        
        // 设置为窗口的内容视图
        window.contentView = scrollView
        
        Logger.info("UserGuideWindow: Simple text view setup completed")
    }
    
    private func getUserGuideContent() -> String {
        // 先尝试从文件读取
        if let path = Bundle.main.path(forResource: "UserGuide", ofType: "md"),
           let content = try? String(contentsOfFile: path, encoding: .utf8) {
            Logger.info("UserGuideWindow: Loaded content from bundle")
            return content
        }
        
        // 如果没有文件，返回默认内容
        Logger.info("UserGuideWindow: Using default content")
        return getDefaultUserGuideContent()
    }
    
    private func getDefaultUserGuideContent() -> String {
        return """
# Glotera User Guide

## Function Overview
Glotera is a cross-application translation assistant for macOS that allows you to quickly translate and replace the original text in any input field or selected text. It supports multiple triggering methods, suitable for both input and reading scenarios.

## How to Use

### Input Translation
- After entering content in any input field, specify the target language (100+), and it will automatically translate and replace the original text.
- Supports the following triggering methods:
  - Type @language code or #language code (e.g., @en or #ja), then double-click the spacebar to initiate the translation.
  - Pressing the enter key directly after inputting will automatically translate and send (this only works in chat software clients; you can disable this feature in the settings if not desired).
  - Use the mouse or Cmd+A to select all input content, then click "Translate to" in the pop-up menu or any other language you wish to translate to.

### Reading Translation
- In non-input areas such as web pages, selecting any text will pop up a translation overlay that quickly displays the corresponding language content.

## Personalization Settings
- In Settings, you can customize the triggering commands for any language (e.g., change @zh-tw to @tw).
- If you do not want the enter key to trigger translation, you can disable this feature in the settings (Remember to click Save after making changes).

## Language Support
Glotera supports 100+ languages including:
- English (en)
- Chinese Simplified (zh)
- Chinese Traditional (zh-tw)
- Japanese (ja)
- Korean (ko)
- Spanish (es)
- French (fr)
- German (de)
- Italian (it)
- Portuguese (pt)
- Russian (ru)
- Arabic (ar)
- Hindi (hi)
- And many more...

## Keyboard Shortcuts
- Cmd+A: Select all text in input fields
- Double-click Space: Trigger translation after language code
- Enter: Auto-translate and send (in chat applications)

## Troubleshooting
If you encounter any issues:
1. Check that accessibility permissions are granted
2. Restart the application
3. Check the system console for error messages
4. Contact support if problems persist

## About
Glotera is designed to make cross-language communication seamless and efficient. For more information, visit our website or contact support.
"""
    }
    
    deinit {
        Logger.info("UserGuideWindow: Deallocating")
    }
} 