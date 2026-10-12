# 应用设置

设置定义集中在 `lib/foundation/app_setting_keys.dart`，每个 key 都有中文用途说明，默认值集中在 `defaultAppSettings`。原有 97 个槽位保留 75 个有效设置，另将字体纳入统一仓库，共 76 项。

## 存储格式

应用数据目录下的 `settings` 文件直接保存 JSON 对象。导出文件与 WebDAV 使用同样的对象作为 `settings` 字段。程序不读取旧的 value 数组，也不做运行时旧格式迁移。

```json
{
  "networkBackend": "rhttp",
  "networkProtocol": "auto",
  "parallelDownloads": "6",
  "showNetworkSpeedBall": "0",
  "font": ""
}
```

value 沿用现有字符串编码：布尔值使用 `"1"`/`"0"`，数值存为数字字符串，列表及复合配置的编码在对应 key 的注释中说明。部分 key 缺失时使用默认值；未知 key 不纳入有效设置。

## 读取与修改

- Widget 使用 `appSettingsProvider` 或其派生 Provider 观察快照，使用 Notifier 的 `setValue`/`setValues` 修改配置。
- 滑块预览可使用 `persist: false`，拖动结束再调用 `save()`。
- 无 WidgetRef 的设置弹窗从当前 `ProviderScope` 读取同一个 Notifier。
- Riverpod 管理的网络与下载服务通过 `ref.read(appSettingsProvider)` 读取最新快照，写入统一调用设置 Notifier；不要在这些服务里直接读取或修改 `appdata`。
- 非 Provider 服务通过构造参数、回调或设置仓库接收配置；`appdata.getSetting` 仅作为尚未迁移的兼容读取入口，不能成为新服务的依赖方式。
- 用户数据导入保留本机的下载目录与身份验证配置。隐式界面状态、首次使用提示和已有独立主题 Provider 维持各自存储边界。

## 后续改造约定

后续修改含 `appdata` 设置访问的页面或业务模块时，应连带检查能否接入 Riverpod，并迁移适合的设置调用。按模块推进，避免只为消除全局变量而改变服务生命周期。

- 已有 `ref` 的界面使用 `appSettingProvider(key)` 或领域 Provider 的 `watch/select` 观察所需设置；事件回调使用 `read` 读取最新值，通过 Notifier 修改。不要在事件回调中使用 `watch`。
- 编辑弹窗的草稿、输入控制器和未提交选择仍为局部状态，不要用设置监听覆盖用户正在输入的内容。
- 普通服务优先由 Provider 创建并注入仓库或配置；后台 isolate 自行读取持久化数据。不要借用全局界面 `Ref` 或创建全局容器绕过依赖边界。
- 阅读器已有会话 Notifier，后续调整其设置读取时，优先 `read` 或针对性的 `listen` 更新业务状态。不能因设置变化重新初始化阅读会话、重置页码或释放控制器。
- 网络管理器和共享 Dio 保持应用级生命周期；配置变化通过现有运行时应用入口处理。
- `AppSettingsRepository` 内部的 `appdata` 访问是存储适配；账号、历史、隐式界面状态等非主设置数据分别评估，不随设置迁移机械替换。

当前已将 E-Hentai、禁漫、哔咔、Hitomi、绅士漫画、本地收藏、漫画源开关、主设置页及设置弹窗的主设置读取接入 Provider；阅读器右键菜单的图片宽度限制通过会话 Notifier 调用统一设置入口。其他业务中的同步读取继续按上述约定逐步处理。

## 清理的失效项

移除了旧转发开关、旧搜索排序入口、首次使用冗余开关、旧收藏浏览方式、旧禁漫分类/搜索排序、旧漫画源开关、废弃分类/探索页面、旧主题颜色/深色/纯黑配置、旧缓存数量限制、未使用的翻页动画、旧 nhentai 排序/域名、旧收藏开关、旧禁漫域名、旧工具栏配置、本地收藏显示数量、自定义源更新开关，以及没有业务读取的常亮开关。

阅读器当前使用 `WakelockPlus`，常亮开关的删除保持现有阅读行为。Hosts 虽已提示不再受支持，但仍有代理运行时依赖，因此继续保留。
