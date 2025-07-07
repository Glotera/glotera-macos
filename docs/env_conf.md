# Environment Configuration Guide

## 概述

Glotera 桌面应用现在支持自动环境配置，可以根据编译模式自动切换本地开发和生产环境的服务器地址。

## 配置系统

### TranslatorEnvironment 结构

```swift
struct TranslatorEnvironment {
    let apiEndpoint: String       // API服务器地址
    let isProduction: Bool        // 是否为生产环境
    let timeoutInterval: TimeInterval  // 请求超时时间
    let maxRetries: Int           // 最大重试次数
}
```

### 自动环境切换

系统使用 Swift 编译条件 (`#if DEBUG`) 来自动切换环境：

- **Debug 模式 (开发环境)**：
  - API 地址：`http://localhost:1145/api/translate`
  - 超时时间：10秒（快速失败）
  - 最大重试：2次
  - 网络配置：优化本地开发体验

- **Release 模式 (生产环境)**：
  - API 地址：`https://glotera.ai/api/translate`
  - 超时时间：30秒（适应网络延迟）
  - 最大重试：3次
  - 网络配置：优化生产环境稳定性

## 使用方法

### 本地开发

1. **在 Xcode 中运行**：
   ```bash
   # 自动使用 Debug 配置，连接本地服务器
   cmd + R
   ```

2. **命令行编译开发版本**：
   ```bash
   xcodebuild -scheme desktop -configuration Debug build
   ```

### 生产发布

1. **Archive 构建**：
   ```bash
   # 在 Xcode 中: Product -> Archive
   # 自动使用 Release 配置，连接生产服务器
   ```

2. **命令行编译发布版本**：
   ```bash
   xcodebuild -scheme desktop -configuration Release build
   ```

## 环境识别

应用启动时会在日志中显示当前环境信息：

```
TranslatorClient initialized
Environment: DEVELOPMENT
API Endpoint: http://localhost:1145/api/translate
Timeout: 10.0s, Max Retries: 2
🔧 Debug mode: Using local server for fast development
```

或者：

```
TranslatorClient initialized
Environment: PRODUCTION
API Endpoint: https://glotera.ai/api/translate
Timeout: 30.0s, Max Retries: 3
🚀 Release mode: Using production server
```

## 网络配置差异

### 开发环境配置
- 更多并发连接（5个）
- 启用 HTTP 管道化
- 使用协议缓存策略
- 快速超时（10秒）

### 生产环境配置
- 单一连接以提高稳定性
- 禁用 HTTP 管道化
- 禁用缓存以确保数据新鲜度
- 延长超时（60秒）

## 配置修改

如需修改环境配置，编辑 `TranslatorClient.swift` 中的 `TranslatorEnvironment.current` 静态属性：

```swift
static let current: TranslatorEnvironment = {
    #if DEBUG
        return TranslatorEnvironment(
            apiEndpoint: "http://localhost:1145/api/translate",  // 修改本地地址
            isProduction: false,
            timeoutInterval: 10.0,  // 修改超时时间
            maxRetries: 2
        )
    #else
        return TranslatorEnvironment(
            apiEndpoint: "https://glotera.ai/api/translate",     // 修改生产地址
            isProduction: true,
            timeoutInterval: 30.0,
            maxRetries: 3
        )
    #endif
}()
```

## 调试信息

开发环境下会显示更详细的网络调试信息，包括：
- 原始数据内容（前200字符）
- 详细的流式数据处理日志
- 网络配置信息

生产环境下会减少日志输出以提高性能。

## 注意事项

1. **自动切换**：无需手动修改代码，编译时自动选择正确的环境
2. **本地服务器**：确保本地开发时服务器运行在 `localhost:1145`
3. **网络权限**：生产环境需要网络访问权限
4. **缓存清理**：切换环境后可能需要清理 Xcode 缓存

## 故障排除

### 常见问题

1. **连接本地服务器失败**：
   - 检查本地服务器是否运行在端口 1145
   - 确认防火墙设置

2. **生产环境连接超时**：
   - 检查网络连接
   - 确认 HTTPS 证书有效

3. **环境识别错误**：
   - 检查编译配置（Debug/Release）
   - 清理并重新构建项目 