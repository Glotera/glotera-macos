
## 使用sparkle自动更新安装包注意事项
- 需要在Xcode中 File-> Add Package Dependencies 中将sparkle最新的包配置进去
- 在target -> desktop -> Frameworks,Libraries 中也增加引用
- 必须使用sparkle发行包中的/bin/generate_keys命令生成公私钥，然后半公钥配置到info.plist文件中，否则可能会把公钥decode失败
- sparkle在检查版本是否要更新时，是从服务端获取appcast.xml中的 sparkle:version 来比较，而不是sparkle:shortVersionString，所以在Info.plist中需要配置version，一定是一个整数，越新的版本整数越数，这样在进行比较的时候才知道是否需要更新，shortVersionString只是用户展示用的  