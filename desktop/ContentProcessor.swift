//
//  ContentProcessor.swift
//  Manages content processing, such as extracting user input from mail content, etc.
//  Created by Claude Code on 2025-07-20.
//  Copyright © 2025 Glotera AI. All rights reserved.
//

import Foundation

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
        var cleaned = content.replacingOccurrences(of: "\u{200B}", with: "")
        if cleaned.count != content.count {
            Logger.info("Pre-processed content: Removed invisible characters.")
        }
        
        // 检查当前应用是否为Discord或其他聊天应用
        let isDiscordOrChat = AppDetectionManager.shared.isDiscordOrChatApp()
        
        // 对于Discord等聊天应用，使用更保守的清理策略
        if isDiscordOrChat {
            Logger.info("Detected Discord/Chat app - using conservative preprocessing")
            // 只进行基本的空格合并，不移除任何文本内容
            cleaned = cleaned.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned
        }
        
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
     
}