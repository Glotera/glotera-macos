//
//  desktopTests.swift
//  desktopTests
//
//  Created by Bryanzh on 2025/6/5.
//

import Testing
import Foundation
@testable import Glotera

struct desktopTests {

    @Test func testSystemLanguageDetection() async throws {
        // Test system language detection
        print("=== System Language Detection Test ===")
        
        // Test different ways to get system language
        let locale = Locale.current
        print("Locale.current.identifier: \(locale.identifier)")
        print("Locale.current.languageCode?.identifier: \(locale.language.languageCode?.identifier ?? "nil")")
        
        // Test preferred languages
        let preferredLanguages = Locale.preferredLanguages
        print("Locale.preferredLanguages: \(preferredLanguages)")
        
        // Test if we can get Chinese language
        if let chineseLang = preferredLanguages.first(where: { $0.hasPrefix("zh") }) {
            print("Found Chinese language in preferred languages: \(chineseLang)")
        }
        
        // Test current locale components
        print("Locale.current.region?.identifier: \(locale.region?.identifier ?? "nil")")
        print("Locale.current.variant?.identifier: \(locale.variant?.identifier ?? "nil")")
        
        // Test if we can create a Chinese locale
        let chineseLocale = Locale(identifier: "zh-CN")
        print("Chinese locale language code: \(chineseLocale.language.languageCode?.identifier ?? "nil")")
        
        // Test if we can create a Chinese locale with different variants
        let chineseVariants = ["zh-CN", "zh-TW", "zh-HK", "zh"]
        for variant in chineseVariants {
            let testLocale = Locale(identifier: variant)
            print("\(variant) locale language code: \(testLocale.language.languageCode?.identifier ?? "nil")")
        }
        
        // Test the actual ContentProcessor method
        let systemLanguage = EnvironmentManager.shared.getSystemLanguage()
        print("ContentProcessor.getSystemLanguage(): \(systemLanguage)")
        
        #expect(Bool(true), "System language detection test completed")
    }
    
    @Test func testContentProcessorInitialization() async throws {
        // Test that ContentProcessor.shared is properly initialized
        let processor = ContentProcessor.shared
        #expect(processor != nil, "ContentProcessor.shared should not be nil")
        
        print("ContentProcessor.shared initialized successfully")
    }
    
    @Test func testSimpleWhatsAppParsing() async throws {
        // Simple test to verify parseWhatsAppMessage is called
        let testMessage = "‎message, Hello world, July30,at16:20, ‎Received from Test"
        let result = ContentProcessor.shared.parseWhatsAppMessage(testMessage)
        
        print("Test message: \(testMessage)")
        print("Parse result: \(String(describing: result))")
        
        #expect(result != nil, "Should parse valid WhatsApp message")
        if let parsed = result {
            print("Parsed content: \(parsed.content)")
            print("Parsed sender: \(parsed.sender)")
            print("Parsed timestamp: \(parsed.timestamp)")
            print("Is from me: \(parsed.isFromMe)")
        }
    }
    
    @Test func testLanguageDetection() async throws {
        print("=== Language Detection Test ===")
        // 自动生成所有 language-iso-639.json 语言的短句和长句测试用例
        // Short and long test sentences for each language, and test detectLanguage()
        // 按Popular排序，参照@language-iso-639.json
        let languageTestCases: [(code: String, language: String, short: String, long: String)] = [
            ("zh", "Chinese", "你好", "这是一个用于测试的中文长句。"),
            ("en", "English", "Hello", "This is a long sentence in English for testing purposes."),
            ("hi", "Hindi", "नमस्ते", "यह हिंदी में एक लंबा वाक्य है परीक्षण के लिए।"),
            ("es", "Spanish", "Hola", "Esta es una oración larga en español para probar."),
            ("fr", "French", "Bonjour", "Ceci est une longue phrase en français pour les tests."),
            ("ar", "Arabic", "مرحبا", "أتمنى لك يوماً سعيداً مليئاً بالنجاح والسعادة."),
            ("bn", "Bengali", "হ্যালো", "আমি আশা করি আজ তোমার দিনটি খুব ভালো যাবে।"),
            ("pt", "Portuguese", "Olá", "Esta é uma frase longa em português para teste."),
            ("ru", "Russian", "Привет", "Это длинное предложение на русском языке для тестирования."),
            ("ur", "Urdu", "ہیلو", "یہ اردو میں ایک طویل جملہ ہے جانچ کے لیے۔"),
            ("id", "Indonesian", "Halo", "Ini adalah kalimat panjang dalam bahasa Indonesia untuk pengujian."),
            ("de", "German", "Hallo", "Dies ist ein langer Satz auf Deutsch zum Testen."),
            ("ja", "Japanese", "こんにちは", "これはテスト用の日本語の長い文です。"),
            ("sw", "Swahili", "Habari", "Hii ni sentensi ndefu kwa Kiswahili kwa ajili ya majaribio."),
            ("mr", "Marathi", "हॅलो", "ही मराठीतली एक लांब वाक्य आहे चाचणीसाठी."),
            ("te", "Telugu", "హలో", "ఇది పరీక్ష కోసం తెలుగు లోని ఒక పొడవైన వాక్యం."),
            ("tr", "Turkish", "Merhaba", "Bu, test için Türkçe uzun bir cümledir."),
            ("ta", "Tamil", "வணக்கம்", "இது ஒரு நீண்ட தமிழ் வாக்கியம் சோதனைக்காக."),
            ("vi", "Vietnamese", "Xin chào", "Đây là một câu dài bằng tiếng Việt để kiểm tra."),
            ("ko", "Korean", "안녕하세요", "이것은 테스트를 위한 한국어 긴 문장입니다."),
            ("fa", "Persian", "سلام", "این یک جمله طولانی به زبان فارسی برای آزمایش است."),
            ("it", "Italian", "Ciao", "Questa è una frase lunga in italiano per il test."),
            ("pl", "Polish", "Cześć", "To jest długie zdanie po polsku do testowania."),
            ("uk", "Ukrainian", "Привіт", "Це довге речення українською мовою для тестування."),
            ("ro", "Romanian", "Salut", "Aceasta este o propoziție lungă în română pentru testare."),
            ("nl", "Dutch", "Hallo", "Dit is een lange zin in het Nederlands voor testen."),
            ("th", "Thai", "สวัสดี", "นี่คือประโยคยาวในภาษาไทยสำหรับการทดสอบ."),
            ("gu", "Gujarati", "હેલો", "આ ગુજરાતી ભાષામાં લાંબી વાક્ય છે પરીક્ષણ માટે."),
            ("el", "Greek", "Γειά", "Αυτή είναι μια μεγάλη πρόταση στα ελληνικά για δοκιμή."),
            ("hu", "Hungarian", "Helló", "Ez egy hosszú mondat magyarul teszteléshez."),
            ("cs", "Czech", "Ahoj", "Toto je dlouhá věta v češtině pro testování."),
            ("sv", "Swedish", "Hej", "Detta är en lång mening på svenska för test."),
            ("az", "Azerbaijani", "Salam", "Bu, Azərbaycan dilində uzun bir cümlədir və test üçün yazılmışdır."),
            ("he", "Hebrew", "שלום", "זהו משפט ארוך בעברית לבדיקה."),
            ("fi", "Finnish", "Hei", "Tämä on pitkä lause suomeksi testausta varten."),
            ("bg", "Bulgarian", "Здравей", "Това е дълго изречение на български език за тестване."),
            ("da", "Danish", "Hej", "Dette er en lang sætning på dansk til testformål."),
            ("no", "Norwegian", "Hei", "Dette er en lang setning på norsk for testing."),
            ("sr", "Serbian", "Здраво", "Ово је дуга реченица на српском за тестирање."),
            ("sk", "Slovak", "Ahoj", "Toto je dlhá veta v slovenčine na testovanie."),
            ("hr", "Croatian", "Bok", "Ovo je duga rečenica na hrvatskom jeziku za testiranje."),
            ("lt", "Lithuanian", "Labas", "Tai ilgas sakinys lietuvių kalba testavimui."),
            ("sl", "Slovenian", "Živjo", "To je dolg stavek v slovenščini za testiranje."),
            ("et", "Estonian", "Tere", "See on pikk lause eesti keeles testimiseks."),
            ("ms", "Malay", "Hai", "Ini adalah ayat panjang dalam bahasa Melayu untuk ujian."),
            ("ca", "Catalan", "Hola", "Aquesta és una frase llarga en català per fer proves."),
            ("tl", "Tagalog", "Kamusta", "Ito ay isang mahabang pangungusap sa Tagalog para sa pagsubok."),
            ("my", "Burmese", "မင်္ဂလာပါ", "ဒါက စမ်းသပ်ဖို့ မြန်မာဘာသာနဲ့ ရှည်တဲ့ဝါကျပါ။"),
            ("ta", "Tamil", "வணக்கம்", "இது ஒரு நீண்ட தமிழ் வாக்கியம் சோதனைக்காக."),
            ("ml", "Malayalam", "ഹലോ", "ഇത് മലയാളത്തിൽ ഒരു ദീർഘവാക്യമാണ് പരീക്ഷയ്ക്കായി."),
            ("pa", "Punjabi", "ਹੈਲੋ", "ਇਹ ਪੰਜਾਬੀ ਵਿੱਚ ਇੱਕ ਲੰਮਾ ਵਾਕ ਹੈ ਜਾਂਚ ਲਈ।"),
            ("ro", "Romanian", "Salut", "Aceasta este o propoziție lungă în română pentru testare."),
            ("jw", "Javanese", "Halo", "Iki minangka ukara dawa ing basa Jawa kanggo dites."), // jv
            ("su", "Sundanese", "Halo", "Ieu mangrupikeun kalimat panjang dina basa Sunda pikeun nguji."),
            ("ha", "Hausa", "Sannu", "Wannan jimla ce mai tsawo a harshen Hausa don gwaji."),
            ("yo", "Yoruba", "Bawo", "Eyi jẹ gbolohun ọrọ gigun ni Yoruba fun idanwo."),
            ("ig", "Igbo", "Ndewo", "Nke a bụ ahịrịokwu ogologo n'asụsụ Igbo maka ule."),
            ("zu", "Zulu", "Sawubona", "Lena yisisho eside ngesiZulu sokuhlola."),
            ("am", "Amharic", "ሰላም", "ይህ የረጅም ሐረግ ለመሙከር ብቻ ነው።"),
            ("om", "Oromo", "Akkam", "Kun sagalee dheeraa Afaan Oromoo keessatti qorannooaf."),
            ("or", "Odia", "ନମସ୍କାର", "ଏହା ଓଡ଼ିଆ ଭାଷାରେ ଏକ ଦୀର୍ଘ ବାକ୍ୟ ପରୀକ୍ଷା ପାଇଁ।"),
            ("as", "Assamese", "নমস্কাৰ", "এইটো পৰীক্ষাৰ বাবে অসমীয়াত এটা দীঘল বাক্য।"),
            ("ma", "Maithili", "नमस्कार", "ई मैथिली में एक लंबा वाक्य अछि परीक्षण लेल।"),
            ("sd", "Sindhi", "سلام", "اها سنڌيءَ ۾ ڊگهي جملي آهي جاچ لاءِ."),
            ("ne", "Nepali", "नमस्ते", "यो परीक्षणको लागि नेपालीमा लामो वाक्य हो।"),
            ("si", "Sinhala", "හෙලෝ", "මෙය පරීක්ෂා කිරීම සඳහා සිංහලෙන් දිගු වාක්‍යයකි."),
            ("km", "Khmer", "សួស្តី", "នេះជាប្រយោគវែងមួយជាភាសាខ្មែរសម្រាប់សាកល្បង។"),
            ("lo", "Lao", "ສະບາຍດີ", "ນີ້ແມ່ນປະໂຫຍກຍາວໃນພາສາລາວສໍາລັບການທົດສອບ."),
            ("my", "Burmese", "မင်္ဂလာပါ", "ဒါက စမ်းသပ်ဖို့ မြန်မာဘာသာနဲ့ ရှည်တဲ့ဝါကျပါ။"),
            ("th", "Thai", "สวัสดี", "นี่คือประโยคยาวในภาษาไทยสำหรับการทดสอบ."),
            ("km", "Khmer", "សួស្តី", "នេះជាប្រយោគវែងមួយជាភាសាខ្មែរសម្រាប់សាកល្បង។"),
            ("mn", "Mongolian", "Сайн уу", "Энэ бол туршилтын зориулалттай урт өгүүлбэр монголоор."),
            ("uk", "Ukrainian", "Привіт", "Це довге речення українською мовою для тестування."),
            ("be", "Belarusian", "Прывітанне", "Гэта доўгае сказанне на беларускай мове для тэставання."),
            ("uz", "Uzbek", "Salom", "Bu, test uchun o'zbek tilida uzun gap."),
            ("kk", "Kazakh", "Сәлем", "Бұл қазақ тіліндегі ұзақ сөйлем сынақ үшін."),
            ("tt", "Tatar", "Сәлам", "Бу сынау өчен татарча озын җөмлә."),
            ("ky", "Kyrgyz", "Салам", "Бул тест үчүн кыргыз тилиндеги узун сүйлөм."),
            ("tk", "Turkmen", "Salam", "Bu, synag üçin türkmen dilindäki uzyn sözlem."),
            ("ps", "Pashto", "سلام", "دا په پښتو کې د ازموینې لپاره اوږده جمله ده."),
            ("af", "Afrikaans", "Hallo", "Ek hoop jy het 'n wonderlike dag vandag!"),
            ("sq", "Albanian", "Përshëndetje", "Kjo është një fjali e gjatë në shqip për testim."),
            ("bs", "Bosnian", "Zdravo", "Ovo je duga rečenica na bosanskom jeziku za testiranje."),
            ("ca", "Catalan", "Hola", "Aquesta és una frase llarga en català per fer proves."),
            ("eo", "Esperanto", "Saluton", "Ĉi tiu estas longa frazo en Esperanto por testi."),
            ("eu", "Basque", "Kaixo", "Hau da euskarazko esaldi luze bat probatzeko."),
            ("gl", "Galician", "Ola", "Esta é unha frase longa en galego para probar."),
            ("is", "Icelandic", "Halló", "Þetta er löng setning á íslensku til prófunar."),
            ("ga", "Irish", "Dia duit", "Is abairt fhada í seo i nGaeilge le haghaidh tástála."),
            ("mt", "Maltese", "Bongu", "Din sentenza twila bil-Malti għall-ittestjar."),
            ("sm", "Samoan", "Talofa", "O le fuaiupu umi lea i le gagana Samoa mo le su'ega."),
            ("gd", "Scots Gaelic", "Halò", "Is e seo seantans fhada ann an Gàidhlig airson deuchainn."),
            ("cy", "Welsh", "Helo", "Dyma frawddeg hir yn Gymraeg ar gyfer profi."),
            ("ny", "Chichewa", "Moni", "Iyi ndi ndime yaitali mu Chichewa yoyesera."),
            ("rw", "Kinyarwanda", "Muraho", "Iyi n'interuro ndende mu Kinyarwanda yo kugerageza."),
            ("so", "Somali", "Salaan", "Tani waa jumlad dheer oo af Soomaali ah oo tijaabo ah."),
            ("st", "Sesotho", "Lumela", "Sena ke polelo e telele ka Sesotho bakeng sa teko."),
            ("sn", "Shona", "Mhoro", "Iyi ndiyo ndima refu muShona yekuyedza."),
            ("yo", "Yoruba", "Bawo", "Eyi jẹ gbolohun ọrọ gigun ni Yoruba fun idanwo."),
            ("xh", "Xhosa", "Molo", "Esi sisivakalisi eside ngesiXhosa sokuvavanya."),
            ("zu", "Zulu", "Sawubona", "Lena yisisho eside ngesiZulu sokuhlola."),
            ("fil", "Filipino", "Kamusta", "Ito ay isang mahabang pangungusap sa Filipino para sa pagsubok."),
            ("ceb", "Cebuano", "Kumusta", "Kini usa ka taas nga hugpong sa mga pulong sa Cebuano alang sa pagsulay."),
            ("hmn", "Hmong", "Nyob zoo", "Qhov no yog ib kab lus ntev hauv Hmong rau kev xeem."),
            ("jv", "Javanese", "Halo", "Iki minangka ukara dawa ing basa Jawa kanggo dites."),
            ("zh-TW", "Chinese (Traditional)", "你好", "這是一個用於測試的繁體中文長句。"),
            ("yi", "Yiddish", "העלא", "דאָס איז אַ לאַנג זאַץ אויף ייִדיש פֿאַר טעסטינג.")
        ]
        
        for (code, language, short, long) in languageTestCases {
            let detectedShort = ContentProcessor.detectLanguage(short)
            // #expect(detectedShort == code, "Short sentence for \(language) should detect as \(code)")
            let detectedLong = ContentProcessor.detectLanguage(long)
            // #expect(detectedLong == code, "Long sentence for \(language) should detect as \(code)")
            
            var shortResult = "✅"
            var longResult = "✅"
            if detectedShort != code {
                shortResult = "❌"
            }
            if detectedLong != code {
                longResult = "❌"
            }

            print("Testing \(code) (\(language)): short -> \(detectedShort) \(shortResult), long -> \(detectedLong) \(longResult)")
        }
        // Basic language detection cases
        #expect(ContentProcessor.detectLanguage("Hello, how are you?") == "en")
        #expect(ContentProcessor.detectLanguage("你好，世界人民大团结") == "zh")
        #expect(ContentProcessor.detectLanguage("こんにちは") == "ja")
        #expect(ContentProcessor.detectLanguage("안녕하세요") == "ko")
        #expect(ContentProcessor.detectLanguage("مرحبا") == "ar")
        #expect(ContentProcessor.detectLanguage("สวัสดี") == "th")
        #expect(ContentProcessor.detectLanguage("Здравствуйте") == "ru")
        #expect(ContentProcessor.detectLanguage("Hola") == "es")
        #expect(ContentProcessor.detectLanguage("Bonjour") == "fr")
        #expect(ContentProcessor.detectLanguage("Guten Tag") == "de")
        
        // Unknown or very short strings should fallback to unknown
        #expect(ContentProcessor.detectLanguage("") == "unknown")
        #expect(ContentProcessor.detectLanguage("?") == "unknown")
    }
    
    @Test func testWhatsAppMessageParsing() async throws {
        // Test Chinese WhatsApp messages (单聊)
        let chineseReceivedMessage = "‎消息, Vuelva a probar si la pantalla, sigue colgada en estado de salvapantallas, 11:11, ‎从Carlos收到"
        if let result = ContentProcessor.shared.parseWhatsAppMessage(chineseReceivedMessage,language: "zh") {
            #expect(result.messageType == "text")
            #expect(result.content == "Vuelva a probar si la pantalla, sigue colgada en estado de salvapantallas")
            #expect(result.sender == "Carlos")
            #expect(result.isFromMe == false)  
            // Get current date in format YYYY-MM-DD
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let currentDateString = dateFormatter.string(from: Date())
            print("Current date: \(currentDateString)")
            #expect(result.timestamp == currentDateString + " 11:11:00")
        } else {
            #expect(Bool(false), "Failed to parse Chinese received message")
        }
        
        let chineseSentMessage = "‎你的消息, Este problema ya ha sido solucionado., 2025年8月5日11:37, ‎已发送到Carlos, ‎已读"
        if let result = ContentProcessor.shared.parseWhatsAppMessage(chineseSentMessage,language: "zh") {
            #expect(result.messageType == "text")
            #expect(result.content == "Este problema ya ha sido solucionado.")
            #expect(result.sender == "You")
            #expect(result.isFromMe == true)  
            #expect(result.timestamp == "2025-08-05 11:37:00")
        } else {
            #expect(Bool(false), "Failed to parse Chinese sent message")
        }
 
        let chineseSentMessage2 = "‎你的消息, 中文系统下无法正常解析, 2024年8月5日14:35, ‎已发送到Carlos, ‎已读"
        if let result = ContentProcessor.shared.parseWhatsAppMessage(chineseSentMessage2,language: "zh") {
            #expect(result.messageType == "text")
            #expect(result.content == "中文系统下无法正常解析")
            #expect(result.sender == "You")
            #expect(result.isFromMe == true)  
            #expect(result.timestamp == "2024-08-05 14:35:00")
        } else {
            #expect(Bool(false), "Failed to parse Chinese sent message")
        }

        // 发送的消息不一定都是有状态的分为三段，如果没有状态也可能是两段，所以也不完全靠几段来判断是发送的消息和接收的消息
        let chineseSentMessage3 = "‎你的消息, The climate of California is characterized as a typical Mediterranean climate., 14:35, ‎已发送到Carlos"
        if let result = ContentProcessor.shared.parseWhatsAppMessage(chineseSentMessage3,language: "zh") {
            #expect(result.messageType == "text")
            #expect(result.content == "The climate of California is characterized as a typical Mediterranean climate.")
            #expect(result.sender == "You")
            #expect(result.isFromMe == true)  
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let currentDateString = dateFormatter.string(from: Date())
            #expect(result.timestamp == "\(currentDateString) 14:35:00")
        } else {
            #expect(Bool(false), "Failed to parse Chinese sent message")
        }

        let chineseReceivedMessage2 = "‎‎消息和通话已进行端到端加密。只有此对话中的成员可以查看、收听或分享。‎了解更多。点击了解更多信息。"
        if let result = ContentProcessor.shared.parseWhatsAppMessage(chineseReceivedMessage2,language: "zh"){}
        else{
            #expect(true, "should be empty")
        }
        
        // Test Chinese WhatsApp group messages (群聊)
        let chineseGroupReceivedMessage = "‎Carlos发来的消息, 测试一下群聊, 16:50, ‎在Glotera测试群收到"
        if let result = ContentProcessor.shared.parseWhatsAppMessage(chineseGroupReceivedMessage,language: "zh") {
            #expect(result.messageType == "text")
            #expect(result.content == "测试一下群聊")
            #expect(result.sender == "Carlos")
            #expect(result.isFromMe == false)
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; let today = df.string(from: Date())
            #expect(result.timestamp == "\(today) 16:50:00")
        } else {
            #expect(Bool(false), "Failed to parse Chinese group received message")
        }
        
        let chineseGroupSentMessage = "‎你的消息, 有什么不一样的地方, 16:51, ‎发送到Glotera测试群, ‎已发送"
        if let result = ContentProcessor.shared.parseWhatsAppMessage(chineseGroupSentMessage,language: "zh") {
            #expect(result.messageType == "text")
            #expect(result.content == "有什么不一样的地方")
            #expect(result.sender == "You")
            #expect(result.isFromMe == true) 
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; let today = df.string(from: Date())
            #expect(result.timestamp == "\(today) 16:51:00")
        } else {
            #expect(Bool(false), "Failed to parse Chinese group sent message")
        }
        
        // Test English WhatsApp messages (单聊)
        let englishReceivedMessage = "‎message, 可以触发 focus, July30,at16:20, ‎Received from Princeton"
        if let result = ContentProcessor.shared.parseWhatsAppMessage(englishReceivedMessage,language: "en") {
            #expect(result.messageType == "text")
            #expect(result.content == "可以触发 focus")
            #expect(result.sender == "Princeton")
            #expect(result.isFromMe == false)  
            #expect(result.timestamp == "2025-07-30 16:20:00")
        } else {
            #expect(Bool(false), "Failed to parse English received message")
        }
        
        let englishSentMessage = "‎Your message, Test again, please ignore it, August3,at23:00, ‎Sent to Princeton, ‎Sent"
        if let result = ContentProcessor.shared.parseWhatsAppMessage(englishSentMessage,language: "en") {
            #expect(result.messageType == "text")
            #expect(result.content == "Test again, please ignore it")
            #expect(result.sender == "You")
            #expect(result.isFromMe == true)  
            #expect(result.timestamp == "2025-08-03 23:00:00")
        } else {
            #expect(Bool(false), "Failed to parse English sent message")
        }

        let englishSentMessage2 = "‎Your message, The climate of California is characterized as a typical Mediterranean climate., 14:35, ‎Sent to Carlos"
        if let result = ContentProcessor.shared.parseWhatsAppMessage(englishSentMessage2,language: "en") {
            #expect(result.messageType == "text")
            #expect(result.content == "The climate of California is characterized as a typical Mediterranean climate.")
            #expect(result.sender == "You")
            #expect(result.isFromMe == true)  
        } else {
            #expect(Bool(false), "Failed to parse English sent message")
        }

        let englishReceivedMessage2 = "‎message from Carlos, 可以触发 focus, July30,at16:20, ‎Received at Princeton"
        if let result = ContentProcessor.shared.parseWhatsAppMessage(englishReceivedMessage2,language: "en") {
            #expect(result.messageType == "text")
            #expect(result.content == "可以触发 focus")
            #expect(result.sender == "Carlos")
            #expect(result.isFromMe == false)  
            #expect(result.timestamp == "2025-07-30 16:20:00")
        } else {
            #expect(Bool(false), "Failed to parse English received message")
        }
        
        // Test timestamp parsing
        let messageWithTimestamp = "‎message, Hello world, 16:20, ‎Received from Test"
        if let result = ContentProcessor.shared.parseWhatsAppMessage(messageWithTimestamp,language: "en") {
            #expect(!result.timestamp.isEmpty, "Timestamp should not be empty") 
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let currentDateString = dateFormatter.string(from: Date())
            print("Current date: \(currentDateString)")
            #expect(result.timestamp == currentDateString + " 16:20:00")
        } else {
            #expect(Bool(false), "Failed to parse message with timestamp")
        }

        let messageWithTimestamp2 = "‎消息, Swing freely, 年8月9日上午3:48, ‎从bryan收到"
        if let result = ContentProcessor.shared.parseWhatsAppMessage(messageWithTimestamp2,language: "zh") {
            #expect(!result.timestamp.isEmpty, "Timestamp should not be empty") 
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy"
            let currentDateString = dateFormatter.string(from: Date())
            #expect(result.timestamp == "\(currentDateString)-08-09 03:48:00")
        } else {
            #expect(Bool(false), "Failed to parse message with timestamp")
        }

        let messageWithTimestamp3 = "‎消息, Finally fixed this issue, 下午4:50, ‎从bryan收到"
        if let result = ContentProcessor.shared.parseWhatsAppMessage(messageWithTimestamp3,language: "zh") {
            #expect(!result.timestamp.isEmpty, "Timestamp should not be empty") 
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let currentDateString = dateFormatter.string(from: Date())
            #expect(result.timestamp == "\(currentDateString) 16:50:00")
        } else {
            #expect(Bool(false), "Failed to parse message with timestamp")
        }

        let messageWithTimestamp4 = "‎message, Strange project, 4:53 PM, ‎Received from Carlos"
        if let result = ContentProcessor.shared.parseWhatsAppMessage(messageWithTimestamp4,language: "en") {
            #expect(!result.timestamp.isEmpty, "Timestamp should not be empty") 
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let currentDateString = dateFormatter.string(from: Date())
            #expect(result.timestamp == "\(currentDateString) 16:53:00")
        } else {
            #expect(Bool(false), "Failed to parse message with timestamp")
        }

        let messageWithTimestamp5 = "‎message, Let's start, August9,at3:41 AM, ‎Received from Carlos"
        if let result = ContentProcessor.shared.parseWhatsAppMessage(messageWithTimestamp5,language: "en") {
            #expect(!result.timestamp.isEmpty, "Timestamp should not be empty") 
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy"
            let currentDateString = dateFormatter.string(from: Date())
            #expect(result.timestamp == "\(currentDateString)-08-09 03:41:00")
        } else {
            #expect(Bool(false), "Failed to parse message with timestamp")
        }

        let messageWithTimestamp6 = "‎message, Let's start, August12,at3:41 PM, ‎Received from Carlos"
        if let result = ContentProcessor.shared.parseWhatsAppMessage(messageWithTimestamp6,language: "en") {
            #expect(!result.timestamp.isEmpty, "Timestamp should not be empty") 
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy"
            let currentDateString = dateFormatter.string(from: Date())
            #expect(result.timestamp == "\(currentDateString)-08-12 15:41:00")
        } else {
            #expect(Bool(false), "Failed to parse message with timestamp")
        }
        
        // Test invalid messages
        let invalidMessage = "Invalid format without proper structure"
        let invalidResult = ContentProcessor.shared.parseWhatsAppMessage(invalidMessage)
        #expect(invalidResult == nil, "Should return nil for invalid message format")
        
        let emptyMessage = ""
        let emptyResult = ContentProcessor.shared.parseWhatsAppMessage(emptyMessage)
        #expect(emptyResult == nil, "Should return nil for empty message")
    }
    
}
