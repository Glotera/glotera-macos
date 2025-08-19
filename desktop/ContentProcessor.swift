//
//  ContentProcessor.swift
//  Manages content processing, such as extracting user input from mail content, etc.
//  Created by Claude Code on 2025-07-20.
//  Copyright © 2025 Glotera AI. All rights reserved.
//

import Foundation
import NaturalLanguage

// Chat message data model - unified structure for all chat applications
struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let content: String
    let sender: String
    let timestamp: String
    let isFromMe: Bool
    
    // Additional fields for enhanced functionality
    let messageType: String?     // Message type (e.g., text, sticker, image, video, audio, etc.)
    
    // Translation fields
    var contentTranslation: String?
    var contentLanguage: String?
    var contentTranslationLanguage: String?
    var contentHash: String?
    
    init(messageType: String?, content: String, sender: String, timestamp: String, isFromMe: Bool) {
        self.messageType = messageType
        self.content = content
        self.sender = sender
        self.timestamp = timestamp
        self.isFromMe = isFromMe
        self.contentTranslation = nil
        self.contentLanguage = nil
        self.contentTranslationLanguage = nil
        self.contentHash = nil
    }
    
    // Convenience initializer for backward compatibility
    init(messageType: String?, content: String, sender: String, timestamp: String, isFromMe: Bool, date: String?, time: String?) {
        self.messageType = messageType
        self.content = content
        self.sender = sender
        self.timestamp = timestamp
        self.isFromMe = isFromMe
        self.contentTranslation = nil
        self.contentLanguage = nil
        self.contentTranslationLanguage = nil
        self.contentHash = nil
    }
    
    // Initializer with translation fields
    init(sender: String, content: String, timestamp: String, isFromMe: Bool, 
         contentTranslation: String?, contentLanguage: String?, 
         contentTranslationLanguage: String?, contentHash: String?) {
        self.messageType = nil
        self.content = content
        self.sender = sender
        self.timestamp = timestamp
        self.isFromMe = isFromMe
        self.contentTranslation = contentTranslation
        self.contentLanguage = contentLanguage
        self.contentTranslationLanguage = contentTranslationLanguage
        self.contentHash = contentHash
    }
    
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
    
    // Convenience method to get a formatted description
    var description: String {
        return "Type: \(messageType ?? "Unknown"), Content: \(content), Sender: \(sender), Time: \(timestamp), IsFromMe: \(isFromMe)"
    }
    
    // Convenience method to check if content is valid
    var hasValidContent: Bool {
        return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // Convenience method to get sender display name
    var senderDisplayName: String {
        if sender.isEmpty {
            return isFromMe ? "You" : "Unknown"
        }
        return sender
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

    // MARK: - Language Detection
    /// Detect language of text using NaturalLanguage.NLLanguageRecognizer (BCP 47 codes)
    static func detectLanguage(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "unknown" }

        if let lang = NLLanguageRecognizer.dominantLanguage(for: trimmed) {
            let code = lang.rawValue
            Logger.debug("NLLanguageRecognizer detected language: \(code) for text: \(trimmed.prefix(50))...")

            // Normalize Chinese variants to "zh"
            if code == "zh-Hans" || code == "zh-CN"  {
                return "zh"
            }
            
            if code == "zh-Hant" || code == "zh-TW" || code == "zh-HK" {
                return "zh-TW"
            }

            // Map undefined to unknown
            if code == "und" { return "unknown" }

            return code
        }

        Logger.debug("NLLanguageRecognizer failed to detect language")
        return "unknown"
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
    func parseWhatsAppMessage(_ rawText: String, language: String? = nil) -> ChatMessage? {
        Logger.info("Attempting to parse WhatsApp message: '\(rawText)'")
        
        // 过滤贴纸消息 - 如果消息以 "Sticker with:" 开头，则跳过
        // 两个\u{200E}开头可能是"\u{200E}\u{200E}消息和通话已进行端到端加密。。。"
        if rawText.hasPrefix("\u{200E}Sticker with:") ||
           rawText.hasPrefix("\u{200E}有这个表情符号的贴图：") ||
           rawText.hasPrefix("\u{200E}GIF,") ||
           rawText.hasPrefix("\u{200E}你的视频") ||
           rawText.hasPrefix("\u{200E}your video") ||
           rawText.hasPrefix("\u{200E}\u{200E}") {
            Logger.debug("Skipping sticker message: '\(rawText)'")
            return nil
        }
        
        // 根据U+200E字符进行分隔
        let parts = rawText.components(separatedBy: "\u{200E}")
        Logger.debug("Split by U+200E into \(parts.count) parts: \(parts)")
        if parts.count<3 {
            Logger.debug("Skipping message: '\(rawText)'")
            return nil
        } 

        // 获取系统语言
        let systemLanguage = language ?? EnvironmentManager.shared.getSystemLanguage()
        Logger.debug("System language: \(systemLanguage)")
        
        // 根据系统语言和分隔后的部分进行解析
        switch systemLanguage {
        case "zh":
            return parseChineseWhatsAppMessage(parts)
        case "en":
            return parseEnglishWhatsAppMessage(parts)
        default:
            // 默认使用英文解析
            Logger.warn("Unsupported system language: \(systemLanguage), using English parser")
            return parseEnglishWhatsAppMessage(parts)
        }
    } 
    
    // 解析中文WhatsApp消息
    private func parseChineseWhatsAppMessage(_ parts: [String]) -> ChatMessage? {
        Logger.debug("Parsing Chinese WhatsApp message with \(parts.count) parts")
        
        // 根据whatsapp.md分析，中文消息格式：
        // 接收消息：‎消息, [内容], [时间], ‎从[联系人]收到
        // 发送消息：‎你的消息, [内容], [时间], ‎已发送到[联系人], ‎[状态]
        // 接收群消息：‎[发送人]发来的消息, [内容], [时间], ‎在[群名]收到
        // 发送群消息：‎你的消息, [内容], [时间], ‎发送到[群名], ‎[状态]
        guard parts.count >= 3 else {
            Logger.warn("Chinese message has insufficient parts: \(parts.count)")
            return nil
        }
        
        // Determine sent/received by content instead of relying on parts count
        // Sent when first part starts with "你的消息" or second part contains "已发送到"/"发送到"
        var isSent = parts.count == 4
        if !isSent {
            let firstPartCheck = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let firstPartHead = firstPartCheck.components(separatedBy: ",").first ?? firstPartCheck
            if firstPartHead.contains("你的消息") { isSent = true }
        }
        
        let messageType = "text"
         
        
        // 解析第一部分：提取内容及时间
        let firstPart = parts[1]
        let contentStartIndex = firstPart.firstIndex(of: ",")?.utf16Offset(in: firstPart) ?? 0
        // Get the position of the second-to-last comma
        let commaIndices = firstPart.indices.filter { firstPart[$0] == "," }
        let contentEndIndex = commaIndices.count >= 2 ? commaIndices[commaIndices.count - 2].utf16Offset(in: firstPart) : 0
        let content = String(firstPart.prefix(contentEndIndex).dropFirst(contentStartIndex + 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        // If split by comma, should get the second-to-last part as time string
        let firstPartComponents = firstPart.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let timeString = firstPartComponents.count >= 2 ? String(firstPartComponents[firstPartComponents.count - 2]) : ""
        
        
        // 解析第二部分：提取发送人信息
        var senderName = ""  
        let preContent = String(firstPartComponents[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        if preContent.contains("发来的消息") {
            // 接收群消息：‎[发送人]发来的消息, [内容], [时间], ‎在[群名]收到
            let senderRange = preContent.range(of: "发来的消息")
            if let senderRange = senderRange {
                senderName = String(preContent[..<senderRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } 

        // 第二部分包含发送人信息
        let secondPart = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        if isSent {
            // 发送消息：已发送到[联系人]
            senderName = "You"
        } else {
            // 接收消息：从[联系人]收到
            if let range = secondPart.range(of: "从") {
                let afterFrom = String(secondPart[range.upperBound...])
                if let receivedRange = afterFrom.range(of: "收到") {
                    senderName = String(afterFrom[..<receivedRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    senderName = afterFrom.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }  
        
        // 解析标准化的日期和时间
        let timestamp = parseStandardDateTime(rawDateTime: timeString, language: "zh")  
        Logger.debug("Chinese parsed: Content='\(content)', Sender='\(senderName)', Time='\(timestamp)'")
        
        return ChatMessage(
            messageType: messageType,
            content: content,
            sender: senderName,
            timestamp: timestamp,
            isFromMe: isSent
        )
    }
    
    // 解析英文WhatsApp消息
    private func parseEnglishWhatsAppMessage(_ parts: [String]) -> ChatMessage? {
        Logger.debug("Parsing English WhatsApp message with \(parts.count) parts")
        
        // 根据whatsapp.md分析，英文消息格式：
        // 接收消息：‎message, [内容], [日期],at[时间], ‎Received from [联系人]
        // 发送消息：‎Your message, [内容], [日期],at[时间], ‎Sent to [联系人], ‎[状态]
        
        guard parts.count >= 3 else {
            Logger.warn("English message has insufficient parts: \(parts.count)")
            return nil
        }

        // Determine sent/received by content instead of relying on parts count
        // Sent when first part contains "Your message" or second part contains "Sent to"
        var isSent = parts.count == 4
        if !isSent {
            let firstPartCheck = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let firstPartHead = firstPartCheck.components(separatedBy: ",").first ?? firstPartCheck
            if firstPartHead.contains("Your message") { isSent = true }
        }
        
        let messageType = "text"
        var content = ""
        var timeString = ""
        var senderName = ""
        
        // 第一部分包含消息类型和内容
        let firstPart = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let firstParts = firstPart.components(separatedBy: ",")
        // Special handling: if the last part starts with "at" and is a time (e.g., at16:23), merge last two parts as timeString,
        // remove the first part (message type), remove the time, and treat the middle as content.
        if firstParts.count >= 4 {
            let preContent = String(firstParts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            if preContent.contains("message from ") {
                // 接收群消息：‎message from [发送人], [内容], [时间], ‎Received at [群名]
                let senderRange = preContent.range(of: "message from ")
                if let senderRange = senderRange {
                    senderName = String(preContent[senderRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            
            let lastPart = firstParts[firstParts.count - 2].trimmingCharacters(in: .whitespacesAndNewlines)
            let secondLastPart = firstParts[firstParts.count - 3].trimmingCharacters(in: .whitespacesAndNewlines)
            // Check if last part starts with "at" and is a time (e.g., at16:23)
            if lastPart.hasPrefix("at") && lastPart.count >= 5 {
                let timeCandidate = String(lastPart.dropFirst(2))
                // Check if timeCandidate is in HH:MM format
                let timeRegex = try? NSRegularExpression(pattern: #"^\d{1,2}:\d{2}$"#)
                if let regex = timeRegex, regex.firstMatch(in: timeCandidate, options: [], range: NSRange(location: 0, length: timeCandidate.utf16.count)) != nil {
                    // Merge secondLastPart and lastPart as timeString
                    timeString = "\(secondLastPart),\(lastPart)"

                    // Remove first part (message type)
                    let contentParts = firstParts[1..<(firstParts.count - 3)]
                    content = contentParts.joined(separator: ",").trimmingCharacters(in: .whitespacesAndNewlines) 
                }
            }
            else if  lastPart.count == 5 && lastPart.contains(":") {
                // 如果时间格式不正确，则使用第二部分作为时间
                timeString = lastPart
                // Remove first part (message type)
                let contentParts = firstParts[1..<(firstParts.count - 2)]
                content = contentParts.joined(separator: ",").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            else {
                timeString = ""
            }
        } 
         
        // 第二部分包含发送人信息
        let secondPart = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        if isSent {
            // 发送消息：Sent to [联系人]
            senderName = "You"
        } else {
            // 接收消息：Received from [联系人]
            if let range = secondPart.range(of: "Received from ") {
                senderName = String(secondPart[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } 
         
        
        // 解析标准化的日期和时间
        let timestamp = parseStandardDateTime(rawDateTime: timeString, language: "en")  
        Logger.debug("English parsed: Content='\(content)', Sender='\(senderName)', Time='\(timestamp)'")  
        
        return ChatMessage(
            messageType: messageType,
            content: content,
            sender: senderName,
            timestamp: timestamp,
            isFromMe: isSent
        )
    }
    
    // 解析并转换为标准化的日期和时间 YYYY-MM-DD HH:MM:SS
    private func parseStandardDateTime(rawDateTime: String, language: String) -> String {
        // 解析日期：支持英文和中文格式
        var standardDateTime = ""

        if rawDateTime.isEmpty {
            return ""
        }

        switch language {
        case "en":
            // English date format: convert "July30,at16:23" to "2025-07-30 16:23:00"
            // Assumes current year if year is not present 
            let englishDatePattern = #"(?i)(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s?(\d{1,2})"# // e.g. July30 or July 30
            let timePattern = #"at?(\d{1,2}):(\d{2})"# // e.g. at16:23 or 16:23
            let onlyTimePattern = #"^(\d{1,2}):(\d{2})$"# // e.g. 16:20

            var year = Calendar.current.component(.year, from: Date())
            var month = 1
            var day = 1
            var hour = 0
            var minute = 0

            // 首先检查是否只是时间格式（如 "16:20"）
            if let timeRegex = try? NSRegularExpression(pattern: onlyTimePattern, options: []),
               let timeMatch = timeRegex.firstMatch(in: rawDateTime, options: [], range: NSRange(location: 0, length: rawDateTime.utf16.count)) {
                // 只有时间，使用今天的日期
                let now = Date()
                let calendar = Calendar.current
                year = calendar.component(.year, from: now)
                month = calendar.component(.month, from: now)
                day = calendar.component(.day, from: now)
                
                // 解析时间
                if let hourRange = Range(timeMatch.range(at: 1), in: rawDateTime) {
                    hour = Int(rawDateTime[hourRange]) ?? 0
                }
                if let minuteRange = Range(timeMatch.range(at: 2), in: rawDateTime) {
                    minute = Int(rawDateTime[minuteRange]) ?? 0
                }
                
                Logger.debug("Parsed time-only string '\(rawDateTime)' to today's date")
            } else {
                // 解析月份和日期
                if let regex = try? NSRegularExpression(pattern: englishDatePattern, options: []),
                   let match = regex.firstMatch(in: rawDateTime, options: [], range: NSRange(location: 0, length: rawDateTime.utf16.count)) {
                    let monthStrRange = Range(match.range(at: 1), in: rawDateTime)!
                    let dayRange = Range(match.range(at: 2), in: rawDateTime)!
                    let monthStr = String(rawDateTime[monthStrRange]).lowercased()
                    let dayStr = String(rawDateTime[dayRange])
                    let monthMap = [
                        "january": 1, "jan": 1,
                        "february": 2, "feb": 2,
                        "march": 3, "mar": 3,
                        "april": 4, "apr": 4,
                        "may": 5,
                        "june": 6, "jun": 6,
                        "july": 7, "jul": 7,
                        "august": 8, "aug": 8,
                        "september": 9, "sep": 9,
                        "october": 10, "oct": 10,
                        "november": 11, "nov": 11,
                        "december": 12, "dec": 12
                    ]
                    month = monthMap[monthStr] ?? 1
                    day = Int(dayStr) ?? 1
                }

                // 解析时间
                if let regex = try? NSRegularExpression(pattern: timePattern, options: []),
                   let match = regex.firstMatch(in: rawDateTime, options: [], range: NSRange(location: 0, length: rawDateTime.utf16.count)) {
                    let hourRange = Range(match.range(at: 1), in: rawDateTime)!
                    let minuteRange = Range(match.range(at: 2), in: rawDateTime)!
                    hour = Int(rawDateTime[hourRange]) ?? 0
                    minute = Int(rawDateTime[minuteRange]) ?? 0
                }
            }

            // 构造DateComponents并转为ISO8601字符串
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            components.hour = hour
            components.minute = minute
            components.second = 0

            let calendar = Calendar(identifier: .gregorian)
            if let date = calendar.date(from: components) {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                standardDateTime = formatter.string(from: date)
            } else {
                standardDateTime = ""
            }
             
        case "zh":
            // 中文日期格式：将 "12:51"或"年8月9日12:51"或"2025年8月9日12:51" 转换为 "2025-08-09 12:51:00" 
            // Try to match full date and time first: "2025年8月9日12:51"
            let fullChineseDatePattern = #"(?:(\d{4})年)?(\d{1,2})月(\d{1,2})日(\d{1,2}):(\d{2})"#
            let onlyTimePattern = #"^(\d{1,2}):(\d{2})$"#
            var year = ""
            var month = ""
            var day = ""
            var hour = ""
            var minute = ""
            if let regex = try? NSRegularExpression(pattern: fullChineseDatePattern, options: []) {
                let range = NSRange(location: 0, length: rawDateTime.utf16.count)
                if let match = regex.firstMatch(in: rawDateTime, options: [], range: range) {
                    // Year (optional)
                    if let yearRange = Range(match.range(at: 1), in: rawDateTime), match.range(at: 1).length > 0 {
                        year = String(rawDateTime[yearRange])
                    } else {
                        // If year is missing, use current year
                        let currentYear = Calendar.current.component(.year, from: Date())
                        year = "\(currentYear)"
                    }
                    // Month and day
                    if let monthRange = Range(match.range(at: 2), in: rawDateTime) {
                        month = String(format: "%02d", Int(rawDateTime[monthRange]) ?? 1)
                    }
                    if let dayRange = Range(match.range(at: 3), in: rawDateTime) {
                        day = String(format: "%02d", Int(rawDateTime[dayRange]) ?? 1)
                    }
                    // Hour and minute
                    if let hourRange = Range(match.range(at: 4), in: rawDateTime) {
                        hour = String(format: "%02d", Int(rawDateTime[hourRange]) ?? 0)
                    }
                    if let minuteRange = Range(match.range(at: 5), in: rawDateTime) {
                        minute = String(format: "%02d", Int(rawDateTime[minuteRange]) ?? 0)
                    }
                    standardDateTime = "\(year)-\(month)-\(day) \(hour):\(minute):00"
                } else if let timeRegex = try? NSRegularExpression(pattern: onlyTimePattern, options: []) {
                    // Only time, e.g. "12:51"
                    let timeRange = NSRange(location: 0, length: rawDateTime.utf16.count)
                    if let timeMatch = timeRegex.firstMatch(in: rawDateTime, options: [], range: timeRange) {
                        // Use today's date
                        let now = Date()
                        let calendar = Calendar.current
                        year = String(calendar.component(.year, from: now))
                        month = String(format: "%02d", calendar.component(.month, from: now))
                        day = String(format: "%02d", calendar.component(.day, from: now))
                        if let hourRange = Range(timeMatch.range(at: 1), in: rawDateTime) {
                            hour = String(format: "%02d", Int(rawDateTime[hourRange]) ?? 0)
                        }
                        if let minuteRange = Range(timeMatch.range(at: 2), in: rawDateTime) {
                            minute = String(format: "%02d", Int(rawDateTime[minuteRange]) ?? 0)
                        }
                        standardDateTime = "\(year)-\(month)-\(day) \(hour):\(minute):00"
                    }
                }
            }
        default:
            // Default case for unsupported languages
            standardDateTime = ""
        } 
         
        return standardDateTime
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
                Logger.info("  - Timestamp: \(result.timestamp)")
                Logger.info("  - Is From Me: \(result.isFromMe)")
                Logger.info("  - Has Valid Content: \(result.hasValidContent)")
            } else {
                Logger.info("❌ Failed to parse")
            }
            Logger.info("---")
        }
    }
}
