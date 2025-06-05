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
        menu.addItem(NSMenuItem(title: "设置", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func openSettings() {
        // 打开设置窗口
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
} 