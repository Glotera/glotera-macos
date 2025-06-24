## 导出app
Xcode-> Product-> Archive -> Distribute App -> Custom -> Developer ID

## 打包成zip文件
ditto -c -k --keepParent /path/to/Glotera.app glotera.zip

## 检查plist是否正确（可选）
plutil -lint Glotera-20250624/Glotera.app/Contents/Info.plist

## 上传文件进行公证
xcrun notarytool submit glotera-clean.zip \
  --keychain-profile "glotera-profile" \
  --wait

## 查看APP公证状态
xcrun notarytool history --keychain-profile "glotera-profile"

## 安全验证是否ok
spctl --assess --type exec -v glotera.zip

## 生成notarytool keychain profile，避免每次输密码
xcrun notarytool store-credentials "glotera-profile" \
  --apple-id glotera.ai@gmail.com \
  --team-id 6Q3GB859VC \
  --password ocij-tdpl-azxx-xxxx