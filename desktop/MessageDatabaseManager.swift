import Foundation
import SQLite3
import CryptoKit

/// Manager for SQLite database operations for chat messages
class MessageDatabaseManager {
    static let shared = MessageDatabaseManager()
    
    private var db: OpaquePointer?
    private let dbPath: String
    
    private init() {
        // Create ~/Library/Glotera directory if it doesn't exist
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let libraryPath = homeDirectory.appendingPathComponent("Library")
        let gloteraPath = libraryPath.appendingPathComponent("Glotera")
        
        try? FileManager.default.createDirectory(at: gloteraPath, 
                                               withIntermediateDirectories: true, 
                                               attributes: nil)
        
        dbPath = gloteraPath.appendingPathComponent("desktop.db").path
        Logger.info("Database path: \(dbPath)")
        
        openDatabase()
        createTable()
    }
    
    deinit {
        closeDatabase()
    }
    
    /// Open database connection
    private func openDatabase() {
        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            Logger.info("Successfully opened database")
        } else {
            Logger.error("Unable to open database")
        }
    }
    
    /// Close database connection
    private func closeDatabase() {
        if sqlite3_close(db) == SQLITE_OK {
            Logger.info("Successfully closed database")
        } else {
            Logger.error("Unable to close database")
        }
    }
    
    /// Create messages table if it doesn't exist
    private func createTable() {
        let createTableSQL = """
            CREATE TABLE IF NOT EXISTS messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sender TEXT NOT NULL,
                content TEXT NOT NULL,
                content_hash TEXT NOT NULL,
                content_language TEXT NOT NULL,
                content_translation TEXT NOT NULL,
                content_translation_language TEXT NOT NULL,
                content_timestamp TIMESTAMP NOT NULL,
                chat_app TEXT NOT NULL,
                session_id TEXT NOT NULL,
                created_time TIMESTAMP NOT NULL,
                updated_time TIMESTAMP NOT NULL
            );
            
            CREATE INDEX IF NOT EXISTS idx_content_hash ON messages(content_hash);
            CREATE INDEX IF NOT EXISTS idx_chat_app ON messages(chat_app);
            CREATE INDEX IF NOT EXISTS idx_session_id ON messages(session_id);
            CREATE INDEX IF NOT EXISTS idx_content_timestamp ON messages(content_timestamp);
        """
        
        let result = sqlite3_exec(db, createTableSQL, nil, nil, nil)
        if result == SQLITE_OK {
            Logger.info("Messages table created successfully")
        } else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            Logger.error("Failed to create messages table: \(errorMsg) (code: \(result))")
        }
        
        // Check if session_id column exists, if not add it
//        addSessionIdColumnIfNeeded()
    }
    
    /// Add session_id column if it doesn't exist (for database migration)
//    private func addSessionIdColumnIfNeeded() {
//        // Check if session_id column exists
//        let checkColumnSQL = "PRAGMA table_info(messages);"
//        var statement: OpaquePointer?
//        var hasSessionIdColumn = false
//        
//        guard sqlite3_prepare_v2(db, checkColumnSQL, -1, &statement, nil) == SQLITE_OK else {
//            Logger.error("Failed to check table schema")
//            return
//        }
//        
//        defer { sqlite3_finalize(statement) }
//        
//        while sqlite3_step(statement) == SQLITE_ROW {
//            let columnName = String(cString: sqlite3_column_text(statement, 1))
//            if columnName == "session_id" {
//                hasSessionIdColumn = true
//                break
//            }
//        }
//        
//        if !hasSessionIdColumn {
//            Logger.info("Adding session_id column to messages table...")
//            let alterTableSQL = "ALTER TABLE messages ADD COLUMN session_id TEXT NOT NULL DEFAULT 'default';"
//            let result = sqlite3_exec(db, alterTableSQL, nil, nil, nil)
//            if result == SQLITE_OK {
//                Logger.info("Successfully added session_id column")
//            } else {
//                let errorMsg = String(cString: sqlite3_errmsg(db))
//                Logger.error("Failed to add session_id column: \(errorMsg)")
//            }
//        } else {
//            Logger.info("session_id column already exists")
//        }
//    }
    
    /// Calculate SHA256 hash of content for deduplication
    func calculateContentHash(_ content: String) -> String {
        let data = Data(content.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Check if message already exists in database
    func messageExists(contentHash: String) -> Bool {
        let querySQL = "SELECT COUNT(*) FROM messages WHERE content_hash = ?;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK else {
            Logger.error("Failed to prepare message exists query")
            return false
        }
        
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, (contentHash as NSString).utf8String, -1, nil)
        
        if sqlite3_step(statement) == SQLITE_ROW {
            let count = sqlite3_column_int(statement, 0)
            return count > 0
        }
        
        return false
    }
    
    /// Get existing message by content hash
    func getMessage(byContentHash contentHash: String) -> MessageRecord? {
        let querySQL = """
            SELECT id, sender, content, content_hash, content_language, 
                   content_translation, content_translation_language, 
                   content_timestamp, chat_app, created_time, updated_time
            FROM messages WHERE content_hash = ?;
        """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK else {
            Logger.error("Failed to prepare get message query")
            return nil
        }
        
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, (contentHash as NSString).utf8String, -1, nil)
        
        if sqlite3_step(statement) == SQLITE_ROW {
            return extractMessageRecord(from: statement)
        }
        
        return nil
    }
    
    /// Insert new message into database
    func insertMessage(_ message: MessageRecord) -> Bool {
        let insertSQL = """
            INSERT INTO messages (sender, content, content_hash, content_language,
                                content_translation, content_translation_language,
                                content_timestamp, chat_app, session_id, created_time, updated_time)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
            Logger.error("Failed to prepare insert statement")
            return false
        }
        
        defer { sqlite3_finalize(statement) }
        
        // Bind values using proper Swift-to-SQLite method with UTF-8 encoding
        sqlite3_bind_text(statement, 1, (message.sender as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (message.content as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (message.contentHash as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 4, (message.contentLanguage as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 5, (message.contentTranslation as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 6, (message.contentTranslationLanguage as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 7, (message.contentTimestamp.ISO8601Format() as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 8, (message.chatApp as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 9, (message.sessionId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 10, (message.createdTime.ISO8601Format() as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 11, (message.updatedTime.ISO8601Format() as NSString).utf8String, -1, nil)
        
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE {
            Logger.info("Message inserted successfully: \(message.content.prefix(50))...")
            Logger.debug("Inserted sender: '\(message.sender)' (length: \(message.sender.count))")
            Logger.debug("Inserted sessionId: '\(message.sessionId)' (length: \(message.sessionId.count))")
            return true
        } else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            Logger.error("Failed to insert message: \(errorMsg) (code: \(result))")
            Logger.error("Message content: \(message.content)")
            Logger.error("Message sender: \(message.sender)")
            Logger.error("Message sessionId: \(message.sessionId)")
            return false
        }
    }
    
    /// Get recent messages for a chat app and session
    func getRecentMessages(forApp appName: String, sessionId: String, limit: Int = 100) -> [MessageRecord] {
        let querySQL = """
            SELECT id, sender, content, content_hash, content_language,
                   content_translation, content_translation_language,
                   content_timestamp, chat_app, session_id, created_time, updated_time
            FROM messages 
            WHERE chat_app = ? AND session_id = ?
            ORDER BY content_timestamp DESC
            LIMIT ?;
        """
        
        var statement: OpaquePointer?
        var messages: [MessageRecord] = []
        
        guard sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK else {
            Logger.error("Failed to prepare recent messages query")
            return messages
        }
        
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, (appName as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (sessionId as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 3, Int32(limit))
        
        while sqlite3_step(statement) == SQLITE_ROW {
            if let message = extractMessageRecord(from: statement) {
                messages.append(message)
            }
        }
        
        // Reverse to get chronological order (oldest first)
        return messages.reversed()
    }
    
    /// Get the timestamp of the last message for a specific session
    func getLastMessageTimestamp(forApp appName: String, sessionId: String) -> Date? {
        let querySQL = """
            SELECT content_timestamp
            FROM messages 
            WHERE chat_app = ? AND session_id = ?
            ORDER BY content_timestamp DESC
            LIMIT 1;
        """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK else {
            Logger.error("Failed to prepare last message timestamp query")
            return nil
        }
        
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, (appName as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (sessionId as NSString).utf8String, -1, nil)
        
        if sqlite3_step(statement) == SQLITE_ROW {
            let timestampStr = String(cString: sqlite3_column_text(statement, 0))
            let dateFormatter = ISO8601DateFormatter()
            return dateFormatter.date(from: timestampStr)
        }
        
        return nil
    }
    
    /// Test database functionality
    func testDatabase() {
        Logger.info("Testing database functionality...")
        
        // Test insertion
        let testMessage = MessageRecord(
            sender: "Test Sender",
            content: "This is a test message",
            contentHash: calculateContentHash("This is a test message"),
            contentLanguage: "en",
            contentTranslation: "这是一个测试消息",
            contentTranslationLanguage: "zh",
            contentTimestamp: Date(),
            chatApp: "WhatsApp",
            sessionId: "test_session"
        )
        
        let insertResult = insertMessage(testMessage)
        Logger.info("Test message insertion result: \(insertResult)")
        
        // Test retrieval
        let messages = getRecentMessages(forApp: "WhatsApp", sessionId: "test_session", limit: 5)
        Logger.info("Retrieved \(messages.count) messages from database")
        
        for message in messages {
            Logger.info("Message: \(message.sender) - \(message.content) -> \(message.contentTranslation)")
        }
    }
    
    /// Clear all messages (for debugging)
    func clearAllMessages() {
        let deleteSQL = "DELETE FROM messages;"
        let result = sqlite3_exec(db, deleteSQL, nil, nil, nil)
        if result == SQLITE_OK {
            Logger.info("All messages cleared from database")
        } else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            Logger.error("Failed to clear messages: \(errorMsg)")
        }
    }
    
    /// Extract MessageRecord from SQLite statement
    private func extractMessageRecord(from statement: OpaquePointer?) -> MessageRecord? {
        guard let statement = statement else { return nil }
        
        let id = Int(sqlite3_column_int(statement, 0))
        
        guard let sender = sqlite3_column_text(statement, 1),
              let content = sqlite3_column_text(statement, 2),
              let contentHash = sqlite3_column_text(statement, 3),
              let contentLanguage = sqlite3_column_text(statement, 4),
              let contentTranslation = sqlite3_column_text(statement, 5),
              let contentTranslationLanguage = sqlite3_column_text(statement, 6),
              let contentTimestampStr = sqlite3_column_text(statement, 7),
              let chatApp = sqlite3_column_text(statement, 8),
              let sessionId = sqlite3_column_text(statement, 9),
              let createdTimeStr = sqlite3_column_text(statement, 10),
              let updatedTimeStr = sqlite3_column_text(statement, 11) else {
            return nil
        }
        
        let dateFormatter = ISO8601DateFormatter()
        
        return MessageRecord(
            id: id,
            sender: String(cString: sender),
            content: String(cString: content),
            contentHash: String(cString: contentHash),
            contentLanguage: String(cString: contentLanguage),
            contentTranslation: String(cString: contentTranslation),
            contentTranslationLanguage: String(cString: contentTranslationLanguage),
            contentTimestamp: dateFormatter.date(from: String(cString: contentTimestampStr)) ?? Date(),
            chatApp: String(cString: chatApp),
            sessionId: String(cString: sessionId),
            createdTime: dateFormatter.date(from: String(cString: createdTimeStr)) ?? Date(),
            updatedTime: dateFormatter.date(from: String(cString: updatedTimeStr)) ?? Date()
        )
    }
}

/// Message record structure matching database schema
struct MessageRecord {
    let id: Int?
    let sender: String
    let content: String
    let contentHash: String
    let contentLanguage: String
    let contentTranslation: String
    let contentTranslationLanguage: String
    let contentTimestamp: Date
    let chatApp: String
    let sessionId: String
    let createdTime: Date
    let updatedTime: Date
    
    init(id: Int? = nil,
         sender: String,
         content: String,
         contentHash: String,
         contentLanguage: String,
         contentTranslation: String,
         contentTranslationLanguage: String,
         contentTimestamp: Date,
         chatApp: String,
         sessionId: String,
         createdTime: Date = Date(),
         updatedTime: Date = Date()) {
        self.id = id
        self.sender = sender
        self.content = content
        self.contentHash = contentHash
        self.contentLanguage = contentLanguage
        self.contentTranslation = contentTranslation
        self.contentTranslationLanguage = contentTranslationLanguage
        self.contentTimestamp = contentTimestamp
        self.chatApp = chatApp
        self.sessionId = sessionId
        self.createdTime = createdTime
        self.updatedTime = updatedTime
    }
    
}
