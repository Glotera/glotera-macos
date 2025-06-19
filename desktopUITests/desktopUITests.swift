//
//  desktopUITests.swift
//  desktopUITests
//
//  Created by Bryanzh on 2025/6/5.
//

import XCTest
/**
 ⚠️：
 1.请先将 Target 设置为  desktopUITests
 2.如果报错：No such module 'Testing' ，请先 Clean Build Folder
 3.如果报错：签名错误，在证书设置正确的情况下 ，请先 Clean Build Folder

 */
final class desktopUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    
    func showAppWindows(app: XCUIApplication){
        
        // UI tests must launch the application that they test.
        // 遍历所有窗口并打印属性
        for window in app.windows.allElementsBoundByIndex {
            // 打印窗口的调试描述（包含层级、标识符等信息）
            print("窗口调试描述：\(window.debugDescription)")
            
            // 也可单独获取部分属性，比如窗口标题（若有）
            let title = window.title
            print("窗口标题：\(title)")
            
            // 还能获取其他属性，如是否存在、坐标等
            print("窗口是否存在：\(window.exists)")
            print("窗口坐标：\(window.frame)")
            print("------------------------")
        }
    }
    
    /**
     WeChat  4.0.5.27
     在使用工程内XCUITests testWeChat 测试时，⚠️⚠️⚠️请尽可能的删除微信聊天框，至少保留1个即可，使你的mac 微信聊天框不要充满整个列表，否则会滑动导致点击不准的问题
     
     进行如下测试:
     1.选中一个顶部的聊天框，单击进入
     2.会清空当前聊天框所有消息⚠️⚠️⚠️，这么做是经验之谈，避免过多聊天记录的干扰,所以请准备测试聊天
     3.在输入框输入 "你好呀你好呀你好呀"
     4.选中中间的"你好呀",然后弹窗进行翻译，翻译后替换原来中间的”你好呀“，并检测正确性
     5.全选 "你好呀你好呀你好呀 "，输入 "#en ",翻译后替换原来的"你好呀你好呀你好呀"，并检测正确性，然后点击回车发送
     6.在聊天记录中，选中刚发发送的"你好呀你好呀你好呀"对应的英文翻译，弹出翻译弹窗，下来语言选择框，选择"中文' 进行翻译，并检测翻译结果的正确性
     
     */
    func testWeChat() throws {
        
        let WeChatApp = XCUIApplication(bundleIdentifier: "com.tencent.xinWeChat")
        WeChatApp.launch()
        
        // 1.启动微信
        let exists = WeChatApp.wait(for: .runningForeground, timeout: 10)
        XCTAssertTrue(exists, "WeChat failed to launch")
        
        // 2.登录微信
        if WeChatApp.buttons["Log In"].waitForExistence(timeout: 10) {
            WeChatApp.buttons["Log In"].click()
        }
        
        
        let mainWindow = WeChatApp.windows["Weixin"]
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 20), "主窗口加载失败")
        
        let chatsSection = mainWindow.otherElements["Chats"]
        XCTAssertTrue(chatsSection.waitForExistence(timeout: 10), "聊天列表区域加载失败")
        
        // 3.点击顶部聊天框
        chatsSection.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx:20,dy: 20)).tap()
        
        
        
        
        // 4.启动我们的 Glotera app
        let app = XCUIApplication()
        app.launch()
        
        // 5.清空聊天记录
        let chatInfoButton = mainWindow.buttons["Chat Info"]
        chatInfoButton.tap()
        
        
        let clearChatHistoryButton = mainWindow.buttons["Clear Chat History"]
        clearChatHistoryButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        
        let clearButton = mainWindow.buttons["Clear"]
        clearButton.tap()
        
        
        // 6.获取编辑框
        let textEditor : XCUIElement = mainWindow.textViews.allElementsBoundByAccessibilityElement.last!
        textEditor.tap()
        
        
        
        /** TEST1:          选中中间的"你好呀",然后弹窗进行翻译，翻译后替换原来中间的”你好呀“，并检测正确性   -----------------    **/
        // TEST1.1.全选已有内容
        textEditor.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.01)).click(forDuration: 1, thenDragTo: textEditor.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.8)))
        
        let testString = "你好呀  "
        let testStringLen = testString.count
        let testStringWidth = 60
        let Y = 10
        textEditor.typeText(testString)
        
        let pos0 = textEditor.coordinate(withNormalizedOffset:.zero)
        
        let pos1 = textEditor.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx: testStringWidth, dy: Y))
        pos1.tap()
        textEditor.typeText(testString)
        let pos2 = textEditor.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx: testStringWidth*2, dy:Y))
        pos2.tap()
        textEditor.typeText(testString)
        let pos3 = textEditor.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx: testStringWidth*3, dy: Y))
        pos3.tap()
        
        let pos4 = textEditor.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx: testStringWidth*8, dy: Y))
        // TEST1.2.选中部分文字进行弹窗翻译后插入，选中的是"好呀  你"，翻译后应该满足 "你好呀  你.+好呀  "
        pos1.click(forDuration: 1, thenDragTo: pos2)
        
        var windowsQuery = app.windows
        var popUpButton = app.popUpButtons.element(boundBy: 0)
        popUpButton.click()
        windowsQuery = app.windows
        
        // TEST1.3.选中英语进行翻译
        windowsQuery.menuItems["English"].click()
        
        sleep(5)
        // TEST1.3.自动插入后，检验结果是否满足 "你好呀  你.+好呀  " 正则表达式
        var translatedString : String! = textEditor.value as! String
        print("translatedString:" + translatedString)
        // 定义正则表达式："你好呀  你.+好呀  "
        let pattern = "你好呀\\s+你.+好呀\\s+"
        
        
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: translatedString, range: NSRange(translatedString.startIndex..., in: translatedString))
        
        
        // XCTAssertTrue(matches.count > 0, "输入框部分翻译插入失败")
        
        
        /** TEST2:          全选输入框文字,然后弹窗进行翻译，翻译后整体替换原来输入框文字，并检测正确性   -----------------    **/
        // TEST2.1.全选已有内容
        textEditor.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.01)).click(forDuration: 1, thenDragTo: textEditor.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.8)))
        
        
        
        textEditor.typeText(testString)
        
        textEditor.typeText(testString)
        
        textEditor.typeText(testString)
        
        
        pos3.tap()
        
        // TEST2.2.输入 #en 触发翻译
        textEditor.typeText("#en ")
        
        
        sleep(3)
        // TEST2.3.整体翻译后，检查结果是否是 "Hello there, hello there, hello there."
        translatedString = textEditor.value as! String
        print("translatedString:" + translatedString)
        
        
        // 定义正则表达式："你好呀  你.+好呀  "
        var matchString = "Hello there, hello there, hello there"
        
        
        //  XCTAssertTrue(translatedString == matchString, "输入框整体翻译插入失败")
        
        
        pos4.tap()
        // TEST2.4.回车发送
        textEditor.typeText("\n")
        textEditor.typeText("\n")
        textEditor.typeText("\n")
        
        
        /** TEST3:          在聊天记录中，选中刚发发送的"你好呀你好呀你好呀"对应的英文翻译，弹出翻译弹窗，下来语言选择框，选择"中文' 进行翻译，并检测翻译结果的正确性   -----------------    **/
        
        // TEST3.1.获取最后一条聊天记录
        let messagesTable = mainWindow.otherElements["Messages"]
        let lastMessageLabel =  messagesTable.staticTexts.allElementsBoundByAccessibilityElement.last
        let lastMessageLabelFrame = lastMessageLabel?.frame
        let endX = lastMessageLabelFrame!.width - 83
        let midX = lastMessageLabelFrame!.width - 150
        let startX = endX - 300
        let midY = lastMessageLabelFrame!.height / 2.0
        
        // TEST3.2.选中
        let lastMessageLabelMidPoint = lastMessageLabel!.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx:midX,dy: midY))
        
        lastMessageLabel!.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx:endX,dy: midY)).click(forDuration: 1.0, thenDragTo: lastMessageLabel!.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx:startX,dy: midY)), withVelocity: 1000, thenHoldForDuration: 1)
        
        
        sleep(5)
        
        popUpButton = app.popUpButtons.element(boundBy: 0)
        print("app:\(app.debugDescription),app.popUpButtons:\(app.popUpButtons)")
        popUpButton.click()
        windowsQuery = app.windows
        
        // TEST3.3.选中中文进行翻译
        windowsQuery.menuItems["中文"].click()
        
        // TEST3.4.检测翻译结果
        
        let appScrollView = app.scrollViews.firstMatch
        let translatedStaticText = appScrollView.staticTexts.firstMatch
        translatedString = translatedStaticText.value as! String
        print("translatedString:" + translatedString)
        
        
        // 定义正则表达式："你好呀  你.+好呀  "
        matchString = "你好，你好，你好"
        
        
        XCTAssertTrue(translatedString == matchString, "聊天记录弹窗翻译失败")
        
        windowsQuery.buttons["Close"].click()
        
    }
    
    /**
     QQ 6.9.32-22741

     进行如下测试:
     1.选中一个顶部的聊天框，单击进入
     2.会清空当前聊天框所有消息⚠️⚠️⚠️，这么做是经验之谈，避免过多聊天记录的干扰,所以请准备测试聊天
     3.在输入框输入 "你好呀你好呀你好呀"
     4.选中中间的"你好呀",然后弹窗进行翻译，翻译后替换原来中间的”你好呀“，并检测正确性
     5.全选 "你好呀你好呀你好呀 "，输入 "#en ",翻译后替换原来的"你好呀你好呀你好呀"，并检测正确性，然后点击回车发送
     6.在聊天记录中，选中刚发发送的"你好呀你好呀你好呀"对应的英文翻译，弹出翻译弹窗，下来语言选择框，选择"中文' 进行翻译，并检测翻译结果的正确性
     
     */
    func testQQ() throws {
        
        let QQApp = XCUIApplication(bundleIdentifier: "com.tencent.qq")
        
        // 1.启动QQ
        QQApp.launch()
        

        XCTAssertTrue(QQApp.wait(for: .runningForeground, timeout: 5), "QQ 启动失败")
        
        // 2.登录QQ
        let enterButton = QQApp.buttons["登录"]
        enterButton.waitForExistence(timeout: 10)
        enterButton.click()

        

        let chatList = QQApp.groups["会话列表"]

        XCTAssertTrue(chatList.waitForExistence(timeout: 5), "未找到会话列表")
        
        // 3.点击顶部聊天框
        chatList.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx:20,dy: 20)).tap()
        
        sleep(3)
        
        
        
        // 4.清空聊天记录
        let toolbar = QQApp.toolbars["更多"]
        let threePointButton = toolbar.buttons.allElementsBoundByAccessibilityElement.last
        threePointButton?.tap()
        
        
        let clearChatHistoryButton = QQApp.buttons["删除聊天记录"]
        clearChatHistoryButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        
        
        let clearButton = QQApp.buttons["确定"]
        clearButton.tap()
        


        // 5.启动我们的 Glotera app
        let app = XCUIApplication()
        app.launch()
        
        // 6.获取编辑框
        let textEditor = QQApp.groups["Rich Text Editor"]

        textEditor.tap()

        
        /** TEST1:          选中中间的"你好呀",然后弹窗进行翻译，翻译后替换原来中间的”你好呀“，并检测正确性   -----------------    **/
        // TEST1.1.全选已有内容
        textEditor.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.01)).click(forDuration: 1, thenDragTo: textEditor.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.8)))
        
        
        let testString = "你好呀"
        let testStringLen = testString.count
        let testStringWidth = 70
        let Y = 10
        textEditor.typeText(testString)
        textEditor.typeText(" ")
        textEditor.typeText(" ")
        let pos0 = textEditor.coordinate(withNormalizedOffset:.zero)
        
        let pos1 = textEditor.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx: testStringWidth, dy: Y))
        pos1.tap()
        textEditor.typeText(testString)
        textEditor.typeText(" ")
        textEditor.typeText(" ")
        let pos2 = textEditor.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx: testStringWidth*2, dy:Y))
        pos2.tap()
        textEditor.typeText(testString)
        textEditor.typeText(" ")
        textEditor.typeText(" ")
        let pos3 = textEditor.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx: testStringWidth*3, dy: Y))
        pos3.tap()
        
        let pos4 = textEditor.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx: testStringWidth*8, dy: Y))
        // TEST1.2.选中部分文字进行弹窗翻译后插入，选中的是"好呀  你"，翻译后应该满足 "你好呀  你.+好呀  "
        pos1.click(forDuration: 1, thenDragTo: pos2)
        
        var windowsQuery = app.windows
        var popUpButton = app.popUpButtons.element(boundBy: 0)
        popUpButton.click()
        windowsQuery = app.windows
        
        // TEST1.3.选中英语进行翻译
        windowsQuery.menuItems["English"].click()
        
        sleep(5)
        // TEST1.3.自动插入后，检验结果是否满足 "你好呀  你.+好呀  " 正则表达式
        var translatedString : String! = textEditor.value as! String
        print("translatedString:" + translatedString)
        // 定义正则表达式："你好呀  你.+好呀  "
        let pattern = "你好呀\\s+你.+好呀\\s+"
        
        
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: translatedString, range: NSRange(translatedString.startIndex..., in: translatedString))
        
        
        // XCTAssertTrue(matches.count > 0, "输入框部分翻译插入失败")
        
        
        /** TEST2:          全选输入框文字,然后弹窗进行翻译，翻译后整体替换原来输入框文字，并检测正确性   -----------------    **/
        // TEST2.1.全选已有内容
        textEditor.tap()
        textEditor.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.01)).click(forDuration: 1, thenDragTo: textEditor.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.8)))
        
        
        
        textEditor.typeText(testString)
        textEditor.typeText(" ")
        textEditor.typeText(" ")
        
        textEditor.typeText(testString)
        textEditor.typeText(" ")
        textEditor.typeText(" ")
        
        textEditor.typeText(testString)
        textEditor.typeText(" ")
        textEditor.typeText(" ")
        
        pos3.tap()
        
        // TEST2.2.输入 #en 触发翻译
        textEditor.typeText("#en ")
        
        
        sleep(3)
        // TEST2.3.整体翻译后，检查结果是否是 "Hello there, hello there, hello there."
        translatedString = textEditor.value as! String
        print("translatedString:" + translatedString)
        
        
        // 定义正则表达式："你好呀  你.+好呀  "
        var matchString = "Hello there, hello there, hello there"
        
        
        //  XCTAssertTrue(translatedString == matchString, "输入框整体翻译插入失败")
        
        
        pos4.tap()
        // TEST2.4.回车发送
        textEditor.typeText("\n")
        textEditor.typeText("\n")
        textEditor.typeText("\n")
        
        
        

        
        /** TEST3:          在聊天记录中，选中刚发发送的"你好呀你好呀你好呀"对应的英文翻译，弹出翻译弹窗，下来语言选择框，选择"中文' 进行翻译，并检测翻译结果的正确性   -----------------    **/
        
        // TEST3.1.获取最后一条聊天记录
        let messageList = QQApp.groups["消息列表"]
        let lastMessageLabel = messageList.groups.firstMatch.groups.firstMatch.groups.firstMatch.groups.allElementsBoundByAccessibilityElement[6]

        let lastMessageLabelFrame = lastMessageLabel.frame
        let endX = lastMessageLabelFrame.width - 3
        let midX = lastMessageLabelFrame.width - 150
        let startX = endX - 300
        let midY = lastMessageLabelFrame.height / 2.0
        
        // TEST3.2.选中
        let lastMessageLabelMidPoint = lastMessageLabel.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx:midX,dy: midY))
        
        lastMessageLabel.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx:endX,dy: midY)).click(forDuration: 1.0, thenDragTo: lastMessageLabel.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx:startX,dy: midY)), withVelocity: 1000, thenHoldForDuration: 1)
        
        
        sleep(5)
        
        popUpButton = app.popUpButtons.element(boundBy: 0)
        print("app:\(app.debugDescription),app.popUpButtons:\(app.popUpButtons)")
        popUpButton.click()
        windowsQuery = app.windows
        
        // TEST3.3.选中中文进行翻译
        windowsQuery.menuItems["中文"].click()
        
        sleep(3)
        
        
        // TEST3.4.检测翻译结果
        
        let appScrollView = app.scrollViews.firstMatch
        let translatedStaticText = appScrollView.staticTexts.firstMatch
        translatedString = translatedStaticText.value as! String
        print("translatedString:" + translatedString)
        
        
        // 定义正则表达式："你好呀  你.+好呀  "
        matchString = "你好，你好，你好"
        
        
        XCTAssertTrue(translatedString == matchString, "聊天记录弹窗翻译失败")
        
        windowsQuery.buttons["Close"].click()
        
    }
    
    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
