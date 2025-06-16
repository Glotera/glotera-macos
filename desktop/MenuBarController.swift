import Cocoa

class MenuBarController {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    init() {
        print("[LOG] MenuBarController initialized")
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "Translator")
        }
        constructMenu()
    }

    func constructMenu() {
        let menu = NSMenu()
        
        // 主要功能菜单
        menu.addItem(NSMenuItem(title: "设置", action: #selector(openSettings), keyEquivalent: ","))
        
        // 调试菜单
        menu.addItem(NSMenuItem.separator())
        let debugMenu = NSMenuItem(title: "调试", action: nil, keyEquivalent: "")
        let debugSubMenu = NSMenu()
        
        debugSubMenu.addItem(NSMenuItem(title: "测试触发器", action: #selector(testTrigger), keyEquivalent: ""))
        debugSubMenu.addItem(NSMenuItem(title: "测试Discord触发器", action: #selector(testDiscordTrigger), keyEquivalent: ""))
        debugSubMenu.addItem(NSMenuItem(title: "测试空格键捕获", action: #selector(testSpaceKeyCapture), keyEquivalent: ""))
        debugSubMenu.addItem(NSMenuItem(title: "显示状态", action: #selector(showStatus), keyEquivalent: ""))
        debugSubMenu.addItem(NSMenuItem(title: "重启事件监听", action: #selector(restartEventMonitoring), keyEquivalent: ""))
        debugSubMenu.addItem(NSMenuItem.separator())
        debugSubMenu.addItem(NSMenuItem(title: "重置计数器", action: #selector(resetCounters), keyEquivalent: ""))
        debugSubMenu.addItem(NSMenuItem(title: "强制健康检查", action: #selector(forceHealthCheck), keyEquivalent: ""))
        debugSubMenu.addItem(NSMenuItem.separator())
        debugSubMenu.addItem(NSMenuItem(title: "打开控制台", action: #selector(openConsole), keyEquivalent: ""))
        
        debugMenu.submenu = debugSubMenu
        menu.addItem(debugMenu)
        
        // 退出菜单
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }

    @objc func openSettings() {
        // 打开设置窗口
        print("[LOG] Settings menu clicked")
    }
    
    @objc func testTrigger() {
        print("[LOG] Manual trigger test requested")
        InputMonitor.shared.manualTriggerTest()
        
        // 显示测试完成的通知
        let alert = NSAlert()
        alert.messageText = "触发器测试完成"
        alert.informativeText = "请查看控制台输出以获取详细信息"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    @objc func testDiscordTrigger() {
        print("[LOG] Discord trigger test requested")
        InputMonitor.shared.testDiscordTrigger()
        
        // 显示测试完成的通知
        let alert = NSAlert()
        alert.messageText = "Discord触发器测试完成"
        alert.informativeText = "请查看控制台输出以获取详细信息。\n建议在Discord输入框中输入测试内容（如 'hello #@en'）后再运行此测试。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
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
        alert.messageText = "系统状态"
        alert.informativeText = statusInfo
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "复制到剪贴板")
        
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(statusInfo, forType: .string)
        }
    }
    
    @objc func restartEventMonitoring() {
        print("[LOG] Event monitoring restart requested")
        
        // 通知AppDelegate重启事件监听
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.restartEventMonitoring()
        }
        
        let alert = NSAlert()
        alert.messageText = "重启完成"
        alert.informativeText = "事件监听已重新启动"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
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
        alert.messageText = "计数器已重置"
        alert.informativeText = "事件计数器已重置为零"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    @objc func forceHealthCheck() {
        print("[LOG] Force health check requested")
        InputMonitor.shared.forceHealthCheck()
        
        let alert = NSAlert()
        alert.messageText = "健康检查完成"
        alert.informativeText = "请查看控制台输出以获取详细信息"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
} 