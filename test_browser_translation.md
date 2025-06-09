# 浏览器翻译功能测试指南

## 🧪 测试步骤

### 1. 启动应用
```bash
cd /Users/bryanzh/Workspace/glotera/desktop
./build/Build/Products/Release/desktop.app/Contents/MacOS/desktop
```

### 2. 测试场景

#### 场景A：单行文本翻译
1. 打开Chrome浏览器
2. 访问Gmail或任何有输入框的网站
3. 在输入框中输入：`你好世界 @en`
4. 按空格键
5. 观察是否自动翻译为：`Hello world`

#### 场景B：多行文本翻译
1. 在输入框中输入：
   ```
   第一行文本
   第二行文本
   第三行文本 @en
   ```
2. 按空格键
3. 观察是否完整翻译所有行

#### 场景C：不同浏览器测试
- Chrome: `com.google.Chrome`
- Safari: `com.apple.Safari`
- Edge: `com.microsoft.edgemac`

### 3. 调试信息查看

在终端中查看详细日志：
- `[LOG] Detected browser environment: Chrome (com.google.Chrome)`
- `[LOG] Got content via AppleScript: XX chars`
- `[LOG] Using web content (only available): XX chars`
- `[LOG] Trigger found using pattern X: text='...', lang='en'`

### 4. 常见问题排查

#### 问题1：无法检测到浏览器
- 检查日志是否显示 `Detected browser environment`
- 确认浏览器在支持列表中

#### 问题2：无法获取输入框内容
- 检查是否显示 `Got content via AppleScript` 或 `Got content via standard method`
- 尝试点击输入框确保焦点正确

#### 问题3：多行内容只翻译最后一行
- 检查日志中的 `Content length` 和 `Newlines found at positions`
- 确认正则表达式是否正确匹配

### 5. 支持的网站测试

#### 标准输入框
- Gmail 撰写邮件
- Google搜索框
- Twitter发推框

#### ContentEditable元素
- Notion页面编辑
- Telegram Web聊天框
- WhatsApp Web消息框

### 6. 预期行为

✅ **正常情况**：
- 自动检测浏览器环境
- 获取完整输入内容（包括换行符）
- 正确提取触发标记和原文
- 调用翻译API
- 替换原文为翻译结果

❌ **异常情况**：
- 无法检测浏览器：检查bundle ID
- 内容获取失败：检查AppleScript权限
- 翻译不触发：检查触发标记格式
- 替换失败：检查输入框焦点

## 🔧 修复验证

本次修复主要解决了以下问题：

1. **多行文本支持**：
   - 添加了 `dotMatchesLineSeparators` 正则选项
   - 增加了内联修饰符 `(?s)` 模式
   - 改进了换行符调试信息

2. **浏览器内容获取优化**：
   - 同时使用标准方法和Web方法
   - 智能选择最佳结果（更长或唯一可用）
   - 避免重复调用AppleScript

3. **调试信息增强**：
   - 显示内容长度和换行符位置
   - 区分不同获取方法的结果
   - 提供详细的选择逻辑日志

## 📝 测试记录

请在测试时记录：
- [ ] 单行文本翻译是否正常
- [ ] 多行文本翻译是否完整
- [ ] 不同浏览器是否都支持
- [ ] 调试日志是否正确显示
- [ ] 性能是否有明显影响 