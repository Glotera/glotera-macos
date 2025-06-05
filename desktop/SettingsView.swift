import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Text("语言配置、快捷键、开机启动等设置")
            // 这里可扩展更多设置项
        }
        .frame(width: 400, height: 300)
    }
} 