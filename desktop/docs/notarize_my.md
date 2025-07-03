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
xcrun notarytool log adf31c27-29ce-440e-b772-1d2edc45bc56 --keychain-profile "glotera-profile"
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

-- 报错示例如下：
Glotera-0.1.4/Glotera.app: rejected
source=Unnotarized Developer ID

-- 如果是dmg
spctl --assess --type open --context context:primary-signature -v /path/to/Glotera.dmg
```
