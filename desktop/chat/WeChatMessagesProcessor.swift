import Cocoa

class WeChatMessagesProcessor: ChatMessagesProcessor {
    static func getCurrentChatSessionId(activeApp: NSRunningApplication) -> String? {
        return nil
    }

    static func extractMessages(from app: NSRunningApplication, filterAfterTimestamp: Date) -> [ChatMessage] {
        return []
    }
}
