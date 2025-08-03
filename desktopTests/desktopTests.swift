//
//  desktopTests.swift
//  desktopTests
//
//  Created by Bryanzh on 2025/6/5.
//

import Testing
@testable import Glotera

struct desktopTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }
    
    @Test func testChatMessageParsing() async throws {
        // Test case 1: Sent message with full details (based on actual WhatsApp format)
        let sentMessageText = "Your message, 基本上把bug修的差不多了, July30,at16:23, Sent to Princeton, Red"
        if let result = ContentProcessor.shared.parseWhatsAppMessage(sentMessageText) {
            #expect(result.messageType == "Your message")
            #expect(result.content == "基本上把bug修的差不多了")
            #expect(result.sender == "You")  // 修复：发送消息的sender应该是"You"
            #expect(result.timestamp == "July 30, 16:23")  // 修复：标准化的时间戳格式
            #expect(result.date == "July 30")  // 修复：标准化的日期格式
            #expect(result.time == "16:23")  // 修复：标准化的时间格式
            #expect(result.isFromMe == true)
            #expect(result.hasValidContent == true)
            #expect(result.senderDisplayName == "You")  // 修复：发送消息的senderDisplayName应该是"You"
        } else {
            #expect(false, "Failed to parse sent message")
        }
        
        // Test case 2: Received message with full details (based on actual WhatsApp format)
        let receivedMessageText = "message, 好，我晚上也测测, July30,at16:23, Received from Princeton"
        if let result = ContentProcessor.shared.parseWhatsAppMessage(receivedMessageText) {
            #expect(result.messageType == "message")
            #expect(result.content == "好，我晚上也测测")
            #expect(result.sender == "Princeton")
            #expect(result.timestamp == "July 30, 16:23")  // 修复：标准化的时间戳格式
            #expect(result.date == "July 30")  // 修复：标准化的日期格式
            #expect(result.time == "16:23")  // 修复：标准化的时间格式
            #expect(result.isFromMe == false)
            #expect(result.hasValidContent == true)
            #expect(result.senderDisplayName == "Princeton")
        } else {
            #expect(false, "Failed to parse received message")
        }
        
        // Test case 3: Message with commas in content
        let messageWithComma = "Your message, Hello, world, how are you?, July22,at08:38, Sent to John Warhol, Red"
        if let result = ContentProcessor.shared.parseWhatsAppMessage(messageWithComma) {
            #expect(result.messageType == "Your message")
            #expect(result.content == "Hello, world, how are you?")
            #expect(result.sender == "You")  // 修复：发送消息的sender应该是"You"
            #expect(result.timestamp == "July 22, 08:38")  // 修复：标准化的时间戳格式
            #expect(result.date == "July 22")  // 修复：标准化的日期格式
            #expect(result.time == "08:38")  // 修复：标准化的时间格式
            #expect(result.isFromMe == true)
        } else {
            #expect(false, "Failed to parse message with comma in content")
        }
        
        // Test case 4: Message with invisible characters (U+200E)
        let invisibleCharMessageText = "message, 测试消息, July30,at16:23, Received from Princeton"
        if let result = ContentProcessor.shared.parseWhatsAppMessage(invisibleCharMessageText) {
            #expect(result.messageType == "message")
            #expect(result.content == "测试消息")
            #expect(result.sender == "Princeton")
            #expect(result.isFromMe == false)
        } else {
            #expect(false, "Failed to parse message with invisible characters")
        }
        
        // Test case 5: Invalid message (should return nil)
        let invalidMessage = "Invalid format"
        let result = ContentProcessor.shared.parseWhatsAppMessage(invalidMessage)
        #expect(result == nil, "Should return nil for invalid message format")
    }
    
    @Test func testChatMessageConvenienceMethods() async throws {
        let message = ChatMessage(
            messageType: "Your message",
            content: "Test content",
            sender: "Test Sender",
            timestamp: "July22, at08:38",
            isFromMe: true,
            date: "July22",
            time: "at08:38"
        )
        
        #expect(message.hasValidContent == true)
        #expect(message.senderDisplayName == "Test Sender")
        #expect(message.description.contains("Type: Your message"))
        #expect(message.description.contains("Content: Test content"))
        #expect(message.description.contains("Sender: Test Sender"))
        #expect(message.description.contains("Time: July22, at08:38"))
        #expect(message.description.contains("IsFromMe: true"))
        
        // Test with empty sender (sent message)
        let sentMessage = ChatMessage(
            messageType: "Your message",
            content: "Test content",
            sender: "",
            timestamp: "",
            isFromMe: true
        )
        #expect(sentMessage.senderDisplayName == "You")
        
        // Test with empty sender (received message)
        let receivedMessage = ChatMessage(
            messageType: "Received message",
            content: "Test content",
            sender: "",
            timestamp: "",
            isFromMe: false
        )
        #expect(receivedMessage.senderDisplayName == "Unknown")
    }

}
