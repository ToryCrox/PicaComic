# StateController 迁移计划

更新时间：2026-10-17

## 处理清单

- [x] 清理无引用控制器和已失效的 `StateController.find` 调用
- [x] 用 `blockingKeywordRevisionProvider` 替换 `SliverGridComicsController`
- [x] 迁移简单页面加载控制器
- [x] 迁移评论与回复控制器（此前已完成，按当前代码同步记录）
- [x] 重构 `StateWithController` 刷新机制
- [x] 迁移窗口、搜索和收藏页全局状态
- [x] 删除旧 `state_controller.dart` 体系

## 已完成项

### 1. 清理无引用控制器和失效调用

- 删除未被引用的 `CommentLogic`。
- 删除未被引用的 `SetJmComicsOrderController`。
- 删除 `MePage` 已不再使用的 `me page` / `me_page` 静态查找调用。
- 将 EHentai 搜索缓存清理从旧的 `StateController` 标签查询改为查询当前
  `comicListPageLogicProvider` 是否仍然存在。

### 2. 替换 `SliverGridComicsController`

- 删除 `SliverGridComicsController`。
- 将 `SliverGridComics` 改为监听现有的 `blockingKeywordRevisionProvider`。
- 删除 `comic_tile.dart` 中遍历所有旧控制器的刷新逻辑。

### 3. 迁移简单页面加载控制器

- `AccountsPageLogic` 改为 autoDispose Riverpod Notifier。
- `CollectionPageLogic` 改为 autoDispose AsyncNotifier，页面不再在 `build` 中直接发起请求。
- `HitomiHomePageLogic` 改为带 URL family 参数的 autoDispose Notifier，保留分页加载、重试和请求代际保护。
- 三个页面均改用 `ConsumerWidget`，并生成对应的 Riverpod 代码。
- 修复 Picacg 推荐接口仅返回一组集合时的越界异常，并避免错误态重复显示返回栏。

### 4. 完成剩余调用迁移

- 搜索页使用 `preSearchProvider(session)` 自动释放 Notifier；来源、筛选、语言、建议与历史展开状态按页面实例隔离。输入与焦点控制器由 Widget 释放，局部 Consumer 按需监听。
- 搜索历史、标签收藏和屏蔽词经 `userLibraryProvider` 观察不可变快照；旧网络保存、导入和数据替换入口发布独立变更通知，不创建全局 ProviderContainer。
- 删除五个网络模块中查找 `PreSearchController` 的七处界面刷新调用。搜索页的删除、清空操作经仓库串行保存，保存失败保留界面数据并提示。
- 屏蔽词页复用已有仓库与操作 Notifier，补齐删除和说明关闭入口；添加、删除通知漫画列表重新过滤。排序和弹窗草稿保留为局部状态，避免重新添加后引用旧列表。
- 探索页按父页面实例、来源和标题隔离刷新信号；多分区页面先显示缓存再请求网络，刷新代际和自动释放保护迟到结果。分页保留现有列表会话，混合页面按刷新版本隔离请求，自定义页面按版本重建。
- 窗口栏使用应用级 `windowFrameProvider`；侧栏动画和关闭回调由 Widget 管理。阅读器使用当前 ProviderScope 的窗口 Notifier，退出时使用提前保存的依赖延迟恢复，避免卸载时访问 WidgetRef。
- 导航留白直接从当前导航布局派生，以 InheritedWidget 向根页面传递；路由通知在帧结束后更新布局，不在 build 中修改 Provider。
- 删除 `state_controller.dart` 和 `app.dart` 中的旧导出，Dart 源码及测试不再依赖旧体系。既有评论、回复、漫画收藏迁移不重复改造。

### 2026-10-17 验证

- 代码生成和修改文件格式化完成，生成文件继续按仓库规则忽略。
- 最终全项目 `fvm flutter test --no-pub --concurrency=2`：326 项通过、1 项跳过。
- 默认并发的复核中曾出现一个设置测试进程加载前连接断开；该文件单独复核 4 项通过，随后降低并发的完整测试全部通过。
- 另外补充验证搜索页输入、ID 建议、清空后保留筛选与资源释放，以及屏蔽词弹窗添加、删除后重新添加，两项 Widget 测试分别通过。
- 回归覆盖搜索实例隔离、不可变快照、自动释放、探索缓存与迟到请求、来源隔离、窗口主题与显隐、保存通知与回滚、导航路由与宽度变化，以及阅读器退出保存。
- `fvm flutter analyze --no-pub`：0 个错误；全项目仍报告 40 个警告、421 条提示。修改文件没有错误或警告，保留其原有弃用等提示。
- `git diff --check` 通过；全仓库 Dart 搜索确认旧状态管理 API 无残留。
- 真实漫画源账号请求及桌面窗口交互仍需设备回归。

## 早期阶段验证记录

- `fvm dart format`：通过，修改文件无需格式调整。
- 修改文件范围的 `fvm dart analyze`：通过，仅有原有的弃用提示。
- 第三项修改文件范围的 `fvm dart analyze`：通过，`No issues found!`。
- Picacg 推荐修复涉及文件的 `fvm dart analyze`：通过，保留网络方法中的 16 条原有提示。
- 全项目 `fvm flutter test --reporter compact`：通过，72 个测试全部通过。
- 全项目 `fvm flutter analyze`：当前报告 610 个分析问题，命令整体返回非零；本次修改文件范围未出现错误或警告，仅有原有弃用提示。

## 后续约定

每完成一个阶段，更新本文件对应的复选框、完成内容和验证记录。
