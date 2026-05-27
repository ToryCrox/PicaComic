# PicaComic - 项目规范

## 项目概述
这是一个使用 Flutter 开发的跨平台漫画阅读应用，支持 Android、iOS、Windows、Linux、macOS 和 Web 平台。

## 技术栈
- **框架**: Flutter (通过 FVM 管理，当前 SDK 版本 3.38.10)
- **语言**: Dart (SDK constraint >=3.10.0 <4.0.0)
- **代码分析**: flutter_lints (>=2.0.0)
- **状态管理**: `signals` (6.3.0) + `flutter_riverpod` (>=3.0.3) + `riverpod_annotation` (代码生成)
- **主要依赖**: dio, shared_preferences, dynamic_color, photo_view, sqlite3, worker_manager, cached_network_image, window_manager 等

## 代码风格规范

### Dart/Flutter 最佳实践
1. **遵循 flutter_lints 规则**: 项目使用 `flutter_lints` 进行代码分析，所有代码必须通过 `flutter analyze`
2. **使用 const 构造函数**: 尽可能使用 `const` 构造函数以提高性能
3. **命名规范**:
   - 类名: PascalCase (如 `ComicTile`, `App`)
   - 变量和方法: camelCase (如 `comicId`, `buildSubDescription`)
   - 私有成员: 以下划线开头 (如 `_MyAppState`)
   - 常量: lowerCamelCase (如 `appdata`, `downloadManager`)
4. **文件组织**: 
   - 每个文件一个主要类/功能
   - `components.dart` 使用 `library` + `part` 组织大型 Widget 组件
5. **导入顺序**:
   ```dart
   // 1. Dart SDK
   import 'dart:async';
   import 'dart:ui';
   
   // 2. Flutter 包
   import 'package:flutter/material.dart';
   
   // 3. 第三方包
   import 'package:dio/dio.dart';
   import 'package:flutter_riverpod/flutter_riverpod.dart';
   import 'package:signals/signals_flutter.dart';
   
   // 4. 项目内部
   import 'package:pica_comic/base.dart';
   import 'package:pica_comic/foundation/app.dart';
   import '../foundation/log.dart';
   ```

### 项目架构规范

#### 目录结构
- `lib/components/`: 可复用的 UI 组件（`components.dart` 通过 `part` 组织子组件）
- `lib/foundation/`: 核心功能、工具类和基础架构（app.dart、log.dart、database/、image_loader/）
- `lib/network/`: 网络请求相关代码（各漫画源子目录、download/）
- `lib/pages/`: 页面组件（各漫画源子目录、reader/、settings/、download/）
- `lib/tools/`: 工具函数和扩展
- `lib/comic_source/`: 漫画源相关代码（built_in/ 内置漫画源、接口定义）
- `packages/`: 本地子包（log_viewer_server、log_viewer_shared、log_viewer_web）

#### 内置漫画源（7个）
`lib/comic_source/built_in/` 下包含: picacg、ehentai、jm、htmanga、nhentai、hitomi、kemono

#### 状态管理
项目同时使用 **signals** 和 **flutter_riverpod**：

1. **signals** — 轻量级响应式状态，适用于简单场景
   ```dart
   import 'package:signals/signals_flutter.dart';
   
   final counter = signal(0);
   
   // 细粒度局部更新
   Widget buildCounter() {
     return Watch.builder(
       builder: (context) => Text('Counter: ${counter.value}'),
     );
   }
   ```
   使用场景：`lib/foundation/history.dart`、`lib/foundation/local_history.dart`、`lib/network/download/download_manager.dart`

2. **flutter_riverpod** — 复杂状态管理，适用于下载页面等数据密集型场景
   - 使用 @riverpod 注解 + 代码生成（riverpod_generator + build_runner）
   - Notifier 管理可变状态，函数式注解处理简单计算/异步场景
   - `@Riverpod(keepAlive: false)` 实现 autoDispose 行为（3.x 默认 autoDispose）
   - 数据分层：全局持久层（Global Persistent State）→ 实例状态层（Instance State）→ 衍生计算层（Computed State）
   
   使用场景：`lib/pages/download/download_providers.dart`（注解式定义）、`lib/pages/download/**`（ConsumerStatefulWidget、ConsumerWidget）

3. **ChangeNotifier** — 用于需要通知 UI 变化的 Manager 类
   - `DownloadManager`、`DownloadStateManager` 使用 ChangeNotifier 模式

#### 组件开发
1. **Widget 设计**:
   - 优先使用 `StatelessWidget`，需要状态时使用 `StatefulWidget` 或 `ConsumerStatefulWidget`（Riverpod）
   - 使用抽象类定义接口（如 `ComicTile`）
   - 提供清晰的 getter 和 setter
   - 使用可选参数和默认值提高灵活性

2. **性能优化**:
   - 使用 `const` 构造函数
   - 合理使用 `ListView.builder` 而非 `ListView`
   - 图片缓存: 最大 400MB（`PaintingBinding.instance.imageCache.maximumSizeBytes`）
   - 避免在 `build` 方法中执行耗时操作
   - 使用 `worker_manager` 管理后台 Isolate 计算（3 个 Isolate）

3. **lib/components/components.dart 组件库**:
   - 使用 `library components;` 声明
   - 通过 `part` 引入子组件文件（appbar、comic_tile、comics_list、flyout、loading、menu、message、navigation_bar 等）
   - 禁止在此文件中添加新版 Widget 的 `part`，新组件请创建独立文件

#### 网络请求
1. **网络客户端**: `lib/network/http_client.dart` 和 `lib/network/app_dio.dart`
2. **Cookie 管理**: 使用自定义 `SingleInstanceCookieJar` + SQLite 持久化（`lib/network/cookie_jar.dart`）
3. **HTTP/2 支持**: 使用 `dio_http2_adapter`
4. **代理**: `lib/network/http_proxy.dart`
5. **下载功能**: `lib/network/download/` 包含 download_manager、download_state_manager、download_queue_manager、image_download_queue、file_downloader

#### 平台特定代码
1. **平台检测**: 使用 `App.isAndroid`, `App.isDesktop`, `App.isMobile`, `App.isWindows`, `App.isLinux`, `App.isMacOS`, `App.isIOS`
2. **条件编译**: 使用 `if (App.isWindows)` 等条件判断
3. **UI 适配**: 使用 `App.uiMode()` 进行响应式设计（m1/m2/m3 三种模式）
4. **桌面窗口**: 使用 `window_manager` 管理窗口（TitleBarStyle.hidden，Linux 透明背景）

## 编码规范

### 日志规范
使用 `lib/foundation/log.dart` 中的 `Log` 类进行日志记录：
- `Log.d()` — 调试日志
- `Log.i()` — 信息日志
- `Log.w()` — 警告日志
- `Log.e()` — 错误日志
- 底层使用 `package:logger`，支持控制台输出 + 文件持久化 + LogViewer 集成
- 生产模式默认 Level 为 info，开发模式为 trace
- 日志级别可通过 `appdata.settings[90]` 配置（auto/trace/debug/info/warning/error）

### 注释和文档
1. **文档注释**: 使用 `///` 为公共 API 添加文档注释
2. **中文注释**: 项目使用中文注释，保持一致性，类和方法必须有中文注释
3. **TODO 注释**: 使用 `// TODO: 描述` 标记待办事项

### 错误处理
1. **异常捕获**: 使用 `try-catch` 处理可能抛出的异常
2. **全局异常**: `main()` 中使用 `runZonedGuarded` 捕获未处理异常，并通过 `FlutterError.onError` 记录
3. **用户友好**: 向用户显示友好的错误信息

### 空值安全
1. 充分利用 Dart 的空值安全特性
2. 使用 `?`、`!`、`??` 操作符处理可空类型
3. 使用 `TypeUtil` 进行类型转换和比较

### 逻辑结构与代码圈复杂度
1. **代码段体积限制**: 单个方法的行数不应超过 **200 行**
2. **逻辑嵌套避免过深**: 嵌套过深需要独立封装成单独的方法
3. **三目运算符规范**: 如果内容过长超过一行，使用 `if-else` 提前定义变量

### 异步编程
1. **使用 async/await**: 优先使用 `async/await` 而非 `Future.then()`
2. **错误处理**: 使用 `runZonedGuarded` 捕获未处理的异常
3. **并发控制**: 使用 `synchronized` 包处理并发问题

### 数据持久化
1. **SharedPreferences**: 通过 `appdata` (`lib/base.dart`) 进行设置存储，`Appdata` 类统一管理所有设置项
2. **数据库**: 使用 `sqlite3` + `sqflite_common_ffi`（桌面端），Cookie 存储使用自定义 SQLite 实现
3. **文件操作**: 使用 `path_provider` 获取路径，`App.dataPath` / `App.cachePath` 为集中路径管理

## 特定功能规范

### 漫画源开发
1. **实现接口**: 实现 `ComicSource` 接口
2. **解析器**: 使用 `Parser` 进行数据解析
3. **分类和收藏**: 实现 `Category` 和 `Favorites` 接口
4. **数据存储**: 每个漫画源在 `data` Map 中存储自身状态，通过 `saveData()` 持久化到 JSON 文件

### 图片处理
1. **图片加载**: 使用 `lib/foundation/image_loader/` 中的图片加载器（base_image_provider、file_image_loader、stream_image_provider）
2. **图片缓存**: 使用 `lib/foundation/cache_manager.dart` 和 `lib/foundation/disk_cache.dart`
3. **图片重组**: 使用 `ImageRecombine` (`lib/foundation/image_loader/image_recombine.dart`) 处理特殊格式（如 JM）

### 下载功能
1. **下载模型**: `lib/network/download/` 下统一管理
2. **进度跟踪**: 实现进度回调
3. **错误恢复**: 实现断点续传和错误重试（`download_error_handler.dart`）
4. **并行下载**: 下载并行数通过 `appdata.settings[79]` 配置（默认 6）

## 测试规范
1. **单元测试**: 为关键业务逻辑编写单元测试
2. **Widget 测试**: 为重要组件编写 Widget 测试
3. **测试文件**: 放在 `test/` 目录下

## Git 提交规范
1. **提交格式**: 使用 Conventional Commits 格式
   - `feat:` / `fix:` / `style:` / `perf:` / `refactor:` 等前缀
   - 描述使用中文，如 `feat: 新增批量重下载和封面刷新支持`
2. **提交粒度**: 每次提交包含一个完整的功能或修复
3. **代码审查**: 重要更改需要代码审查

## 性能要求
1. **启动时间**: 优化应用启动时间
2. **内存使用**: 注意内存泄漏，及时释放资源
3. **图片缓存**: 最大 400MB + 4000 张
4. **列表性能**: 使用虚拟滚动优化长列表

## 安全规范
1. **敏感信息**: 不要在代码中硬编码敏感信息
2. **用户数据**: 妥善处理用户隐私数据
3. **网络请求**: 使用 HTTPS，验证证书

## 国际化
1. **多语言支持**: 支持中文简体、中文繁体和英文
2. **本地化**: 使用 `flutter_localizations`
3. **标签翻译**: 使用 `TagsTranslation` (`lib/tools/tags_translation.dart`) 和 `AppTranslation` (`lib/tools/translations.dart`)，翻译数据从 `assets/tags.json` 和 `assets/translation.json` 加载

## 代码审查清单
- [ ] 代码通过 `flutter analyze`
- [ ] 遵循项目代码风格
- [ ] 添加必要的注释和文档
- [ ] 处理所有可能的错误情况
- [ ] 测试多平台兼容性（如适用）
- [ ] 性能优化（避免不必要的重建）
- [ ] 内存泄漏检查
- [ ] UI 响应式设计检查

## 常见问题
1. **平台特定问题**: 使用 `App.isXXX` 进行平台检测
2. **路由导航**: 使用 `App.to()` 和 `App.globalBack()` 进行导航
3. **主题适配**: 使用 `Theme.of(context)` 获取主题
4. **窗口管理**: 桌面平台使用 `window_manager` 进行窗口管理

## 常用命令

项目使用 FVM 管理 Flutter SDK 版本（当前锁定 3.38.10）。以下命令优先列出 FVM 版本，如果未安装 FVM 则直接使用 `flutter` 命令替代。

### 依赖管理
```bash
fvm flutter pub get          # 安装依赖
fvm flutter pub upgrade      # 升级依赖
fvm flutter pub outdated     # 查看过期依赖
```

### 运行与构建
```bash
fvm flutter run              # 运行应用（连接设备后）
fvm flutter run -d windows   # 指定平台运行
fvm flutter run -d android   # 指定平台运行
fvm flutter build apk        # 构建 Android APK
fvm flutter build windows    # 构建 Windows 应用
fvm flutter build linux      # 构建 Linux 应用
fvm flutter build macos      # 构建 macOS 应用
fvm flutter build web        # 构建 Web 应用
```

### 代码质量
```bash
fvm flutter analyze          # 静态分析（必须通过）
fvm flutter test             # 运行单元测试
fvm dart fix --apply         # 应用自动修复
```

### 清理
```bash
fvm flutter clean            # 清理构建缓存和 .dart_tool/
fvm flutter pub cache clean  # 清理 pub 缓存
```

### 版本管理
```bash
fvm list                     # 查看已安装的 Flutter 版本
fvm use 3.38.10              # 切换到指定版本
```

### 桌面端打包辅助
```bash
dart run flutter_to_arch     # 生成 Arch Linux PKGBUILD（参阅 pubspec.yaml 的 flutter_to_arch 配置）
```

### 代码生成
```bash
fvm dart run build_runner build --delete-conflicting-outputs  # 完整重新生成（首次运行或依赖变更后使用）
fvm dart run build_runner watch --delete-conflicting-outputs  # 开发模式（监听文件变化自动重新生成）
```

修改 `download_providers.dart` 中的 @riverpod 注解后，必须运行 build_runner 重新生成 `.g.dart` 文件。
生成的 `*.g.dart` 文件不纳入版本控制（已在 .gitignore 中排除）。

## 注意事项
- 保持代码简洁和可读性
- 遵循 DRY (Don't Repeat Yourself) 原则
- 优先使用项目已有的工具和组件
- 新功能要考虑多平台兼容性
- 注意向后兼容性

## AI 协作与工作流指导 (Agent Rules)

### 语言输出规范
1. **纯中文服务原则**: 所有的系统分析、Bug原因解释、方案建议、生成的计划或Task任务等，**必须严格使用中文**
2. **Git Commit 信息规范**: 代码提交的 Commit Message 前缀使用 Conventional Commits 格式（`feat:`, `fix:`, `style:`, `perf:`, `refactor:` 等），描述部分使用**中文**
3. **技术标识符保留英文**: 机器可读字段，如变量名、方法名、库名、文件路径和 CLI 命令行不能被翻译，要求维持原始英文

### 执行与思考流程
1. **执行复杂任务原则**: 在修改尚未梳理过的代码逻辑前，AI 应优先阅读已有源码或者项目文档；对相关业务做出计划（Plan），待用户评估且同意后再去执行
2. **不确定性规则**: 遇到不明确的选择时（例如两套不同的架构实现方案），要主动输出不同选项的利弊由用户最终决策，切不可盲目猜测、生硬套用
