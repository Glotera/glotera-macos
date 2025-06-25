# desktop release note

v0.1.3 - 20250625
- 增加了收集用户使用环境的信息，包括IP地址、os版本、应用版本
- 把服务端默认使用的模型放到配置文件中
- 优化了回车Interception时的性能，去掉一直执行失败的AppleScipt，加载配置时不需要每次检查文件是否变更，只有在重新保存时更新cache
- 增加了回车键是否触发自动翻译的配置，并优化代码命名从LanguageConfigXxx改为ConfigXxx
  
v0.1.2 - 20250624
- 修复飞书输入框指令翻译无效的问题
  
v0.1.1 - 20250624
- 修复AdsPower上SunBrowser输入框无法翻译的问题