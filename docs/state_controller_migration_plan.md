# StateController 迁移计划

更新时间：2026-08-19

## 处理清单

- [x] 清理无引用控制器和已失效的 `StateController.find` 调用
- [x] 用 `blockingKeywordRevisionProvider` 替换 `SliverGridComicsController`
- [ ] 迁移简单页面加载控制器
- [ ] 迁移评论与回复控制器
- [ ] 重构 `StateWithController` 刷新机制
- [ ] 迁移窗口、搜索和收藏页全局状态
- [ ] 删除旧 `state_controller.dart` 体系

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

## 验证记录

- `fvm dart format`：通过，修改文件无需格式调整。
- 修改文件范围的 `fvm dart analyze`：通过，仅有原有的弃用提示。
- 全项目 `fvm flutter analyze`：当前报告 610 个分析问题，命令整体返回非零；本次修改文件范围未出现错误或警告，仅有原有弃用提示。

## 后续约定

每完成一个阶段，更新本文件对应的复选框、完成内容和验证记录。
