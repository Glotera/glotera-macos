-- sqlite3 desktop.db

CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL, -- default is chat person's name
    sender TEXT NOT NULL,
    content TEXT NOT NULL,
    content_hash TEXT NOT NULL,
    content_language TEXT NOT NULL,
    content_translation TEXT NOT NULL,
    content_translation_language TEXT NOT NULL,
    content_timestamp TIMESTAMP NOT NULL, -- received or sent time
    chat_app TEXT NOT NULL, -- whatsapp, telegram, etc.
    created_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

