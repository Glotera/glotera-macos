# macOS 打包与公证（Glotera）

本文档为通用流程说明，不含真实账号、Team ID 或密码。发布前请在本地配置 `config/developer.env`（由 `config/developer.env.template` 复制）。

## 1. 申请证书

1. 注册 [Apple Developer](https://developer.apple.com/) 账号
2. Keychain Access → Certificate Assistant → Request a Certificate From a Certificate Authority…
3. 在 developer.apple.com 创建 **Developer ID Application** 证书并导入钥匙串

## 2. 查看本机签名身份

```bash
security find-identity -v -p codesigning
```

记下 **Developer ID Application** 那一行的完整名称，填入 `config/developer.env` 的 `DEVELOPER_ID`。

示例输出（占位）：

```text
1) ABCD1234... "Apple Development: you@example.com (XXXXXXXXXX)"
2) EFGH5678... "Developer ID Application: Your Name (TEAM_ID)"
   2 valid identities found
```

## 3. 导出 Release 版 App

1. Xcode Scheme 选 **Release**
2. Product → Archive → Distribute App → Custom → Copy App

## 4. 核对 Bundle ID

```bash
plutil -p Glotera-0.0.0/Glotera.app/Contents/Info.plist | grep CFBundleIdentifier
# 应为: "ai.glotera.desktop"
```

## 5. 代码签名

将 `YOUR_DEVELOPER_ID` 替换为 `config/developer.env` 中的 `DEVELOPER_ID` 值：

```bash
codesign -f -o runtime -s "YOUR_DEVELOPER_ID" -v Glotera-0.0.0/Glotera.app --deep
codesign --verify --verbose=4 Glotera-0.0.0/Glotera.app
```

## 6. 打包 ZIP（用于公证）

```bash
ditto -c -k --keepParent Glotera-0.0.0/Glotera.app glotera-0.0.0.zip
```

## 7. 配置 notarytool 钥匙串描述文件（仅需一次）

在 [appleid.apple.com](https://appleid.apple.com/) 生成 **App 专用密码**，然后执行：

```bash
xcrun notarytool store-credentials "YOUR_KEYCHAIN_PROFILE" \
  --apple-id "your-apple-id@example.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD"
```

与 `config/developer.env` 中 `KEYCHAIN_PROFILE`、`APPLE_ID`、`APPLE_TEAM_ID` 保持一致。

## 8. 提交公证

```bash
xcrun notarytool submit glotera-0.0.0.zip \
  --keychain-profile "YOUR_KEYCHAIN_PROFILE" \
  --wait
```

## 9. 查看公证状态与日志

```bash
xcrun notarytool history --keychain-profile "YOUR_KEYCHAIN_PROFILE"
xcrun notarytool log SUBMISSION_ID --keychain-profile "YOUR_KEYCHAIN_PROFILE"
```

成功时 `status` 为 `Accepted`。完整 JSON 日志请在本机查看，勿提交到版本库。

## 10. 注入公证票据（Staple）

```bash
xcrun stapler staple /path/to/Glotera.app
```

## 11. Gatekeeper 验证

```bash
# .app
spctl --assess --type exec -v /path/to/Glotera.app
# 期望: accepted, source=Notarized Developer ID

# .dmg
spctl --assess --type open --context context:primary-signature -v /path/to/Glotera.dmg
```

## 12. 制作 DMG（可选）

`appdmg.json` 示例：

```json
{
  "title": "Glotera Installer",
  "icon": "glotera.icns",
  "background": "background.png",
  "window": { "size": { "width": 500, "height": 300 } },
  "contents": [
    { "x": 100, "y": 150, "type": "file", "path": "dist/Glotera.app" },
    { "x": 350, "y": 150, "type": "link", "path": "/Applications" }
  ]
}
```

```bash
npm install -g appdmg
appdmg appdmg.json Glotera.dmg
```

## 使用 package.sh

```bash
cp config/developer.env.template config/developer.env
# 编辑 config/developer.env

./package.sh 0.2.0 2025070701 --notarize
```

详见仓库根目录 `package.sh` 与 `docs/SPARKLE_INTEGRATION.md`。
