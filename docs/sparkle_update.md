# Sparkle使用指南

## 使用sparkle自动更新安装包注意事项
- 需要在Xcode中 File-> Add Package Dependencies 中将sparkle最新的包配置进去
- 在target -> desktop -> Frameworks,Libraries 中也增加引用
- 必须使用sparkle发行包中的/bin/generate_keys命令生成eddsa公私钥
  - 然后将公钥配置到info.plist文件中，否则可能会出现公钥decode失败
  - 私钥不要上传到git库，妥善保管，在打包时需要用私钥进行签名
- sparkle在检查版本是否要更新时，比较的版本是bundleVersion
  - 对应服务端获appcast.xml中的 sparkle:version
  - Xcode general UI中的build, Build Settings中的 Current Project Version，info.plist中的CFBundleVersion
  - 我们看到0.2.x这样的版本号对应appcast.xml中的 sparkle:shortVersionString，Xcode general UI中的version，Build Settings中的Short Marketing Version， info.plist中的CFBundleShortVersionString
  - 0.2.x 这个一般是展示给用户看的，所以也叫MARKTETING_VERSION
  - Xcode中general UI中配置的优先级要高于info.plist文件中配置的，编译后会覆盖
  - Xcode中general UI中修改好之后，经常不会直接生效，需要重启一个Xcode  

## sparkle签名
- 在打包成zip文件后，执行以下命令进行签名：
```bash
./Sparkle-2.7.1/bin/sign_update Glotera-0.1.5.zip
```
- 把生成的Signature配置到数据库表app_version中的dsa_signature字段中
- 最终生成在appcast.xml中的sparkle:edSignature标签中
```xml
 <enclosure url="https://glotera.ai/resources/download/glotera-0.1.5.zip"
                       sparkle:version="2025063001"
                       sparkle:shortVersionString="0.1.5"
                       length="15728640"
                       type="application/octet-stream"
                       sparkle:edSignature="xxxxx" />
```