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
        guard let window = self.window else { 
            Logger.error("UserGuideWindow: Window is nil")
            return 
        }
        
        // 获取内容
        let content = getUserGuideContent()
        Logger.info("UserGuideWindow: Content length: \(content.count)")
        Logger.info("UserGuideWindow: Content preview: '\(content.prefix(200))'")
        
        // 创建一个简单的 NSScrollView 和 NSTextView
        let scrollView = NSScrollView(frame: window.contentView!.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        
        let textView = NSTextView(frame: scrollView.bounds)
        textView.autoresizingMask = [.width, .height]
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.textColor
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 20, height: 20)
        
        // 设置文本内容 - 渲染 Markdown
        let attributedContent = renderMarkdown(content)
        textView.textStorage?.setAttributedString(attributedContent)
        
        // 配置文本容器
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width - 40, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        
        // 设置滚动视图
        scrollView.documentView = textView
        window.contentView = scrollView
        
        // 强制刷新
        textView.needsDisplay = true
        scrollView.needsDisplay = true
        
        Logger.info("UserGuideWindow: Setup completed with textView.string.count = \(textView.string.count)")
    }
    
    private func getUserGuideContent() -> String {
        // 先尝试从文件读取
        if let path = Bundle.main.path(forResource: "UserGuide", ofType: "md") {
            Logger.info("UserGuideWindow: Found UserGuide.md at path: \(path)")
            
            do {
                let content = try String(contentsOfFile: path, encoding: .utf8)
                Logger.info("UserGuideWindow: Successfully loaded content from bundle, length: \(content.count)")
                Logger.info("UserGuideWindow: Content preview: '\(content.prefix(200))'")
                return content
            } catch {
                Logger.error("UserGuideWindow: Failed to read content from file at \(path), error: \(error)")
            }
        } else {
            Logger.error("UserGuideWindow: UserGuide.md not found in bundle")
            
            // 尝试其他可能的路径
            if let bundleURL = Bundle.main.url(forResource: "UserGuide", withExtension: "md") {
                Logger.info("UserGuideWindow: Found UserGuide.md via URL at: \(bundleURL.path)")
                do {
                    let content = try String(contentsOf: bundleURL, encoding: .utf8)
                    Logger.info("UserGuideWindow: Successfully loaded content via URL, length: \(content.count)")
                    return content
                } catch {
                    Logger.error("UserGuideWindow: Failed to read content via URL, error: \(error)")
                }
            } else {
                Logger.error("UserGuideWindow: UserGuide.md not found via URL either")
            }
        }
        
        // 如果没有文件，返回默认内容
        Logger.info("UserGuideWindow: Using default content")
        let defaultContent = getDefaultUserGuideContent()
        Logger.info("UserGuideWindow: Default content length: \(defaultContent.count)")
        return defaultContent
    }
    
    private func renderMarkdown(_ markdown: String) -> NSAttributedString {
        let attributedString = NSMutableAttributedString()
        let lines = markdown.components(separatedBy: .newlines)
        
        let baseFont = NSFont.systemFont(ofSize: 14)
        let titleFont = NSFont.boldSystemFont(ofSize: 20)
        let subtitleFont = NSFont.boldSystemFont(ofSize: 16)
        let codeFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        
        let baseColor = NSColor.textColor
        let linkColor = NSColor.systemBlue
        
        for (index, line) in lines.enumerated() {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: baseColor
            ]
            
            var processedLine = line
            
            // 处理标题
            if line.hasPrefix("# ") {
                processedLine = String(line.dropFirst(2))
                attributes[.font] = titleFont
                attributes[.foregroundColor] = NSColor.labelColor
            } else if line.hasPrefix("## ") {
                processedLine = String(line.dropFirst(3))
                attributes[.font] = subtitleFont
                attributes[.foregroundColor] = NSColor.labelColor
            } else if line.hasPrefix("### ") {
                processedLine = String(line.dropFirst(4))
                attributes[.font] = NSFont.boldSystemFont(ofSize: 14)
                attributes[.foregroundColor] = NSColor.labelColor
            }
            
            // 处理列表项
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                processedLine = "• " + String(line.dropFirst(2))
            } else if line.range(of: #"^\d+\. "#, options: .regularExpression) != nil {
                // 数字列表保持原样
            }
            
            // 处理代码块（简单的反引号处理）
            if line.hasPrefix("```") {
                // 跳过代码块标记行，但保留换行
                if index < lines.count - 1 {
                    attributedString.append(NSAttributedString(string: "\n"))
                }
                continue
            }
            
            // 处理行内代码
            let codePattern = "`([^`]+)`"
            if let regex = try? NSRegularExpression(pattern: codePattern) {
                let nsString = processedLine as NSString
                let matches = regex.matches(in: processedLine, range: NSRange(location: 0, length: nsString.length))
                
                if !matches.isEmpty {
                    var lastEnd = 0
                    let lineAttributedString = NSMutableAttributedString()
                    
                    for match in matches {
                        // 添加代码前的文本
                        if match.range.location > lastEnd {
                            let beforeCode = nsString.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
                            lineAttributedString.append(NSAttributedString(string: beforeCode, attributes: attributes))
                        }
                        
                        // 添加代码文本
                        let codeText = nsString.substring(with: match.range(at: 1))
                        var codeAttributes = attributes
                        codeAttributes[.font] = codeFont
                        codeAttributes[.backgroundColor] = NSColor.controlBackgroundColor
                        lineAttributedString.append(NSAttributedString(string: codeText, attributes: codeAttributes))
                        
                        lastEnd = match.range.location + match.range.length
                    }
                    
                    // 添加剩余的文本
                    if lastEnd < nsString.length {
                        let afterCode = nsString.substring(from: lastEnd)
                        lineAttributedString.append(NSAttributedString(string: afterCode, attributes: attributes))
                    }
                    
                    attributedString.append(lineAttributedString)
                } else {
                    attributedString.append(NSAttributedString(string: processedLine, attributes: attributes))
                }
            } else {
                attributedString.append(NSAttributedString(string: processedLine, attributes: attributes))
            }
            
            // 添加换行符（除了最后一行）
            if index < lines.count - 1 {
                attributedString.append(NSAttributedString(string: "\n"))
            }
        }
        
        // 设置段落样式
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        paragraphStyle.paragraphSpacing = 8
        
        attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: attributedString.length))
        
        return attributedString
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