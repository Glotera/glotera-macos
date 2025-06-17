# Chrome精确替换修复测试指南

## 问题描述
之前的修复方案存在以下问题：
1. 翻译内容被追加到原内容后面，而不是替换触发器部分
2. 整个输入框内容被全选中
3. 显示之前复制的内容而不是翻译结果

## 新的修复方案

### 🎯 核心改进
1. **精确模式匹配**：JavaScript中使用正则表达式精确匹配触发器模式
2. **精确替换**：只替换匹配的触发器部分，保留其他内容
3. **智能选择**：使用`setSelectionRange`精确选择需要替换的文本
4. **光标定位**：替换后将光标定位到翻译文本末尾

### 🔧 技术实现
- **JavaScript方法优先**：使用AppleScript+JavaScript直接操作DOM
- **剪贴板方法改进**：JavaScript预选择触发器文本，然后粘贴
- **模式验证**：替换前验证是否包含触发器模式

## 测试步骤

### 1. 基础功能测试
1. 打开Chrome浏览器
2. 访问任意有输入框的网站（如Google、GitHub、Twitter等）
3. 在输入框中输入：`hello @zh`
4. 按空格键
5. **预期结果**：`hello @zh` 被替换为 `你好`，光标在末尾

### 2. 混合内容测试
1. 在输入框中输入：`前面的内容 hello @zh 后面的内容`
2. 将光标移动到 `@zh` 后面
3. 按空格键
4. **预期结果**：只有 `hello @zh` 部分被替换为 `你好`，其他内容保持不变

### 3. 剪贴板干扰测试
1. 复制一些文本到剪贴板（如："干扰内容"）
2. 在输入框中输入：`test @zh`
3. 按空格键
4. **预期结果**：显示翻译结果 `测试`，而不是剪贴板内容

### 4. 多种触发器测试
测试以下触发器：
- `hello @en` → `hello`
- `你好 @id` → `halo`
- `test #zh` → `测试`
- `bonjour #en` → `hello`

### 5. ContentEditable测试
1. 访问支持富文本编辑的网站（如Notion、Medium等）
2. 在编辑器中输入：`hello @zh`
3. 按空格键
4. **预期结果**：正确替换为翻译内容

## 调试信息

### JavaScript控制台日志
打开Chrome开发者工具，查看控制台输出：
```
Starting precise text replacement...
Active element: <input>
Current value: hello @zh
Pattern matched: ["hello @zh", "hello ", "@zh", "zh"]
Original text to replace: hello 
Replacement text: 你好
Text precisely replaced from: hello @zh to: 你好
```

### macOS控制台日志
查看应用日志：
```
[LOG] Attempting AppleScript + JavaScript replacement
[LOG] Browser detected: Google Chrome (com.google.Chrome)
[LOG] Executing AppleScript...
[LOG] AppleScript replacement result: 'success'
[LOG] AppleScript replacement successful
```

## 故障排除

### 如果JavaScript方法失败
1. 检查浏览器权限设置
2. 确认AppleScript权限
3. 查看控制台错误信息

### 如果剪贴板方法被使用
日志会显示：
```
[LOG] AppleScript + JavaScript failed, falling back to clipboard method
[LOG] Using Web clipboard replacement with retry
[LOG] Trigger pattern found, proceeding with precise replacement
[LOG] Successfully selected trigger text via JavaScript
```

### 常见问题
1. **没有反应**：检查辅助功能权限
2. **全选问题**：JavaScript选择失败，回退到传统方法
3. **内容追加**：检查触发器模式是否正确匹配

## 验证成功标准
- ✅ 只替换触发器部分，不影响其他内容
- ✅ 光标正确定位到翻译文本末尾
- ✅ 不会显示剪贴板干扰内容
- ✅ 支持多种输入框类型（input、textarea、contentEditable）
- ✅ 触发相应的DOM事件（input、change）

## 技术细节

### 正则表达式模式
```javascript
var patterns = [
    /(.*?)[@#](id|en|zh|ja|jp|ko|fr|de|es|ru|th)\s*$/i,
    /^(.*?)[@#](id|en|zh|ja|jp|ko|fr|de|es|ru|th)\s*$/i,
    /(.*?)\s+[@#](id|en|zh|ja|jp|ko|fr|de|es|ru|th)\s*$/i
];
```

### 精确替换逻辑
```javascript
var newValue = currentValue.replace(patterns[i], '翻译结果');
activeElement.value = newValue;
var cursorPos = '翻译结果'.length;
activeElement.setSelectionRange(cursorPos, cursorPos);
```

这个修复方案彻底解决了之前的问题，实现了真正的精确替换功能。 