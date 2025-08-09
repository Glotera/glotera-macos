# Whatsapp 应用界面DOM树结构说明

## 树结构
- 在系统语言为英文下，发现iOSContentGroup（主界面）下面有时会是5个元素
  - 左侧边栏、分隔线、会话列表、分隔线、聊天框
- 在系统语言为英文下，发现iOSContentGroup（主界面），有时会是6个元素
  - 左侧边栏、分隔线、会话列表、分隔线、聊天框顶部（包含联系人名称及视频、通话、搜索按钮）、聊天框主体部分（对话框及下面的输入框等部分）
- 在系统语言为中文下，iOSContentGroup（主界面）下面有时会是3个元素
  - 相比最上面少了分隔线的两个

> 还不知道在其它语言下是否还有更多的可能性，所以原来严格按照DOM树结果去解析，兼容性太差，只能找联系人元素块及对话框元素块这两个更小单元的特征来解析，稳定性会更好一些
- 联系人元素块的特征
  - AXGroup下面有4个子元素，第一个是AXHeading，其它3个是AXButton
  - 第一个就是联系人的，获取相应的Description即可
- 对话框元素块的特征
  - AXGroup下面有5或6个子元素，第一个是AXGroup，其中一个是AXTextArea，其它的都是AXButton（移至最新消息有时会有，出现在第2位）
  - 第一个AXGroup中的子元素即是类型AXGroup聊天消息列表，解析其子元素（只有一个）选取role为AXGenericElement的即为文本消息

## 消息格式
- 消息内容通过‎进行分隔，一般情况下接收到的消息为两部分，发送的消息为三部分，最后多了一个消息状态
  - 第一部分为消息主体，第二部分为发送人相关，第三部分为发送状态
    - 第一部分消息主体几个部分是以逗号(,)进行分隔
      - 第一部分为消息类型，是接收到的消息还是发送的消息
      - 最后一部分为日期及时间，不同语言格式还不一样
        - 中文：11:37，年8月9日11:37，2025年8月9日11:37
        - 英文：at23:00，Augest3,at23:00
        - 还没有找到带年份的情况是啥
- 如果是三部分即为发送的，如果是两部分需要进一步判断
  - 如果发送的消息没有状态，也是两部分

- 中文示例
  - 单聊
    - ‎消息, Vuelva a probar si la pantalla sigue colgada en estado de salvapantallas, 11:11, ‎从Carlos收到
    - ‎你的消息, Este problema ya ha sido solucionado., 11:37, ‎已发送到Carlos, ‎已读
  - 群聊
    - ‎Carlos发来的消息, 测试一下群聊, 16:50, ‎在Glotera测试群收到
    - ‎你的消息, 有什么不一样的地方, 16:51, ‎发送到Glotera测试群, ‎已发送
- 英文示例
  - 单聊
    - ‎message, 可以触发 focus, July30,at16:20, ‎Received from Princeton
    - ‎Your message, Test again, please ignore it, August3,at23:00, ‎Sent to Princeton, ‎Sent
  - 群聊
    - 