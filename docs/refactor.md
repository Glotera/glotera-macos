# Glotera 代码重构方案

## 概述

本文档分析了 `InputMonitor.swift` 和 `AXController.swift` 两个核心文件的代码结构问题，并提供了在不改变任何业务逻辑实现情况下的重构方案。

## 当前代码问题分析

### 1. 文件过大问题

- **AXController.swift**: 3957行，包含多个职责
- **InputMonitor.swift**: 1334行，功能混杂

### 2. 职责混乱问题

#### AXController.swift 包含的职责：
- AppleScript 模板缓存管理
- 触发器模式缓存
- JavaScript 模式缓存
- 内存管理统计
- 应用检测
- 触发器检测
- 内容获取和处理
- 输入替换
- 剪贴板操作
- 键盘事件模拟
- 文本编辑器支持
- Web环境支持
- Discord特殊处理
- 测试方法

#### InputMonitor.swift 包含的职责：
- 事件监听回调
- 空格键处理
- 回车键拦截
- 应用检测缓存
- 翻译流程管理
- 微信特殊处理
- 健康检查
- 测试方法

### 3. 代码重复问题

- 应用检测逻辑在多个地方重复
- 剪贴板操作代码重复
- 键盘事件模拟代码重复
- 测试方法分散

### 4. 可维护性问题

- 单个文件过大，难以定位问题
- 方法过长，逻辑复杂
- 依赖关系不清晰
- 测试困难

## 重构方案

### 第一阶段：职责分离

#### 1.1 创建 AppleScript 管理模块

**新文件**: `desktop/desktop/AppleScriptManager.swift`

```swift
// 从 AXController 中提取
- AppleScriptTemplateCache 类
- CompiledAppleScript 结构体
- AppleScript 测试方法
- AppleScript 执行逻辑
```

#### 1.2 创建触发器管理模块

**新文件**: `desktop/desktop/TriggerManager.swift`

```swift
// 从 AXController 中提取
- TriggerPatternCache 类
- CompiledTriggerPattern 结构体
- 触发器检测逻辑
- 模式生成逻辑
```

#### 1.3 创建 JavaScript 管理模块

**新文件**: `desktop/desktop/JavaScriptManager.swift`

```swift
// 从 AXController 中提取
- JavaScriptPatternCache 类
- JavaScript 模式生成
- 浏览器特定 JavaScript 代码
```

#### 1.4 创建内容处理模块

**新文件**: `desktop/desktop/ContentProcessor.swift`

```swift
// 从 AXController 中提取
- 内容预处理逻辑
- 光标位置检测
- 内容清理逻辑
- 触发器移除逻辑
```

#### 1.5 创建输入操作模块

**新文件**: `desktop/desktop/InputOperator.swift`

```swift
// 从 AXController 中提取
- 输入替换逻辑
- 剪贴板操作
- 键盘事件模拟
- 特殊应用处理（Discord、微信等）
```

#### 1.6 创建事件处理模块

**新文件**: `desktop/desktop/EventHandler.swift`

```swift
// 从 InputMonitor 中提取
- 空格键处理逻辑
- 回车键拦截逻辑
- 双击检测逻辑
- 事件统计
```

#### 1.7 创建应用检测模块

**新文件**: `desktop/desktop/AppDetector.swift`

```swift
// 从多个文件中提取
- 应用类型检测
- 应用缓存管理
- 特殊应用识别（Discord、微信、浏览器等）
```

### 第二阶段：接口重构

#### 2.1 创建统一的服务接口

**新文件**: `desktop/desktop/Services/TranslationService.swift`

```swift
protocol TranslationServiceProtocol {
    func detectTrigger() -> (text: String, lang: String)?
    func replaceInput(with text: String, completion: @escaping () -> Void)
    func getCurrentContent() -> String?
    func isWebEnvironment() -> Bool
    func isSpecialApp() -> Bool
}
```

#### 2.2 创建事件服务接口

**新文件**: `desktop/desktop/Services/EventService.swift`

```swift
protocol EventServiceProtocol {
    func handleSpaceKey()
    func handleEnterKey()
    func shouldInterceptEnter() -> Bool
    func getEventStatistics() -> EventStatistics
}
```

### 第三阶段：测试模块分离

#### 3.1 创建测试工具模块

**新文件**: `desktop/desktop/Testing/TestUtils.swift`

```swift
// 从两个文件中提取所有测试方法
- AppleScript 测试
- 触发器测试
- 应用检测测试
- 事件处理测试
- 性能测试
```

### 第四阶段：配置管理优化

#### 4.1 创建配置服务

**新文件**: `desktop/desktop/Services/ConfigurationService.swift`

```swift
// 统一管理所有配置相关逻辑
- 触发器配置
- 应用配置
- 性能配置
- 缓存配置
```

## 重构后的文件结构

```
desktop/desktop/
├── Core/
│   ├── AXController.swift (重构后，只保留核心协调逻辑)
│   └── InputMonitor.swift (重构后，只保留事件监听协调)
├── Services/
│   ├── TranslationService.swift
│   ├── EventService.swift
│   ├── ConfigurationService.swift
│   └── AppleScriptManager.swift
├── Managers/
│   ├── TriggerManager.swift
│   ├── JavaScriptManager.swift
│   ├── ContentProcessor.swift
│   ├── InputOperator.swift
│   ├── EventHandler.swift
│   └── AppDetector.swift
├── Testing/
│   └── TestUtils.swift
└── Models/
    ├── TriggerPattern.swift
    ├── AppInfo.swift
    └── EventStatistics.swift
```

## 重构实施步骤

### 步骤1：创建新模块（不删除原代码）

1. 创建所有新的模块文件
2. 将相关代码从原文件复制到新模块
3. 确保新模块可以独立编译

### 步骤2：逐步迁移依赖

1. 修改 AXController 和 InputMonitor 使用新模块
2. 保持原有接口不变
3. 逐步减少原文件中的代码

### 步骤3：接口统一

1. 实现统一的服务接口
2. 重构调用方使用新接口
3. 确保向后兼容

### 步骤4：清理和优化

1. 删除原文件中的重复代码
2. 优化模块间的依赖关系
3. 添加适当的文档和注释

## 重构收益

### 1. 可维护性提升

- 单个文件大小控制在500行以内
- 职责清晰，易于定位问题
- 模块化设计，便于单元测试

### 2. 可扩展性提升

- 新功能可以独立模块开发
- 接口标准化，便于扩展
- 依赖关系清晰

### 3. 性能优化机会

- 模块化后可以独立优化
- 缓存策略可以统一管理
- 内存使用更加高效

### 4. 开发效率提升

- 代码复用率提高
- 测试覆盖更容易
- 调试更加便捷

## 风险控制

### 1. 向后兼容

- 保持所有公共接口不变
- 分阶段实施，确保每个阶段都能正常工作
- 充分的回归测试

### 2. 性能保证

- 重构过程中持续监控性能
- 确保新模块不会引入性能问题
- 保持原有的缓存策略

### 3. 功能完整性

- 确保所有现有功能都能正常工作
- 特殊应用的处理逻辑保持不变
- 错误处理机制保持一致

## 实施时间表

### 第一周：基础模块创建
- 创建所有新模块文件
- 复制相关代码到新模块
- 确保编译通过

### 第二周：接口重构
- 实现统一的服务接口
- 修改调用方使用新接口
- 进行基础测试

### 第三周：依赖迁移
- 逐步迁移 AXController 和 InputMonitor
- 删除重复代码
- 进行集成测试

### 第四周：优化和清理
- 性能优化
- 代码清理
- 文档完善
- 最终测试

## 总结

通过这个重构方案，我们可以将两个超大文件拆分成多个职责清晰的小模块，显著提升代码的可维护性、可扩展性和开发效率。重构过程中保持所有业务逻辑不变，确保系统的稳定性和可靠性。 