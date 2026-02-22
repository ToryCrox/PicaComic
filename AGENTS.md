# PicaComic - Cursor Rules

## 项目概述
这是一个使用 Flutter 开发的跨平台漫画阅读应用，支持 Android、iOS、Windows、Linux、macOS 和 Web 平台。

## 技术栈
- **框架**: Flutter (SDK >= 3.32.0)
- **语言**: Dart
- **代码分析**: flutter_lints
- **主要依赖**: dio, shared_preferences, dynamic_color, photo_view, sqlite3 等

## 代码风格规范

### Dart/Flutter 最佳实践
1. **遵循 flutter_lints 规则**: 项目使用 `flutter_lints` 进行代码分析，所有代码必须通过 `flutter analyze`
2. **使用 const 构造函数**: 尽可能使用 `const` 构造函数以提高性能
3. **命名规范**:
   - 类名: PascalCase (如 `ComicTile`, `App`)
   - 变量和方法: camelCase (如 `comicId`, `buildSubDescription`)
   - 私有成员: 以下划线开头 (如 `_MyAppState`)
   - 常量: lowerCamelCase 或 SCREAMING_CAPS (根据项目风格)
4. **文件组织**: 
   - 每个文件一个主要类/功能
   - 使用 `part` 和 `part of` 组织相关代码（如 `components.dart`）
5. **导入顺序**:
   ```dart
   // 1. Dart SDK
   import 'dart:async';
   import 'dart:ui';
   
   // 2. Flutter 包
   import 'package:flutter/material.dart';
   
   // 3. 第三方包
   import 'package:dio/dio.dart';
   
   // 4. 项目内部（使用相对路径）
   import 'package:pica_comic/base.dart';
   import '../foundation/app.dart';
   ```

### 项目架构规范

#### 目录结构
- `lib/components/`: 可复用的 UI 组件
- `lib/foundation/`: 核心功能、工具类和基础架构
- `lib/network/`: 网络请求相关代码
- `lib/pages/`: 页面组件
- `lib/tools/`: 工具函数和扩展
- `lib/comic_source/`: 漫画源相关代码

#### 组件开发
1. **Widget 设计**:
   - 优先使用 `StatelessWidget`，需要状态时使用 `StatefulWidget`
   - 使用抽象类定义接口（如 `ComicTile`）
   - 提供清晰的 getter 和 setter
   - 使用可选参数和默认值提高灵活性

2. **状态管理**:
   - 建议使用 `signals`包（`package:signals/signals_flutter.dart`）进行状态管理。**注：不再推荐使用 `StateController`**。
   - **细粒度控制**: 使用 `Watch.builder` 代替标准的 `Builder` 组件以实现局部状态刷新机制。只有被依赖的 `signal` 更新时，才会触发对应 Widget 的重建操作，避免造成外围 Widget 的不必要重绘，达到最精细的控制效果。
     ```dart
     import 'package:flutter/material.dart';
     import 'package:signals/signals_flutter.dart';

     final counter = signal(0);
     
     // 推荐方式：局部细粒度更新
     Widget buildCounter() {
       return Watch.builder(
         builder: (context) => Text('Counter: ${counter.value}'),
       );
     }
     ```
   - 避免不必要的 `setState` 调用
   - 使用 `const` 构造函数减少重建

3. **性能优化**:
   - 使用 `const` 构造函数
   - 合理使用 `ListView.builder` 而非 `ListView`
   - **局部状态刷新**: 优先使用局部状态组件来处理 UI 变化，避免在顶层调用 `setState` 导致整个大组件不必要的重建
   - 图片缓存: 使用项目提供的图片加载器
   - 避免在 `build` 方法中执行耗时操作

#### 网络请求
1. **使用项目统一的网络客户端**: `lib/network/http_client.dart` 和 `lib/network/app_dio.dart`
2. **错误处理**: 统一使用项目的错误处理机制
3. **Cookie 管理**: 使用 `cookie_jar` 进行 Cookie 管理
4. **下载功能**: 使用项目提供的下载模型和工具

#### 平台特定代码
1. **平台检测**: 使用 `App.isAndroid`, `App.isDesktop`, `App.isMobile` 等
2. **条件编译**: 使用 `if (App.isWindows)` 等条件判断
3. **UI 适配**: 使用 `App.uiMode()` 进行响应式设计

## 编码规范

### 注释和文档
1. **文档注释**: 使用 `///` 为公共 API 添加文档注释
2. **中文注释**: 项目使用中文注释，保持一致性，类和方法必须有中文注释
3. **TODO 注释**: 使用 `// TODO: 描述` 标记待办事项

### 错误处理
1. **异常捕获**: 使用 `try-catch` 处理可能抛出的异常
2. **日志记录**: 使用 `Log.e()`, `Log.i()` 等记录日志
3. **用户友好**: 向用户显示友好的错误信息

### 空值安全
1. **充分利用 Dart 的空值安全特性**:
2. 使用 `?`、`!`、`??` 操作符处理可空类型
3. 使用 `TypeUtil` 进行类型转换和比较

### 逻辑结构与代码圈复杂度
1. **代码段体积限制**: 合理拆分代码的逻辑复杂度，单个方法的行数不应超过 **200 行**。
2. **逻辑嵌套层级避免过深**: 嵌套过深（例如过多层次的回调或者条件分支）需要独立封装成单独的方法。
3. **三目运算符规范**: 使用三目运算符时，如果其包含的内容过长导致超过了一行，请使用 `if-else` 提前定义变量，提升代码的可读性。


### 异步编程
1. **使用 async/await**: 优先使用 `async/await` 而非 `Future.then()`
2. **错误处理**: 使用 `runZonedGuarded` 捕获未处理的异常
3. **并发控制**: 使用 `synchronized` 包处理并发问题

### 数据持久化
1. **SharedPreferences**: 使用 `appdata` 进行设置存储
2. **数据库**: 使用 `sqlite3` 和项目提供的数据库工具
3. **文件操作**: 使用 `path_provider` 获取路径

## 特定功能规范

### 漫画源开发
1. **实现接口**: 实现 `ComicSource` 接口
2. **解析器**: 使用 `Parser` 进行数据解析
3. **分类和收藏**: 实现 `Category` 和 `Favorites` 接口

### 图片处理
1. **图片加载**: 使用 `lib/foundation/image_loader/` 中的图片加载器
2. **图片缓存**: 使用 `ImageManager` 和 `CacheManager`
3. **图片重组**: 使用 `ImageRecombine` 处理特殊格式（如 JM）

### 下载功能
1. **下载模型**: 使用项目提供的下载模型
2. **进度跟踪**: 实现进度回调
3. **错误恢复**: 实现断点续传和错误重试

## 测试规范
1. **单元测试**: 为关键业务逻辑编写单元测试
2. **Widget 测试**: 为重要组件编写 Widget 测试
3. **测试文件**: 放在 `test/` 目录下

## Git 提交规范
1. **提交信息**: 使用清晰的中文或英文描述
2. **提交粒度**: 每次提交包含一个完整的功能或修复
3. **代码审查**: 重要更改需要代码审查

## 性能要求
1. **启动时间**: 优化应用启动时间
2. **内存使用**: 注意内存泄漏，及时释放资源
3. **图片缓存**: 合理设置图片缓存大小（当前为 400MB）
4. **列表性能**: 使用虚拟滚动优化长列表

## 安全规范
1. **敏感信息**: 不要在代码中硬编码敏感信息
2. **用户数据**: 妥善处理用户隐私数据
3. **网络请求**: 使用 HTTPS，验证证书

## 国际化
1. **多语言支持**: 支持中文简体、中文繁体和英文
2. **本地化**: 使用 `flutter_localizations`
3. **标签翻译**: 使用项目提供的标签翻译功能

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

## 注意事项
- 保持代码简洁和可读性
- 遵循 DRY (Don't Repeat Yourself) 原则
- 优先使用项目已有的工具和组件
- 新功能要考虑多平台兼容性
- 注意向后兼容性

## AI 协作与工作流指导 (Agent Rules)

### 语言输出规范
1. **纯中文服务原则**: 所有的系统分析、Bug原因解释、方案建议、生成的计划或Task任务等，**必须严格使用中文**。
2. **Git Commit 信息规范**: 代码提交的 Commit Message（包含前缀 `feat:`, `fix:` 等及后续描述）必须写**中文**。
3. **技术标识符保留英文**: 机器可读字段，如变量名、方法名、库名、文件路径和 CLI 命令行不能被翻译，要求维持原始英文。

### 执行与思考流程
1. **执行复杂任务原则**: 在修改尚未梳理过的代码逻辑前，AI 应优先阅读已有源码或者项目文档；对相关业务做出计划（Plan），待用户评估且同意后再去执行。
2. **不确定性规则**: 遇到不明确的选择时（例如两套不同的架构实现方案），要主动输出不同选项的利弊由用户最终决策，切不可盲目猜测、生硬套用。

