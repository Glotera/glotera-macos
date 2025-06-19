import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Text("Language configuration, shortcut keys, startup settings, etc.")
            // 这里可扩展更多设置项
        }
        .frame(width: 400, height: 300)
    }
} 