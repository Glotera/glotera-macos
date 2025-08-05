-- sqlite3 desktop.db

-- chat messages table
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

CREATE INDEX IF NOT EXISTS idx_messages_session_id ON messages (session_id);
CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages (sender);
CREATE INDEX IF NOT EXISTS idx_messages_content_hash ON messages (content_hash);  
CREATE INDEX IF NOT EXISTS idx_messages_content_timestamp ON messages (content_timestamp);
CREATE INDEX IF NOT EXISTS idx_messages_chat_app ON messages (chat_app);

-- language config table
CREATE TABLE IF NOT EXISTS language_configs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    lang_name TEXT NOT NULL, -- English name of the language
    lang_native_name TEXT NOT NULL, -- Native name of the language
    lang_iso639 TEXT NOT NULL,
    lang_bcp47 TEXT NOT NULL,
    popular INTEGER NOT NULL, -- 1: popular, 2: medium, 3: rare
    triggers TEXT NOT NULL, -- comma separated list of triggers
    created_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- config table
CREATE TABLE IF NOT EXISTS configs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    config_key TEXT NOT NULL UNIQUE,
    config_value TEXT NOT NULL,
    created_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- initial data
-- insert language configs
INSERT INTO language_configs (lang_name, lang_native_name, lang_iso639, lang_bcp47, popular, triggers) VALUES
('Afrikaans', 'Afrikaans', 'af', 'af', 3, '@af,#af'),
('Amharic', 'አማርኛ', 'am', 'am', 3, '@am,#am'),
('Arabic', 'العربية', 'ar', 'ar', 1, '@ar,#ar'),
('Azerbaijani', 'Azərbaycanca', 'az', 'az', 3, '@az,#az'),
('Belarusian', 'Беларуская', 'be', 'be', 3, '@be,#be'),
('Bulgarian', 'Български', 'bg', 'bg', 3, '@bg,#bg'),
('Bengali', 'বাংলা', 'bn', 'bn', 1, '@bn,#bn'),
('Tibetan', 'བོད་སྐད་', 'bo', 'bo', 3, '@bo,#bo'),
('Bosnian', 'Bosanski', 'bs', 'bs', 3, '@bs,#bs'),
('Catalan', 'Català', 'ca', 'ca', 3, '@ca,#ca'),
('Cebuano', 'Cebuano', 'ceb', 'ceb', 3, '@ceb,#ceb'),
('Czech', 'Čeština', 'cs', 'cs', 3, '@cs,#cs'),
('Welsh', 'Cymraeg', 'cy', 'cy', 3, '@cy,#cy'),
('Danish', 'Dansk', 'da', 'da', 3, '@da,#da'),
('German', 'Deutsch', 'de', 'de', 1, '@de,#de'),
('Greek', 'Ελληνικά', 'el', 'el', 3, '@el,#el'),
('English', 'English', 'en', 'en', 1, '@en,#en'),
('Esperanto', 'Esperanto', 'eo', 'eo', 3, '@eo,#eo'),
('Spanish', 'Español', 'es', 'es', 1, '@es,#es'),
('Estonian', 'Eesti', 'et', 'et', 3, '@et,#et'),
('Basque', 'Euskara', 'eu', 'eu', 3, '@eu,#eu'),
('Persian', 'فارسی', 'fa', 'fa', 2, '@fa,#fa'),
('Finnish', 'Suomi', 'fi', 'fi', 3, '@fi,#fi'),
('Filipino', 'Filipino', 'fil', 'fil', 3, '@fil,#fil'),
('French', 'Français', 'fr', 'fr', 1, '@fr,#fr'),
('Irish', 'Gaeilge', 'ga', 'ga', 3, '@ga,#ga'),
('Galician', 'Galego', 'gl', 'gl', 3, '@gl,#gl'),
('Gujarati', 'ગુજરાતી', 'gu', 'gu', 3, '@gu,#gu'),
('Hebrew', 'עברית', 'he', 'he', 3, '@he,#he'),
('Hindi', 'हिन्दी', 'hi', 'hi', 1, '@hi,#hi'),
('Hmong', 'Hmoob', 'hmn', 'hmn', 3, '@hmn,#hmn'),
('Croatian', 'Hrvatski', 'hr', 'hr', 3, '@hr,#hr'),
('Haitian Creole', 'Kreyòl ayisyen', 'ht', 'ht', 3, '@ht,#ht'),
('Hungarian', 'Magyar', 'hu', 'hu', 3, '@hu,#hu'),
('Armenian', 'Հայերեն', 'hy', 'hy', 3, '@hy,#hy'),
('Indonesian', 'Bahasa Indonesia', 'id', 'id', 1, '@id,#id'),
('Icelandic', 'Íslenska', 'is', 'is', 3, '@is,#is'),
('Italian', 'Italiano', 'it', 'it', 2, '@it,#it'),
('Japanese', '日本語', 'ja', 'ja', 1, '@ja,#ja'),
('Javanese', 'Basa Jawa', 'jv', 'jv', 3, '@jv,#jv'),
('Georgian', 'ქართული', 'ka', 'ka', 3, '@ka,#ka'),
('Kazakh', 'Қазақ тілі', 'kk', 'kk', 3, '@kk,#kk'),
('Khmer', 'ខ្មែរ', 'km', 'km', 3, '@km,#km'),
('Kannada', 'ಕನ್ನಡ', 'kn', 'kn', 3, '@kn,#kn'),
('Korean', '한국어', 'ko', 'ko', 2, '@ko,#ko'),
('Kurdish', 'Kurdî', 'ku', 'ku', 3, '@ku,#ku'),
('Kyrgyz', 'Кыргызча', 'ky', 'ky', 3, '@ky,#ky'),
('Latin', 'Latina', 'la', 'la', 3, '@la,#la'),
('Lao', 'ລາວ', 'lo', 'lo', 3, '@lo,#lo'),
('Lithuanian', 'Lietuvių', 'lt', 'lt', 3, '@lt,#lt'),
('Latvian', 'Latviešu', 'lv', 'lv', 3, '@lv,#lv'),
('Malagasy', 'Malagasy', 'mg', 'mg', 3, '@mg,#mg'),
('Maori', 'Māori', 'mi', 'mi', 3, '@mi,#mi'),
('Macedonian', 'Македонски', 'mk', 'mk', 3, '@mk,#mk'),
('Malayalam', 'മലയാളം', 'ml', 'ml', 3, '@ml,#ml'),
('Mongolian', 'Монгол', 'mn', 'mn', 3, '@mn,#mn'),
('Marathi', 'मराठी', 'mr', 'mr', 3, '@mr,#mr'),
('Malay', 'Bahasa Melayu', 'ms', 'ms', 2, '@ms,#ms'),
('Maltese', 'Malti', 'mt', 'mt', 3, '@mt,#mt'),
('Burmese', 'မြန်မာစာ', 'my', 'my', 3, '@my,#my'),
('Nepali', 'नेपाली', 'ne', 'ne', 3, '@ne,#ne'),
('Dutch', 'Nederlands', 'nl', 'nl', 2, '@nl,#nl'),
('Norwegian', 'Norsk', 'no', 'no', 3, '@no,#no'),
('Chichewa', 'Chichewa', 'ny', 'ny', 3, '@ny,#ny'),
('Punjabi', 'ਪੰਜਾਬੀ', 'pa', 'pa', 3, '@pa,#pa'),
('Polish', 'Polski', 'pl', 'pl', 2, '@pl,#pl'),
('Pashto', 'پښتو', 'ps', 'ps', 3, '@ps,#ps'),
('Portuguese', 'Português', 'pt', 'pt', 1, '@pt,#pt'),
('Romanian', 'Română', 'ro', 'ro', 2, '@ro,#ro'),
('Russian', 'Русский', 'ru', 'ru', 1, '@ru,#ru'),
('Kinyarwanda', 'Kinyarwanda', 'rw', 'rw', 3, '@rw,#rw'),
('Sindhi', 'سنڌي', 'sd', 'sd', 3, '@sd,#sd'),
('Sinhala', 'සිංහල', 'si', 'si', 3, '@si,#si'),
('Slovak', 'Slovenčina', 'sk', 'sk', 3, '@sk,#sk'),
('Slovenian', 'Slovenščina', 'sl', 'sl', 3, '@sl,#sl'),
('Samoan', 'Gagana Samoa', 'sm', 'sm', 3, '@sm,#sm'),
('Shona', 'ChiShona', 'sn', 'sn', 3, '@sn,#sn'),
('Somali', 'Soomaali', 'so', 'so', 3, '@so,#so'),
('Albanian', 'Shqip', 'sq', 'sq', 3, '@sq,#sq'),
('Serbian', 'Српски', 'sr', 'sr', 3, '@sr,#sr'),
('Sesotho', 'Sesotho', 'st', 'st', 3, '@st,#st'),
('Sundanese', 'Basa Sunda', 'su', 'su', 3, '@su,#su'),
('Swedish', 'Svenska', 'sv', 'sv', 3, '@sv,#sv'),
('Swahili', 'Kiswahili', 'sw', 'sw', 3, '@sw,#sw'),
('Tamil', 'தமிழ்', 'ta', 'ta', 2, '@ta,#ta'),
('Telugu', 'తెలుగు', 'te', 'te', 3, '@te,#te'),
('Tajik', 'Тоҷикӣ', 'tg', 'tg', 3, '@tg,#tg'),
('Thai', 'ไทย', 'th', 'th', 2, '@th,#th'),
('Turkmen', 'Türkmen', 'tk', 'tk', 3, '@tk,#tk'),
('Tagalog', 'Tagalog', 'tl', 'tl', 3, '@tl,#tl'),
('Turkish', 'Türkçe', 'tr', 'tr', 2, '@tr,#tr'),
('Tatar', 'Татарча', 'tt', 'tt', 3, '@tt,#tt'),
('Ukrainian', 'Українська', 'uk', 'uk', 2, '@uk,#uk'),
('Urdu', 'اردو', 'ur', 'ur', 2, '@ur,#ur'),
('Uzbek', 'Oʻzbek', 'uz', 'uz', 3, '@uz,#uz'),
('Vietnamese', 'Tiếng Việt', 'vi', 'vi', 2, '@vi,#vi'),
('Xhosa', 'isiXhosa', 'xh', 'xh', 3, '@xh,#xh'),
('Yiddish', 'ייִדיש', 'yi', 'yi', 3, '@yi,#yi'),
('Yoruba', 'Yorùbá', 'yo', 'yo', 3, '@yo,#yo'),
('Chinese (Simplified)', '简体中文', 'zh', 'zh-Hans,zh-CN', 1, '@zh,#zh'),
('Chinese (Traditional)', '繁體中文', 'zh-TW', 'zh-Hant,zh-TW', 3, '@zh-TW,#zh-TW'),
('Zulu', 'isiZulu', 'zu', 'zu', 3, '@zu,#zu');
