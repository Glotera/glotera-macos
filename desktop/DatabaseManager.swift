import Foundation
import SQLite3
import CryptoKit

/// Manager for SQLite database operations for chat messages
class DatabaseManager {
    static let shared = DatabaseManager()
    
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
        initializeDatabase()
    }
    
    deinit {
        closeDatabase()
    }
    
    /// Get the database connection for use by other managers
    func getDatabase() -> OpaquePointer? {
        return db
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
    
    /// Initialize database from desktop.sql file
    private func initializeDatabase() {
        guard let sqlFileURL = Bundle.main.url(forResource: "desktop", withExtension: "sql") else {
            Logger.error("desktop.sql file not found in bundle")
            fallbackCreateTables()
            return
        }
        
        do {
            let sqlContent = try String(contentsOf: sqlFileURL, encoding: .utf8)
            Logger.info("Loaded desktop.sql from bundle")
            
            // Split SQL content into statements
            let statements = parseSQLStatements(from: sqlContent)
            
            // Execute table creation and index statements
            let tableStatements = statements.filter { statement in
                let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                return trimmed.hasPrefix("CREATE TABLE") || trimmed.hasPrefix("CREATE INDEX")
            }
            
            for statement in tableStatements {
                let result = sqlite3_exec(db, statement, nil, nil, nil)
                if result == SQLITE_OK {
                    let tableName = extractTableName(from: statement)
                    Logger.info("Successfully created table/index: \(tableName)")
                } else {
                    let errorMsg = String(cString: sqlite3_errmsg(db))
                    Logger.error("Failed to execute statement: \(errorMsg) (code: \(result))")
                    Logger.error("Statement: \(statement.prefix(100))...")
                }
            }
            
            // Initialize language_configs table only if it's empty
            initializeLanguageConfigsIfNeeded(from: statements)
            
        } catch {
            Logger.error("Failed to read desktop.sql: \(error.localizedDescription)")
            fallbackCreateTables()
        }
    }
    
    /// Parse SQL content into individual statements
    private func parseSQLStatements(from content: String) -> [String] {
        var statements: [String] = []
        var currentStatement = ""
        
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip comments
            if trimmedLine.hasPrefix("--") {
                continue
            }
            
            // Skip empty lines
            if trimmedLine.isEmpty {
                continue
            }
            
            currentStatement += line + "\n"
            
            // Check if statement is complete (ends with semicolon)
            if trimmedLine.hasSuffix(";") {
                statements.append(currentStatement.trimmingCharacters(in: .whitespacesAndNewlines))
                currentStatement = ""
            }
        }
        
        // Add remaining statement if any
        if !currentStatement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            statements.append(currentStatement.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        
        return statements
    }
    
    /// Extract table name from CREATE TABLE statement
    private func extractTableName(from statement: String) -> String {
        let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.uppercased().hasPrefix("CREATE TABLE") {
            let components = trimmed.components(separatedBy: .whitespacesAndNewlines)
            for (index, component) in components.enumerated() {
                if component.uppercased() == "TABLE" && index + 1 < components.count {
                    let tableName = components[index + 1].replacingOccurrences(of: "IF", with: "").replacingOccurrences(of: "NOT", with: "").replacingOccurrences(of: "EXISTS", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    return tableName
                }
            }
        } else if trimmed.uppercased().hasPrefix("CREATE INDEX") {
            let components = trimmed.components(separatedBy: .whitespacesAndNewlines)
            for (index, component) in components.enumerated() {
                if component.uppercased() == "INDEX" && index + 1 < components.count {
                    let indexName = components[index + 1].replacingOccurrences(of: "IF", with: "").replacingOccurrences(of: "NOT", with: "").replacingOccurrences(of: "EXISTS", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    return indexName
                }
            }
        }
        return "unknown"
    }
    
    /// Initialize language_configs table with data if it's empty
    private func initializeLanguageConfigsIfNeeded(from statements: [String]) {
        // Check if language_configs table has any data
        let countSQL = "SELECT COUNT(*) FROM language_configs;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, countSQL, -1, &statement, nil) == SQLITE_OK else {
            Logger.error("Failed to prepare count query for language_configs")
            return
        }
        
        defer { sqlite3_finalize(statement) }
        
        var count = 0
        if sqlite3_step(statement) == SQLITE_ROW {
            count = Int(sqlite3_column_int(statement, 0))
        }
        
        if count == 0 {
            Logger.info("language_configs table is empty, initializing with data from desktop.sql")
            
            // Find and execute INSERT statements for language_configs
            let insertStatements = statements.filter { statement in
                let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                return trimmed.hasPrefix("INSERT INTO LANGUAGE_CONFIGS")
            }
            
            for insertStatement in insertStatements {
                let result = sqlite3_exec(db, insertStatement, nil, nil, nil)
                if result == SQLITE_OK {
                    Logger.info("Successfully inserted language config data")
                } else {
                    let errorMsg = String(cString: sqlite3_errmsg(db))
                    Logger.error("Failed to insert language config data: \(errorMsg)")
                    Logger.error("Statement: \(insertStatement.prefix(200))...")
                }
            }
        } else {
            Logger.info("language_configs table already contains \(count) records, skipping initialization")
        }
    }
    
    /// Fallback table creation if desktop.sql is not available
    private func fallbackCreateTables() {
        Logger.info("Using fallback table creation")
        
        let createTablesSQL = """
            CREATE TABLE IF NOT EXISTS messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                sender TEXT NOT NULL,
                content TEXT NOT NULL,
                content_hash TEXT NOT NULL,
                content_language TEXT NOT NULL,
                content_translation TEXT NOT NULL,
                content_translation_language TEXT NOT NULL,
                content_timestamp TIMESTAMP NOT NULL,
                chat_app TEXT NOT NULL,
                created_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
            
            CREATE INDEX IF NOT EXISTS idx_messages_session_id ON messages (session_id);
            CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages (sender);
            CREATE INDEX IF NOT EXISTS idx_messages_content_hash ON messages (content_hash);
            CREATE INDEX IF NOT EXISTS idx_messages_content_timestamp ON messages (content_timestamp);
            CREATE INDEX IF NOT EXISTS idx_messages_chat_app ON messages (chat_app);
            
            CREATE TABLE IF NOT EXISTS language_configs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                lang_name TEXT NOT NULL,
                lang_native_name TEXT NOT NULL,
                lang_iso639 TEXT NOT NULL,
                lang_bcp47 TEXT NOT NULL,
                popular INTEGER NOT NULL,
                triggers TEXT NOT NULL,
                created_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
            
            CREATE TABLE IF NOT EXISTS configs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                config_key TEXT NOT NULL,
                config_value TEXT NOT NULL,
                created_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
        """
        
        let result = sqlite3_exec(db, createTablesSQL, nil, nil, nil)
        if result == SQLITE_OK {
            Logger.info("Fallback tables created successfully")
        } else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            Logger.error("Failed to create fallback tables: \(errorMsg) (code: \(result))")
        }
    }
    
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
    
    /// Get the language of the most recent received message (not from user) in a session
    func getLastReceivedMessageLanguage(forApp appName: String, sessionId: String) -> String? {
        let querySQL = """
            SELECT content_language
            FROM messages 
            WHERE chat_app = ? AND session_id = ? AND sender != 'You'
            ORDER BY content_timestamp DESC
            LIMIT 1;
        """
        
        Logger.debug("🔍 Executing SQL query for getLastReceivedMessageLanguage:")
        Logger.debug("📄 SQL: \(querySQL.replacingOccurrences(of: "\n", with: " "))")
        Logger.debug("📋 Parameters: appName='\(appName)', sessionId='\(sessionId)'")
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK else {
            Logger.error("Failed to prepare last received message language query")
            return nil
        }
        
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, (appName as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (sessionId as NSString).utf8String, -1, nil)
        
        if sqlite3_step(statement) == SQLITE_ROW {
            let languageStr = String(cString: sqlite3_column_text(statement, 0))
            Logger.info("✅ Found last received message language: '\(languageStr)' for session: '\(sessionId)'")
            return languageStr
        }
        
        Logger.warn("❌ No received messages found for appName: '\(appName)', sessionId: '\(sessionId)'")
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
