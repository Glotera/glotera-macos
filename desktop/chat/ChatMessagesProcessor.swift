import Cocoa

protocol ChatMessagesProcessor {
    static func getCurrentChatSessionId(activeApp: NSRunningApplication) -> String?

    static func extractMessages(from app: NSRunningApplication, filterAfterTimestamp: Date) -> [ChatMessage]
}
