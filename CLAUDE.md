# CLAUDE.md

本文件为 Claude Code (claude.ai/code) 在此仓库中工作时提供指导。

## 常用开发命令

```bash
# 获取依赖
flutter pub get

# 调试模式运行
flutter run
flutter run -d windows
flutter run -d android

# 构建发布版本
flutter build windows
flutter build apk
flutter build ios

# 代码分析
flutter analyze

# 运行测试
flutter test
```

Windows 部署: `build_win.bat` 将构建产物复制到 Program Files。

## 架构概览

Pica Comic 是一个使用**插件式架构**的多源漫画阅读器，每个漫画源实现统一的接口。

### 目录结构
```
lib/
├── base.dart              # Appdata 单例（全局设置、历史记录）
├── init.dart              # 应用初始化
├── main.dart              # 入口文件
├── comic_source/          # 漫画源抽象层
├── network/               # 每个源的网络实现
├── pages/                 # UI 页面
├── foundation/            # 状态管理、工具类
├── components/            # 可复用组件
└── tools/                 # 辅助函数
```

### 核心模式：ComicSource 接口

**关键文件**: [lib/comic_source/comic_source.dart](lib/comic_source/comic_source.dart)

每个漫画源（picacg、ehentai、jm、hitomi、htmanga、nhentai、kemono）都实现 `ComicSource`：

```dart
ComicSource {
  name, key                      // 身份标识
  account: AccountConfig?        // 登录/登出
  categoryData: CategoryData?    // 分类浏览
  favoriteData: FavoriteData?    // 收藏管理
  explorePages: List<ExplorePageData>  // 发现页面
  searchPageData: SearchPageData?      // 搜索
  loadComicInfo: LoadComicFunc?        // 获取漫画详情
  loadComicPages: LoadComicPagesFunc?  // 获取页面 URL
  data: Map<String, dynamic>     // 持久化源数据
}
```

**源注册**: `ComicSource.sources` 保存所有活跃的源
- 内置源: 7 个硬编码源
- 自定义源: 从 `${App.dataPath}/comic_source/*.js` 加载的 JS 扩展

### 网络层

每个源在 `lib/network/` 下有自己的网络模块：
- `picacg_network/`, `eh_network/`, `jm_network/`, `hitomi_network/`, `htmanga_network/`, `nhentai_network/`

**响应模式**: 所有网络调用返回 `Res<T>`：
```dart
Res<T> {
  _data: T?           // 成功数据
  errorMessage: String?  // 错误信息（如果有）
  subData: dynamic    // 额外数据（如 maxPage）
}
```

### 状态管理

**关键文件**: [lib/foundation/state_controller.dart](lib/foundation/state_controller.dart)

使用服务定位器 + 可观察模式：
```dart
StateController.put<T>(controller)  // 注册
StateController.find<T>()           // 检索
controller.update()                 // 通知订阅者
```

`StateBuilder` widget 将控制器绑定到 UI，在更新时触发重建。

### 阅读器系统

**位置**: [lib/pages/reader/](lib/pages/reader/)

**ReadingData** (抽象基类) - 定义每个源如何加载页面：
```dart
abstract class ReadingData {
  Stream<Res<List<String>>> loadEp(int ep)  // 加载页面 URL
  Stream<DownloadProgress> loadImage(ep, page, url)  // 带进度的流
  ImageProvider createImageProvider(ep, page, url)
}
```

**ComicReadingPageLogic** ([reading_logic.dart](lib/pages/reader/reading_logic.dart)) - 主控制器：
- `PageController` 用于逐页模式
- `ItemScrollController` 用于连续滚动模式
- 每个图片的 `PhotoViewController` 用于缩放

阅读模式: 逐页、连续垂直、双页 spread。

### 数据持久化

| 数据 | 存储 | 位置 |
|------|------|------|
| 设置 | JSON + SharedPreferences | `${App.dataPath}/settings` |
| 历史记录 | SQLite | `history` 表 |
| 下载 | 文件 + SQLite | `${App.dataPath}/downloads/` |
| 源数据 | 每个源的 JSON | `comic_source/{key}.data` |
| 图片缓存 | 磁盘 LRU | 由 `DiskCache` 管理 |

### 数据流：加载漫画

1. 用户点击漫画 → 使用 `sourceKey` + `id` 导航
2. `ComicSource.find(sourceKey)` → 获取源
3. `source.loadComicInfo(id)` → 获取 `ComicInfoData`
4. 用户选择章节 → 创建 `ReadingData` 子类
5. `readingData.loadEp(ep)` → 图片 URL 流
6. `readingData.loadImage()` → `Stream<DownloadProgress>`
7. `ImageProvider` 渲染到 UI

### 关键设计模式

- **源无关 UI**: 所有 UI 代码使用 `ComicSource` 接口，而非特定源
- **基于流的加载**: 图片加载返回流以显示进度 UI 和支持取消
- **延迟初始化**: 源和数据按需加载
- **双重收藏夹**: 网络收藏夹（来自源 API）+ 本地 SQLite 收藏夹
- **配置驱动页面**: 分类/搜索 UI 从 `*Data` 配置构建，而非硬编码

### 扩展系统

**文件**: [lib/comic_source/parser.dart](lib/comic_source/parser.dart)

通过 JavaScript (QuickJS 引擎) 实现自定义源：
- 从 `${App.dataPath}/comic_source/*.js` 加载
- 实现相同的 `ComicSource` 接口
- 与内置源无缝集成

## 平台说明

- Flutter 3.35.7，多个 fork 的依赖
- 主要平台: Android；也支持 Windows、iOS、macOS
- 桌面端: 通过 `window_manager` 进行窗口管理
- 使用 `event_bus` 进行跨组件通信
- 使用 `flutter_riverpod` 进行部分状态管理
