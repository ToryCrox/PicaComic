# 历史与收藏状态管理

历史、漫画收藏夹、目录收藏、网络收藏和图片收藏统一使用 Riverpod。数据库表结构、导出 JSON、WebDAV 备份及上次收藏位置编码保持兼容。

## 状态与职责

- `HistoryManager`、`LocalHistoryManager`、`LocalFavoritesManager` 只适配存储，通过仓库 Provider 提供应用级实例。启动、导入及 WebDAV 仍可直接使用同一适配，成功写入后必须发布变更。
- `DirectoryFavoritesRepository` 独立管理目录收藏，复用下载数据库，不依赖下载任务队列。
- 单次查询使用 `AsyncValue<T>` 表达查询中、数据和错误；空值代表没有记录。关联业务字段使用不可变 State：`LocalFavoritesState`、`FavoritesSessionState`、`NetworkFavoriteState`、`FavoriteJobState`、`ReaderLayoutState`。
- Notifier 提供可等待的写入方法。列表查询错误与操作错误分别保存，写入失败不替换现有数据。Widget 只保留输入、未提交勾选、滚动与动画控制器。
- 多选以 `(type, target)` 保存，元数据更新不会改变身份；目录用完整路径，网络列表按来源、收藏夹与会话隔离。
- 新 SQL、数据库行映射统一使用字段常量。字段常量值不变更；外部 JSON 的 `coverPath` 与数据库的 `cover_path` 保持原有区别。

## 查询和生命周期

历史卡片使用 `historyEntryProvider(target)` 或 `localHistoryEntryProvider(path)`，同一微任务内合并数据库查询。`BatchLookup` 缓存空值但不缓存错误，并通过版本校验拒绝写入、删除或清空前的旧结果。列表、最近阅读及统计订阅仓库变更。

仓库 Provider 保持存活；详情、搜索、分页和页面会话按页面自动释放。阅读器在会话建立时取得保存服务，每次保存立即复制阅读进度，后台及退出保存不再访问已卸载 Widget 的 Ref。更新列表数据保持当前滚动控制器。

漫画收藏查询按目录、作品身份和封面 URL 派生。`FavoriteSearchInput` 输入等待 300 毫秒，提交立即查询；关键词通过 family 隔离，旧查询不能覆盖新关键词。所有收藏写操作经 `LocalFavorites`，多夹归属与排序采用事务，重命名和排序保留同步配置。

## 网络与批量任务

网络操作由 `NetworkFavoriteActions` 执行，保留漫画源原有回调及参数；成功后发布统一变更。登录、退出和来源重载增加会话版本，旧会话的结果被忽略。E-Hentai 每次浏览与导入拥有独立分页游标。

`FavoriteJob(folder)` 对同一目标复用正在运行的任务，发布阶段、进度、成功数、失败数和取消状态：

1. 导入、同步先完整抓取；抓取失败或取消时不创建目录、不写入、不修改同步时间。
2. 抓取成功后用单个事务提交，提交阶段禁止取消，写入失败整体回滚。
3. 信息更新和失效检查逐条提交；取消后停止后续处理，并忽略正在请求的迟到结果。普通网络错误不会标记失效。
4. 逐条任务完成或取消时合并已经成功的变更通知和上传请求。导入提交后准备封面，封面及上传失败不撤销已经保存的收藏。

## 设置边界与验证

界面主设置使用 `appSettingProvider`、`appSettingsProvider`；操作通过 Notifier，服务注入 `AppSettingsRepository` 或配置。导航位置和阅读器首页布局分别由存储适配保持原有隐式格式。屏蔽词与标签收藏入口使用 `UserLibraryPreferencesActions`。不创建全局 ProviderContainer，不跨 isolate 传递 Ref。

图片收藏继续沿用 `image_favorites_providers.dart`，与历史共用数据库的初始化和清理保持兼容。

验证命令使用项目 `.fvmrc` 锁定 SDK：代码生成、`fvm flutter test`、`fvm flutter analyze`。生成的 `.g.dart` 按仓库规则不提交。相关测试覆盖持久化、事务、取消、分页会话、搜索、界面联动、历史快照与退出保存；真实账号网络、桌面右键和移动端长按仍需设备回归。
