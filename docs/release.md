# desktop release note

v0.2.0 - 20250707
- 增加登陆功能，支持Email和Google
- 服务端增加token校验, 非登陆用户禁止使用使用
- 针对不同类型的用户，实现配额的检查
- 增加Sparkle自动更新机制
- 进行性能优化，减少应用卡死，减少资源占用，提升用户体验
- 修复Apple Mail中trigger无法触发翻译的问题
- 增加pricing页面
- 增加Blog功能及2篇文章

v0.1.5 - 20250629
- 增加了User Guide

v0.1.4 - 20250626
- 增加了api.glotera.ai的专用域名，和走Cloudflare代理的静态网站分开，减少性能损耗
- 回车键自动翻译只限于聊天应用，非聊天应用禁用，防止有性能问题影响用户体验
- 增加了Developer ID Appplication的签名证书，用于公证和发布应用，避免GateKeeper的拦截

v0.1.3 - 20250625
- 增加了收集用户使用环境的信息，包括IP地址、os版本、应用版本
- 把服务端默认使用的模型放到配置文件中
- 优化了回车Interception时的性能，去掉一直执行失败的AppleScipt，加载配置时不需要每次检查文件是否变更，只有在重新保存时更新cache
- 增加了回车键是否触发自动翻译的配置，并优化代码命名从LanguageConfigXxx改为ConfigXxx
  
v0.1.2 - 20250624
- 修复飞书输入框指令翻译无效的问题
  
v0.1.1 - 20250624
- 修复AdsPower上SunBrowser输入框无法翻译的问题