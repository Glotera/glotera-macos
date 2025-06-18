import Cocoa

class MenuBarController {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var languageConfigWindow: LanguageConfigWindow?

    init() {
        print("[LOG] MenuBarController initialized")
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "Translator")
        }
        constructMenu()
    }

    func constructMenu() {
        let menu = NSMenu()
        
        // Main function menu
        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        // Debug menu
        menu.addItem(NSMenuItem.separator())
        let debugMenu = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        let debugSubMenu = NSMenu()
        
        let testTriggerItem = NSMenuItem(title: "Test Trigger", action: #selector(testTrigger), keyEquivalent: "")
        testTriggerItem.target = self
        debugSubMenu.addItem(testTriggerItem)
        
        let testDiscordTriggerItem = NSMenuItem(title: "Test Discord Trigger", action: #selector(testDiscordTrigger), keyEquivalent: "")
        testDiscordTriggerItem.target = self
        debugSubMenu.addItem(testDiscordTriggerItem)
        
        let testSpaceKeyItem = NSMenuItem(title: "Test Space Key Capture", action: #selector(testSpaceKeyCapture), keyEquivalent: "")
        testSpaceKeyItem.target = self
        debugSubMenu.addItem(testSpaceKeyItem)
        
        let showStatusItem = NSMenuItem(title: "Show Status", action: #selector(showStatus), keyEquivalent: "")
        showStatusItem.target = self
        debugSubMenu.addItem(showStatusItem)
        
        let restartEventItem = NSMenuItem(title: "Restart Event Monitoring", action: #selector(restartEventMonitoring), keyEquivalent: "")
        restartEventItem.target = self
        debugSubMenu.addItem(restartEventItem)
        
        debugSubMenu.addItem(NSMenuItem.separator())
        
        let resetCountersItem = NSMenuItem(title: "Reset Counters", action: #selector(resetCounters), keyEquivalent: "")
        resetCountersItem.target = self
        debugSubMenu.addItem(resetCountersItem)
        
        let forceHealthCheckItem = NSMenuItem(title: "Force Health Check", action: #selector(forceHealthCheck), keyEquivalent: "")
        forceHealthCheckItem.target = self
        debugSubMenu.addItem(forceHealthCheckItem)
        
        debugSubMenu.addItem(NSMenuItem.separator())
        
        let openConsoleItem = NSMenuItem(title: "Open Console", action: #selector(openConsole), keyEquivalent: "")
        openConsoleItem.target = self
        debugSubMenu.addItem(openConsoleItem)
        
        debugMenu.submenu = debugSubMenu
        menu.addItem(debugMenu)
        
        // Exit menu
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }

    @objc func openSettings() {
        print("[LOG] Settings menu clicked")
        
        // 如果窗口已存在，直接显示
        if let existingWindow = languageConfigWindow {
            existingWindow.show()
            return
        }
        
        // 创建新的语言配置窗口
        languageConfigWindow = LanguageConfigWindow()
        languageConfigWindow?.show()
        
        // 监听窗口关闭事件，释放引用
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: languageConfigWindow,
            queue: .main
        ) { [weak self] _ in
            self?.languageConfigWindow = nil
        }
    }
    
    @objc func testTrigger() {
        print("[LOG] Manual trigger test requested")
        InputMonitor.shared.manualTriggerTest()
        
        // Show test completion notification
        let alert = NSAlert()
        alert.messageText = "Trigger Test Completed"
        alert.informativeText = "Please check console output for detailed information"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    @objc func testDiscordTrigger() {
        print("[LOG] Discord trigger test requested")
        InputMonitor.shared.testDiscordTrigger()
        
        // Show test completion notification
        let alert = NSAlert()
        alert.messageText = "Discord Trigger Test Completed"
        alert.informativeText = "Please check console output for detailed information.\nRecommend entering test content (like 'hello #@en') in Discord input box before running this test."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    @objc func testSpaceKeyCapture() {
        print("[LOG] Space key capture test requested")
        InputMonitor.shared.testSpaceKeyCapture()
    }
    
    @objc func showStatus() {
        print("[LOG] Status info requested")
        let statusInfo = InputMonitor.shared.getStatusInfo()
        
        let alert = NSAlert()
        alert.messageText = "System Status"
        alert.informativeText = statusInfo
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Copy to Clipboard")
        
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(statusInfo, forType: .string)
        }
    }
    
    @objc func restartEventMonitoring() {
        print("[LOG] Event monitoring restart requested")
        
        // Notify AppDelegate to restart event monitoring
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.restartEventMonitoring()
        }
        
        let alert = NSAlert()
        alert.messageText = "Restart Completed"
        alert.informativeText = "Event monitoring has been restarted"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    @objc func openConsole() {
        print("[LOG] Opening Console app")
        NSWorkspace.shared.launchApplication("Console")
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    @objc func resetCounters() {
        print("[LOG] Reset counters requested")
        InputMonitor.shared.resetEventCounters()
        
        let alert = NSAlert()
        alert.messageText = "Counters Reset"
        alert.informativeText = "Event counters have been reset to zero"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    @objc func forceHealthCheck() {
        print("[LOG] Force health check requested")
        InputMonitor.shared.forceHealthCheck()
        
        let alert = NSAlert()
        alert.messageText = "Health Check Completed"
        alert.informativeText = "Please check console output for detailed information"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
} 