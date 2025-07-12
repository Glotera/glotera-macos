# Mac打包发行的步骤

## 申请证书
- 注册Apple Develper开发者账号，$99/年
- 申请证书
  - Keychain Access > Certificate Assistant > Request a Certificate From a Certificate Authority...
  - 将申请的证书上传developer.apple.com进行认证，使用Developer ID Application这个选项，下载证书双击导入

## 查看证书是否正确
```bash
-- 第3个有了说明正常了
(base) bryanzh@BMA release % security find-identity -v -p codesigning
  1) 31D35FEFBC0198845FF6A46ED8F72332FAF6714A "Apple Development: yikebocai@gmail.com (FLLL94GWWX)"
  2) 84515235F3BCF4802F1C5BDE9FF6A77AD3CE59A8 "Apple Development: glotera.ai@gmail.com (B3X8H554SN)"
  3) 90E8D8FA31547D951B07B1E83687BA35F7B7D4AB "Developer ID Application: Xinbo Zhang (6Q3GB859VC)"
     3 valid identities found
```

## 导出app
schema 从debug改为release
Xcode-> Product-> Archive -> Distribute App -> Custom -> Copy App

## Verify Bundle ID and Team Configuration
Check that your app's bundle ID matches your Apple Developer account:
```bash
# Check current bundle ID
plutil -p Glotera-0.1.4/Glotera.app/Contents/Info.plist | grep CFBundleIdentifier
# Should show: "CFBundleIdentifier" => "ai.glotera.desktop"
```

## 进行签名
```bash
(base) bryanzh@BMA release % codesign -f -o runtime -s "Developer ID Application: Xinbo Zhang (6Q3GB859VC)" -v Glotera-0.2.0/Glotera.app --deep
Glotera-0.1.4/Glotera.app: replacing existing signature
Glotera-0.1.4/Glotera.app: signed app bundle with Mach-O universal (x86_64 arm64) [ai.glotera.desktop]

-- 进行验证签名
codesign --verify --verbose=4 Glotera-0.1.4/Glotera.app
```

## 打包成zip文件
```bash
ditto -c -k --keepParent Glotera-0.1.4/Glotera.app glotera-0.1.4.zip
```
 
## 生成notarytool keychain profile，避免每次输密码(只需要操作一次)
```bash
xcrun notarytool store-credentials "glotera-profile" \
  --apple-id glotera.ai@gmail.com \
  --team-id 6Q3GB859VC \
  --password ocij-tdpl-azxx-zouk
```

## 上传文件进行公证
```bash
xcrun notarytool submit glotera-0.1.4.zip \
  --keychain-profile "glotera-profile" \
  --wait
```

## 查看APP公证状态
```bash
xcrun notarytool history --keychain-profile "glotera-profile"
xcrun notarytool log 38658fe3-5761-4cac-97a7-fef400849d68 --keychain-profile "glotera-profile"

 bryanzh@bma release % xcrun notarytool log eac2b237-7acb-4eae-90c7-4cdc6f7ddd95 --keychain-profile "glotera-profile"
{
  "logFormatVersion": 1,
  "jobId": "eac2b237-7acb-4eae-90c7-4cdc6f7ddd95",
  "status": "Accepted",
  "statusSummary": "Ready for distribution",
  "statusCode": 0,
  "archiveFilename": "Glotera-0.2.1.zip",
  "uploadDate": "2025-07-11T11:50:53.372Z",
  "sha256": "1e18854be2359f6da04339cc2d877c97c0716bb8e08f52f14c9042f833dbd56b",
  "ticketContents": [
    {
      "path": "Glotera-0.2.1.zip/Glotera.app/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app",
      "digestAlgorithm": "SHA-256",
      "cdhash": "f378fff9e1148eadfbb64f871395b29116810df1",
      "arch": "x86_64"
    },
    {
      "path": "Glotera-0.2.1.zip/Glotera.app/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app",
      "digestAlgorithm": "SHA-256",
      "cdhash": "d216a058872695d9a1b23e2687a79325f2e083c6",
      "arch": "arm64"
    },
    {
      "path": "Glotera-0.2.1.zip/Glotera.app/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater",
      "digestAlgorithm": "SHA-256",
      "cdhash": "f378fff9e1148eadfbb64f871395b29116810df1",
      "arch": "x86_64"
    },
    {
      "path": "Glotera-0.2.1.zip/Glotera.app/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater",
      "digestAlgorithm": "SHA-256",
      "cdhash": "d216a058872695d9a1b23e2687a79325f2e083c6",
      "arch": "arm64"
    },
    {
      "path": "Glotera-0.2.1.zip/Glotera.app/Contents/Frameworks/Sparkle.framework/Versions/Current/XPCServices/Installer.xpc",
      "digestAlgorithm": "SHA-256",
      "cdhash": "1d6f1f0c44c9423fb2772b1a197939101fd54590",
      "arch": "x86_64"
    },
    {
      "path": "Glotera-0.2.1.zip/Glotera.app/Contents/Frameworks/Sparkle.framework/Versions/Current/XPCServices/Installer.xpc",
      "digestAlgorithm": "SHA-256",
      "cdhash": "e40b63ac584986f355670aee8a971100766f2506",
      "arch": "arm64"
    },
    {
      "path": "Glotera-0.2.1.zip/Glotera.app/Contents/Frameworks/Sparkle.framework/Versions/Current",
      "digestAlgorithm": "SHA-256",
      "cdhash": "23d325be6998789efb713ea6e60995328a131149",
      "arch": "x86_64"
    },
    {
      "path": "Glotera-0.2.1.zip/Glotera.app/Contents/Frameworks/Sparkle.framework/Versions/Current",
      "digestAlgorithm": "SHA-256",
      "cdhash": "1c542021d2e9b4609aab9ae5ff28ee22499d22d6",
      "arch": "arm64"
    },
    {
      "path": "Glotera-0.2.1.zip/Glotera.app/Contents/Frameworks/Sparkle.framework/Versions/Current/Updater.app",
      "digestAlgorithm": "SHA-256",
      "cdhash": "f378fff9e1148eadfbb64f871395b29116810df1",
      "arch": "x86_64"
    },
    {
      "path": "Glotera-0.2.1.zip/Glotera.app/Contents/Frameworks/Sparkle.framework/Versions/Current/Updater.app",
      "digestAlgorithm": "SHA-256",
      "cdhash": "d216a058872695d9a1b23e2687a79325f2e083c6",
      "arch": "arm64"
    },
    {
      "path": "Glotera-0.2.1.zip/Glotera.app/Contents/Frameworks/Sparkle.framework/Versions/Current/XPCServices/Downloader.xpc",
      "digestAlgorithm": "SHA-256",
      "cdhash": "36b2921af47036611d930c8b549351e3cc3b46e2",
      "arch": "x86_64"
    },
    {
      "path": "Glotera-0.2.1.zip/Glotera.app/Contents/Frameworks/Sparkle.framework/Versions/Current/XPCServices/Downloader.xpc",
      "digestAlgorithm": "SHA-256",
      "cdhash": "afedf2133ab4e78890a3992aba95e4224877f28a",
      "arch": "arm64"
    },
    {
      "path": "Glotera-0.2.1.zip/Glotera.app",
      "digestAlgorithm": "SHA-256",
      "cdhash": "25c4a64bb9acfc77b51666054ebaa8dcbad8f35c",
      "arch": "x86_64"
    },
    {
      "path": "Glotera-0.2.1.zip/Glotera.app",
      "digestAlgorithm": "SHA-256",
      "cdhash": "25c3bce8b861978200f93d630bff2a020d6f2242",
      "arch": "arm64"
    },
    {
      "path": "Glotera-0.2.1.zip/Glotera.app/Contents/Frameworks/Sparkle.framework/Versions/Current/Autoupdate",
      "digestAlgorithm": "SHA-256",
      "cdhash": "5ee34c38058e842ccefd5289a4bbc9e1d9356447",
      "arch": "x86_64"
    },
    {
      "path": "Glotera-0.2.1.zip/Glotera.app/Contents/Frameworks/Sparkle.framework/Versions/Current/Autoupdate",
      "digestAlgorithm": "SHA-256",
      "cdhash": "b40764493457edb064f9ca7c1445a06dfc919f5a",
      "arch": "arm64"
    },
    {
      "path": "Glotera-0.2.1.zip/Glotera.app/Contents/MacOS/Glotera",
      "digestAlgorithm": "SHA-256",
      "cdhash": "25c4a64bb9acfc77b51666054ebaa8dcbad8f35c",
      "arch": "x86_64"
    },
    {
      "path": "Glotera-0.2.1.zip/Glotera.app/Contents/MacOS/Glotera",
      "digestAlgorithm": "SHA-256",
      "cdhash": "25c3bce8b861978200f93d630bff2a020d6f2242",
      "arch": "arm64"
    },
    {
      "path": "Glotera-0.2.1.zip/Glotera.app/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate",
      "digestAlgorithm": "SHA-256",
      "cdhash": "5ee34c38058e842ccefd5289a4bbc9e1d9356447",
      "arch": "x86_64"
    },
    {
      "path": "Glotera-0.2.1.zip/Glotera.app/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate",
      "digestAlgorithm": "SHA-256",
      "cdhash": "b40764493457edb064f9ca7c1445a06dfc919f5a",
      "arch": "arm64"
    },
    {
      "path": "Glotera-0.2.1.zip/Glotera.app/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle",
      "digestAlgorithm": "SHA-256",
      "cdhash": "23d325be6998789efb713ea6e60995328a131149",
      "arch": "x86_64"
    },
    {
      "path": "Glotera-0.2.1.zip/Glotera.app/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle",
      "digestAlgorithm": "SHA-256",
      "cdhash": "1c542021d2e9b4609aab9ae5ff28ee22499d22d6",
      "arch": "arm64"
    },
    {
      "path": "Glotera-0.2.1.zip/Glotera.app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader",
      "digestAlgorithm": "SHA-256",
      "cdhash": "36b2921af47036611d930c8b549351e3cc3b46e2",
      "arch": "x86_64"
    },
    {
      "path": "Glotera-0.2.1.zip/Glotera.app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader",
      "digestAlgorithm": "SHA-256",
      "cdhash": "afedf2133ab4e78890a3992aba95e4224877f28a",
      "arch": "arm64"
    },
    {
      "path": "Glotera-0.2.1.zip/Glotera.app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer",
      "digestAlgorithm": "SHA-256",
      "cdhash": "1d6f1f0c44c9423fb2772b1a197939101fd54590",
      "arch": "x86_64"
    },
    {
      "path": "Glotera-0.2.1.zip/Glotera.app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer",
      "digestAlgorithm": "SHA-256",
      "cdhash": "e40b63ac584986f355670aee8a971100766f2506",
      "arch": "arm64"
    }
  ],
  "issues": null
}
```

## 成功后注入公证信息
```bash
xcrun stapler staple /path/to/Glotera.app 
```

## 安全验证，GateKeeper是否还报错
```bash
-- 如果是app
spctl --assess --type exec -v /path/to/Glotera.app

-- 正常示例如下：
Glotera-0.2.1/Glotera.app: accepted
source=Notarized Developer ID

-- 报错示例如下：
Glotera-0.1.4/Glotera.app: rejected
source=Unnotarized Developer ID

-- 如果是dmg
spctl --assess --type open --context context:primary-signature -v /path/to/Glotera.dmg
```

## 打包成dmg
生成配置文件appdmg.json
```json
{
  "title": "Glotera Installer",
  "icon": "glotera.icns",
  "background": "background.png",
  "window": {
    "size": {
      "width": 500,
      "height": 300
    }
  },
  "contents": [
    { "x": 100, "y": 150, "type": "file", "path": "dist/Glotera.app" },
    { "x": 350, "y": 150, "type": "link", "path": "/Applications" }
  ]
}
```

进行打包：
```bash
npm install -g appdmg
appdmg appdmg.json Glotera.dmg
```
