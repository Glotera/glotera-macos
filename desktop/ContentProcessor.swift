//
//  ContentProcessor.swift
//  Manages content processing, such as extracting user input from mail content, etc.
//  Created by Claude Code on 2025-07-20.
//  Copyright © 2025 Glotera AI. All rights reserved.
//

import Foundation

// Chat message data model - unified structure for all chat applications
struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let sender: String
    let content: String
    let timestamp: String
    let isFromMe: Bool
    
    // Additional fields for enhanced functionality
    let messageType: String?     // Message type (e.g., "Your message", "Received message")
    let date: String?           // Date part
    let time: String?           // Time part
    
    // Translation fields
    var contentTranslation: String?
    var contentLanguage: String?
    var contentTranslationLanguage: String?
    var contentHash: String?
    
    // Custom equality check - prioritize timestamp when available
    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        // If both messages have valid timestamps, compare primarily by timestamp
        if !lhs.timestamp.isEmpty && !rhs.timestamp.isEmpty {
            return lhs.timestamp == rhs.timestamp &&
                   lhs.sender == rhs.sender
        }
        
        // Fallback to content-based comparison when timestamps are missing
        return lhs.sender == rhs.sender &&
               lhs.content == rhs.content &&
               lhs.isFromMe == rhs.isFromMe
    }
    
    // Create a unique hash for message deduplication - prioritize timestamp
    var messageHash: String {
        // If timestamp is available and valid, use it as primary identifier
        if !timestamp.isEmpty && ChatMessage.isValidTimestamp(timestamp) {
            return "\(timestamp)|\(sender)"
        }
        
        // Fallback to content-based hash
        return "\(sender)|\(content.prefix(50))|\(isFromMe)"
    }
    
    // Check if timestamp appears to be valid (contains time pattern like HH:MM)
    static func isValidTimestamp(_ timestamp: String) -> Bool {
        // Check for common time patterns: "12:34", "1:23 PM", etc.
        do {
            let regex = try NSRegularExpression(pattern: "\\d{1,2}:\\d{2}", options: [])
            let range = NSRange(location: 0, length: timestamp.utf16.count)
            return regex.firstMatch(in: timestamp, options: [], range: range) != nil
        } catch {
            return false
        }
    }
    
    // Convenience initializer for basic chat messages
    init(sender: String, content: String, timestamp: String = "", isFromMe: Bool = false) {
        self.sender = sender
        self.content = content
        self.timestamp = timestamp
        self.isFromMe = isFromMe
        self.messageType = nil
        self.date = nil
        self.time = nil
        self.contentTranslation = nil
        self.contentLanguage = nil
        self.contentTranslationLanguage = nil
        self.contentHash = nil
    }
    
    // Convenience initializer for WhatsApp messages
    init(messageType: String, content: String, sender: String, timestamp: String, isFromMe: Bool, date: String? = nil, time: String? = nil) {
        self.sender = sender
        self.content = content
        self.timestamp = timestamp
        self.isFromMe = isFromMe
        self.messageType = messageType
        self.date = date
        self.time = time
        self.contentTranslation = nil
        self.contentLanguage = nil
        self.contentTranslationLanguage = nil
        self.contentHash = nil
    }
    
    // Initializer with translation fields
    init(sender: String, content: String, timestamp: String, isFromMe: Bool, 
         contentTranslation: String?, contentLanguage: String?, 
         contentTranslationLanguage: String?, contentHash: String?) {
        self.sender = sender
        self.content = content
        self.timestamp = timestamp
        self.isFromMe = isFromMe
        self.messageType = nil
        self.date = nil
        self.time = nil
        self.contentTranslation = contentTranslation
        self.contentLanguage = contentLanguage
        self.contentTranslationLanguage = contentTranslationLanguage
        self.contentHash = contentHash
    }
    
    // Convenience method to get a formatted description
    var description: String {
        var desc = "Sender: \(sender), Content: \(content)"
        if let messageType = messageType {
            desc = "Type: \(messageType), " + desc
        }
        if !timestamp.isEmpty {
            desc += ", Time: \(timestamp)"
        }
        desc += ", IsFromMe: \(isFromMe)"
        return desc
    }
    
    // Convenience method to check if message has valid content
    var hasValidContent: Bool {
        return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // Convenience method to get sender display name
    var senderDisplayName: String {
        return sender.isEmpty ? (isFromMe ? "You" : "Unknown") : sender
    }
}

class ContentProcessor {
    static let shared = ContentProcessor()

    private init() {}

       // 从邮件内容中提取用户正在输入的部分
    func extractUserInputFromMailContent(_ content: String) -> String {
        Logger.info("Apple Mail: Extracting user input from mail content")
        
        let lines = content.components(separatedBy: .newlines)
        var userLines: [String] = []
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // 跳过空行
            if trimmedLine.isEmpty {
                continue
            }
            
            // 检查是否是邮件历史标记的开始
            if isMailHistoryMarker(trimmedLine) {
                Logger.info("Apple Mail: Found mail history marker, stopping extraction")
                break
            }
            
            userLines.append(line)
        }
        
        let userContent = userLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        Logger.info("Apple Mail: Extracted user content: '\(userContent)'")
        
        return userContent
    }
    
    // 检查是否是邮件历史标记
    private func isMailHistoryMarker(_ line: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        
        // 常见的邮件历史标记
        let historyMarkers = [
            "On ", // "On [date], [person] wrote:"
            "From:", // "From: [email]"
            "To:", // "To: [email]"  
            "Subject:", // "Subject: [subject]"
            "Date:", // "Date: [date]"
            "Sent:", // "Sent: [date]"
            "-----Original Message-----", // Outlook style
            "Begin forwarded message:", // Apple Mail forwarding
            "---------- Forwarded message ----------", // Gmail style
            "> ", // Quoted text
            ">>", // Multiple level quotes
        ]
        
        for marker in historyMarkers {
            if trimmedLine.hasPrefix(marker) {
                return true
            }
        }
        
        // 检查是否是邮件签名分隔符
        if trimmedLine == "--" || trimmedLine.hasPrefix("--") {
            return true
        }
        
        // 检查是否是时间戳格式的行 (如 "2024-01-01 10:00:00")
        let dateRegex = try? NSRegularExpression(pattern: "\\d{4}-\\d{2}-\\d{2}|\\d{1,2}/\\d{1,2}/\\d{4}", options: [])
        if let regex = dateRegex {
            let matches = regex.matches(in: trimmedLine, options: [], range: NSRange(location: 0, length: trimmedLine.count))
            if !matches.isEmpty {
                return true
            }
        }
        
        return false
    }

       
    // 预处理内容：清理可能的干扰文本
    func preprocessContent(_ content: String) -> String {
        // 首先，执行通用清理，移除零宽空格等不可见字符，这对于修复飞书等Electron应用至关重要
        let cleaned = content.replacingOccurrences(of: "\u{200B}", with: "")
        if cleaned.count != content.count {
            Logger.info("Pre-processed content: Removed invisible characters.")
        }
        
        // 检查当前应用是否为Discord或其他聊天应用
        // let isDiscordOrChat = AppDetectionManager.shared.isDiscordOrChatApp()
        
        // // 对于Discord等聊天应用，使用更保守的清理策略
        // if isDiscordOrChat {
        //     Logger.info("Detected Discord/Chat app - using conservative preprocessing")
        //     // 只进行基本的空格合并，不移除任何文本内容
        //     cleaned = cleaned.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        //     cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        //     return cleaned
        // }
        
        // 对于其他应用（如Notion），使用更激进的清理策略
        // 移除常见的Notion界面元素文本
        // let notionInterferencePatterns = [
        //     "Add cover",
        //     "Add icon",
        //     "Add comment",
        //     "Untitled",
        //     "Type '/' for commands",
        //     "Press Enter to continue writing or type '/' for commands",
        //     "Empty page",
        //     "Start writing...",
        //     "Click to edit",
        //     "Add a page inside",
        //     "New page",
        //     "Template",
        //     "Import",
        //     "Database",
        //     "Gallery",
        //     "Board",
        //     "Timeline",
        //     "Calendar",
        //     "List"
        // ]
        
        // // 移除这些干扰文本（不区分大小写）
        // for pattern in notionInterferencePatterns {
        //     cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .caseInsensitive)
        // }
        
        // 移除表格相关的干扰内容
        // 匹配类似 "Column 1Column 2Column 3" 这样的表格标题
        // cleaned = cleaned.replacingOccurrences(of: #"Column\s*\d+"#, with: "", options: .regularExpression)
        
        // // 只合并连续的空格和制表符，保留换行符
        // cleaned = cleaned.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        
        // // 移除行首行尾的空白，但保留换行符
        // let lines = cleaned.components(separatedBy: .newlines)
        // let trimmedLines = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        // cleaned = trimmedLines.joined(separator: "\n")
        
        // // 最终去掉首尾空白
        // cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 如果清理后的内容太短或为空，返回原内容
        if cleaned.isEmpty || cleaned.count < 3 {
            return content
        }
        
        return cleaned
    }

       // 解析 WhatsApp 消息格式 - 返回包含详细信息的 ChatMessage 结构体
    func parseWhatsAppMessage(_ rawText: String) -> ChatMessage? {
        Logger.debug("Attempting to parse WhatsApp message: '\(rawText)'")
        
        // 清理不可见字符，特别是 U+200E (左到右标记)
        let cleanedText = rawText.replacingOccurrences(of: "\u{200E}", with: "")
                                  .replacingOccurrences(of: "\u{200B}", with: "")
                                  .trimmingCharacters(in: .whitespacesAndNewlines)
        
        Logger.debug("Cleaned text: '\(cleanedText)'")
        
        // 过滤贴纸消息 - 如果消息以 "Sticker with:" 开头，则跳过
        if cleanedText.hasPrefix("Sticker with:") {
            Logger.debug("Skipping sticker message: '\(cleanedText)'")
            return nil
        }
        
        // WhatsApp 消息格式分析：
        // 发送消息: "Your message, [内容], [日期],at[时间], Sent to [联系人], Red"
        // 接收消息: "message, [内容], [日期],at[时间], Received from [联系人]"
        
        // 首先检查消息类型
        let messageType: String
        let isSent: Bool
        
        if cleanedText.hasPrefix("Your message") {
            messageType = "Your message"
            isSent = true
        } else if cleanedText.hasPrefix("message") {
            messageType = "message"
            isSent = false
        } else {
            Logger.warn("Unknown message type: '\(cleanedText)'")
            return nil
        }
        
        // 使用正则表达式提取各个部分
        let pattern: String
        if isSent {
            // 发送消息模式: 
            // 1. "Your message, [内容], [日期],at[时间], Sent to [联系人], Red"
            // 2. "Your message, [内容], [时间], Sent to [联系人]" (当天消息)
            pattern = #"Your message,\s*(.*?),\s*(?:([A-Za-z]+\d+),\s*at)?(\d{1,2}:\d{2}),\s*Sent to\s+(.*?)(?:,\s*Red)?$"#
        } else {
            // 接收消息模式:
            // 1. "message, [内容], [日期],at[时间], Received from [联系人]"
            // 2. "message, [内容], [时间], Received from [联系人]" (当天消息)
            pattern = #"message,\s*(.*?),\s*(?:([A-Za-z]+\d+),\s*at)?(\d{1,2}:\d{2}),\s*Received from\s+(.*?)$"#
        }
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(location: 0, length: cleanedText.utf16.count)
            
            if let match = regex.firstMatch(in: cleanedText, options: [], range: range) {
                // 提取各个部分
                let contentRange = Range(match.range(at: 1), in: cleanedText)!
                let timeRange = Range(match.range(at: 3), in: cleanedText)!
                let senderRange = Range(match.range(at: 4), in: cleanedText)!
                
                let content = String(cleanedText[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                let rawTime = String(cleanedText[timeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                let sender = String(cleanedText[senderRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                // 检查是否有日期部分（可选）
                var rawDate = ""
                if match.range(at: 2).location != NSNotFound {
                    let dateRange = Range(match.range(at: 2), in: cleanedText)!
                    rawDate = String(cleanedText[dateRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                // 解析标准化的日期和时间
                let (standardDate, standardTime) = parseStandardDateTime(rawDate: rawDate, rawTime: rawTime)
                let timestamp = "\(standardDate), \(standardTime)"
                
                // 对于发送的消息，sender 应该是"我"，而不是接收方
                let finalSender: String
                if isSent {
                    finalSender = "You"  // 或者使用 "我" 如果希望显示中文
                } else {
                    finalSender = sender
                }
                
                Logger.debug("Successfully parsed WhatsApp message: Type=\(messageType), Content='\(content)', Sender='\(finalSender)', Time='\(timestamp)', IsSent=\(isSent)")
                
                return ChatMessage(
                    messageType: messageType,
                    content: content,
                    sender: finalSender,
                    timestamp: timestamp,
                    isFromMe: isSent,
                    date: standardDate,
                    time: standardTime
                )
            }
        } catch {
            Logger.warn("Regex error: \(error)")
        }
        
        // 如果正则表达式匹配失败，尝试备用解析方法
        Logger.info("Regex parsing failed, trying fallback method")
        return parseWhatsAppMessageFallback(cleanedText, messageType: messageType, isSent: isSent)
    }
    
    // 备用解析方法 - 使用传统的分割方法
    private func parseWhatsAppMessageFallback(_ text: String, messageType: String, isSent: Bool) -> ChatMessage? {
        let parts = text.components(separatedBy: ",")
        
        guard parts.count >= 4 else {
            Logger.warn("Fallback parsing failed: insufficient parts (\(parts.count))")
            return nil
        }
        
        // 从后往前找发送人信息
        var senderName: String?
        var timeString: String?
        var dateString: String?
        
        // 查找发送人信息
        for i in stride(from: parts.count - 1, through: 0, by: -1) {
            let part = parts[i].trimmingCharacters(in: .whitespacesAndNewlines)
            
            if isSent && (part.lowercased().contains("sent to") || part.lowercased().contains("send to")) {
                if let range = part.range(of: "to ", options: .caseInsensitive) {
                    senderName = String(part[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                break
            } else if !isSent && (part.lowercased().contains("received from") || part.lowercased().contains("receive from")) {
                if let range = part.range(of: "from ", options: .caseInsensitive) {
                    senderName = String(part[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                break
            }
        }
        
        // 查找时间信息
        for i in stride(from: parts.count - 2, through: 0, by: -1) {
            let part = parts[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if part.lowercased().hasPrefix("at") && part.contains(":") {
                timeString = part
                // 查找日期
                if i > 0 {
                    let datePart = parts[i - 1].trimmingCharacters(in: .whitespacesAndNewlines)
                    let datePattern = #"(?i)(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s*\d+"#
                    if datePart.range(of: datePattern, options: .regularExpression) != nil {
                        dateString = datePart
                    }
                }
                break
            }
        }
        
        // 提取消息内容
        var contentParts: [String] = []
        let contentStartIndex = 1 // 跳过消息类型
        
        // 找到内容结束位置
        var contentEndIndex = parts.count - 1
        if let timeIndex = parts.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("at") }) {
            contentEndIndex = timeIndex - 1
        }
        
        for i in contentStartIndex...contentEndIndex {
            contentParts.append(parts[i])
        }
        
        let content = contentParts.joined(separator: ",").trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 对于发送的消息，sender 应该是"我"，而不是接收方
        let finalSender: String
        if isSent {
            finalSender = "You"  // 或者使用 "我" 如果希望显示中文
        } else {
            finalSender = senderName ?? "Unknown"
        }
        
        // 解析标准化的日期和时间
        let (standardDate, standardTime) = parseStandardDateTime(rawDate: dateString ?? "", rawTime: timeString ?? "")
        let timestamp = "\(standardDate), \(standardTime)"
        
        Logger.debug("Fallback parsed: Content='\(content)', Sender='\(finalSender)', Time='\(timestamp)'")
        
        return ChatMessage(
            messageType: messageType,
            content: content,
            sender: finalSender,
            timestamp: timestamp,
            isFromMe: isSent,
            date: standardDate,
            time: standardTime
        )
    }
    
    // 解析标准化的日期和时间
    private func parseStandardDateTime(rawDate: String, rawTime: String) -> (date: String, time: String) {
        // 解析日期：将 "July30" 转换为 "July 30"
        var standardDate = rawDate
        if !rawDate.isEmpty {
            // 在月份和日期之间添加空格
            let datePattern = #"(?i)(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)(\d+)"#
            if let regex = try? NSRegularExpression(pattern: datePattern, options: []) {
                let range = NSRange(location: 0, length: rawDate.utf16.count)
                if let match = regex.firstMatch(in: rawDate, options: [], range: range) {
                    let monthRange = Range(match.range(at: 1), in: rawDate)!
                    let dayRange = Range(match.range(at: 2), in: rawDate)!
                    let month = String(rawDate[monthRange])
                    let day = String(rawDate[dayRange])
                    standardDate = "\(month) \(day)"
                }
            }
        } else {
            // 如果没有日期，使用今天的日期
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM d"
            standardDate = formatter.string(from: Date())
        }
        
        // 解析时间：将 "at16:23" 转换为 "16:23"
        var standardTime = rawTime
        if !rawTime.isEmpty {
            // 移除 "at" 前缀
            if rawTime.lowercased().hasPrefix("at") {
                standardTime = String(rawTime.dropFirst(2))
            }
            
            // 确保时间格式正确 (HH:MM)
            let timePattern = #"(\d{1,2}):(\d{2})"#
            if let regex = try? NSRegularExpression(pattern: timePattern, options: []) {
                let range = NSRange(location: 0, length: standardTime.utf16.count)
                if let match = regex.firstMatch(in: standardTime, options: [], range: range) {
                    let hourRange = Range(match.range(at: 1), in: standardTime)!
                    let minuteRange = Range(match.range(at: 2), in: standardTime)!
                    let hour = String(standardTime[hourRange])
                    let minute = String(standardTime[minuteRange])
                    
                    // 格式化小时为两位数
                    let formattedHour = hour.count == 1 ? "0\(hour)" : hour
                    standardTime = "\(formattedHour):\(minute)"
                }
            }
        }
        
        return (standardDate, standardTime)
    }
     
}

// MARK: - WhatsApp Message Parsing Examples
extension ContentProcessor {
    /// Example usage of the new ChatMessage parsing functionality
    static func demonstrateWhatsAppParsing() {
        let examples = [
            "Your message, Hello world, July22, at08:38, Sent to John Warhol, Red",
            "Received message, How are you?, July22, at08:38, Received from Jane Doe, Blue",
            "Your message, Hello, world, how are you?, July22, at08:38, Sent to John Warhol, Red",
            "Your message, Test message, please ignore it, 22:52, Sent to Princeton",
            "message, How are you today?, 14:30, Received from Alice",
            "Your message, Simple content",
            "Sticker with: 😂, July22, at08:38, Sent to John Warhol, Red",
            "Sticker with: 🎉, July22, at08:38, Received from Jane Doe, Blue"
        ]
        
        for (index, example) in examples.enumerated() {
            Logger.info("=== Example \(index + 1) ===")
            Logger.info("Input: '\(example)'")
            
            if let result = ContentProcessor.shared.parseWhatsAppMessage(example) {
                Logger.info("✅ Parsed successfully:")
                Logger.info("  - Type: \(result.messageType ?? "N/A")")
                Logger.info("  - Content: \(result.content)")
                Logger.info("  - Sender: \(result.senderDisplayName)")
                Logger.info("  - Timestamp: \(result.timestamp)")
                Logger.info("  - Date: \(result.date ?? "N/A")")
                Logger.info("  - Time: \(result.time ?? "N/A")")
                Logger.info("  - Is From Me: \(result.isFromMe)")
                Logger.info("  - Has Valid Content: \(result.hasValidContent)")
            } else {
                Logger.info("❌ Failed to parse")
            }
            Logger.info("---")
        }
    }
}