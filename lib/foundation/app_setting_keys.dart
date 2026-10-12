/// 应用设置的稳定命名 key，集中说明用途和取值含义。
abstract final class AppSettingKeys {
  /// 应用界面的自定义字体；空字符串使用平台默认字体。
  static const font = 'font';

  /// 点按屏幕左右区域翻页：1 启用，0 禁用。
  static const readerTapToTurnPage = "readerTapToTurnPage";

  /// 启动时检查应用更新：1 启用，0 禁用。
  static const checkUpdatesOnStartup = "checkUpdatesOnStartup";

  /// 宽屏时显示前进后退关闭按钮
  static const showReaderButtons = "showReaderButtons";

  /// 是否显示头像框
  static const picacgShowAvatarFrame = "picacgShowAvatarFrame";

  /// 启动时签到
  static const picacgAutoCheckIn = "picacgAutoCheckIn";

  /// 使用音量键翻页
  static const readerVolumeKeys = "readerVolumeKeys";

  /// HTTP 代理地址；0 使用系统代理，空字符串禁用代理。
  static const proxy = "proxy";

  /// 阅读模式：1 左至右，2 右至左，3 上至下，4 连续竖向，5 双页，6 反向双页。
  static const readingMode = "readingMode";

  /// 上下连续模式自动衔接相邻章节：1 启用，0 禁用。
  static const continuousChapterReading = "continuousChapterReading";

  /// 阻止屏幕截图
  static const preventScreenshots = "preventScreenshots";

  /// 身份验证开关；1 启用，0 禁用，导入数据时保留本机配置。
  static const requireAuthentication = "requireAuthentication";

  /// Jm自动选择域名
  static const jmAutoSelectDomain = "jmAutoSelectDomain";

  /// Jm分流
  static const jmApiStream = "jmApiStream";

  /// 夜间模式降低图片亮度
  static const dimImagesInDarkMode = "dimImagesInDarkMode";

  /// Eh 站点：1 为 e-hentai，2 为 exhentai，0 保持默认行为。
  static const ehSite = "ehSite";

  /// 下载目录；空字符串使用应用数据目录，导入数据时保留本机路径。
  static const downloadDirectory = "downloadDirectory";

  /// 初始页面,
  static const initialPage = "initialPage";

  /// 漫画列表显示方式：0 连续加载，1 分页。
  static const comicsListDisplayMode = "comicsListDisplayMode";

  /// 下载列表排序，格式为“排序项与方向”两位字符：排序项 0 时间/1 标题/2 副标题/3 大小，方向 0 降序/1 升序。
  static const downloadSort = "downloadSort";

  /// 预加载页数
  static const preloadPages = "preloadPages";

  /// eh优先加载原图
  static const ehPreferOriginal = "ehPreferOriginal";

  /// picacg收藏夹新到旧
  static const picacgFavoritesNewestFirst = "picacgFavoritesNewestFirst";

  /// 绅士漫画域名
  static const htmangaDomain = "htmangaDomain";

  /// 自动翻页时间
  static const autoPageInterval = "autoPageInterval";

  /// 缓存大小限制
  static const cacheLimitMb = "cacheLimitMb";

  /// 禁漫图片分流
  static const jmImageStream = "jmImageStream";

  /// 高刷新率
  static const highRefreshRate = "highRefreshRate";

  /// 点按翻页识别范围(0-50),
  static const tapTurnPageRange = "tapTurnPageRange";

  /// 阅读器图片布局方式, 0-contain, 1-fitWidth, 2-fitHeight
  static const readerImageLayout = "readerImageLayout";

  /// 禁漫收藏夹排序模式, 0-最新收藏, 1-最新更新
  static const jmFavoritesOrder = "jmFavoritesOrder";

  /// 限制图片宽度
  static const limitReaderImageWidth = "limitReaderImageWidth";

  /// 漫画块显示设置，格式为“模式,缩放比例”：模式 0 详细/1 简略，比例默认 1.0。
  static const comicTileDisplay = "comicTileDisplay";

  /// WebDAV 连接配置，格式为“地址;用户名;密码;目录”；末尾附加 ;0 表示暂时禁用同步。
  static const webdavConfig = "webdavConfig";

  /// 用户数据同步版本，使用 Unix 时间戳秒数比较新旧。
  static const webdavVersion = "webdavVersion";

  /// Eh 是否忽略画廊警告：1 忽略，0 正常检查。
  static const ehIgnoreWarnings = "ehIgnoreWarnings";

  /// 阅读器中双击放缩
  static const doubleTapZoom = "doubleTapZoom";

  /// 界面语言：空字符串跟随系统，cn 简体中文，tw 繁体中文，en 英文。
  static const language = "language";

  /// 默认收藏夹
  static const defaultFavoriteFolder = "defaultFavoriteFolder";

  /// 本地收藏添加位置(尾/首)
  static const localFavoriteInsertPosition = "localFavoriteInsertPosition";

  /// 阅读后移动本地收藏(否/尾/首)
  static const localFavoriteMoveAfterReading = "localFavoriteMoveAfterReading";

  /// 长按缩放
  static const longPressZoom = "longPressZoom";

  /// 阅读器是否显示页码信息：1 显示，0 隐藏。
  static const showReaderPageInfo = "showReaderPageInfo";

  /// 旧 Hosts 代理服务开关：1 启用，0 禁用；仍有运行时依赖，保留。
  static const hostsEnabled = "hostsEnabled";

  /// 点击本地收藏后的动作：0 显示信息，其余值沿用直接阅读行为。
  static const localFavoriteTapAction = "localFavoriteTapAction";

  /// check link in clipboard
  static const checkClipboardLinks = "checkClipboardLinks";

  /// 初始搜索目标
  static const defaultSearchSource = "defaultSearchSource";

  /// 启用侧边翻页
  static const showListSidePaging = "showListSidePaging";

  /// 缩略图布局: 覆盖, 容纳
  static const thumbnailFit = "thumbnailFit";

  /// 分类页面的漫画源标识列表，以逗号分隔并保留显示顺序。
  static const categoryPages = "categoryPages";

  /// 网络收藏页面的漫画源标识列表，以逗号分隔并保留显示顺序。
  static const networkFavoritePages = "networkFavoritePages";

  /// 搜索自动语言筛选：0 不筛选，1 中文，2 英文，3 日文。
  static const searchLanguageFilter = "searchLanguageFilter";

  /// 反转点按识别
  static const reverseTapTurnPage = "reverseTapTurnPage";

  /// 关联网络收藏夹时每次同步拉取的页数。
  static const favoriteSyncPages = "favoriteSyncPages";

  /// 漫画块显示收藏状态
  static const showComicFavoriteStatus = "showComicFavoriteStatus";

  /// 漫画块显示阅读位置
  static const showComicReadingProgress = "showComicReadingProgress";

  /// 图片收藏大小
  static const imageFavoriteScale = "imageFavoriteScale";

  /// Eh 使用的用户配置标识；空字符串保持默认配置。
  static const ehProfile = "ehProfile";

  /// 阅读器内固定屏幕方向: 0-禁用, 1-横屏, 2-竖屏
  static const readerOrientation = "readerOrientation";

  /// 探索页面名称列表，以逗号分隔并保留显示顺序。
  static const explorePages = "explorePages";

  /// 已下载的eh漫画优先显示副标题
  static const ehDownloadedUseSubtitle = "ehDownloadedUseSubtitle";

  /// 漫画下载的并行数量，默认 6。
  static const parallelDownloads = "parallelDownloads";

  /// 使用深色背景
  static const readerDarkBackground = "readerDarkBackground";

  /// 按 builtInSources 顺序保存的漫画源启用标记，1 启用/0 禁用；新增源默认启用。
  static const enabledBuiltInSources = "enabledBuiltInSources";

  /// 完全隐藏屏蔽的作品
  static const fullyHideBlockedComics = "fullyHideBlockedComics";

  /// 禁漫 API 域名列表，以逗号分隔。
  static const jmApiDomains = "jmApiDomains";

  /// 禁漫图片域名，用于图片请求分流。
  static const jmImageDomain = "jmImageDomain";

  /// Hitomi 图片 CDN 域名。
  static const hitomiCdnDomain = "hitomiCdnDomain";

  /// jm auto checkin
  static const jmAutoCheckIn = "jmAutoCheckIn";

  /// 禁漫请求使用的应用版本号。
  static const jmAppVersion = "jmAppVersion";

  /// 日志级别：auto/trace/debug/info/warning/error。
  static const logLevel = "logLevel";

  /// 外部翻译结果根目录；空字符串仅扫描原漫画目录中的 result。
  static const translationResultDirectory = "translationResultDirectory";

  /// 网络请求后端：rhttp 或 dio。
  static const networkBackend = "networkBackend";

  /// HTTP 协议偏好：auto/http1/http2。
  static const networkProtocol = "networkProtocol";

  /// 网速悬浮球开关：1 显示，0 隐藏。
  static const showNetworkSpeedBall = "showNetworkSpeedBall";

  /// 网络日志采集开关：1 采集，0 停止。
  static const collectNetworkLogs = "collectNetworkLogs";

  /// 下载列表拖动开关：1 禁用拖动，0 允许拖动。
  static const downloadPageDragDisabled = "downloadPageDragDisabled";
}

/// 设置默认值。字符串编码保留现有业务取值语义，持久化为 JSON 对象。
const defaultAppSettings = <String, String>{
  AppSettingKeys.font: '',
  AppSettingKeys.readerTapToTurnPage: "1",
  AppSettingKeys.checkUpdatesOnStartup: "1",
  AppSettingKeys.showReaderButtons: "1",
  AppSettingKeys.picacgShowAvatarFrame: "1",
  AppSettingKeys.picacgAutoCheckIn: "1",
  AppSettingKeys.readerVolumeKeys: "1",
  AppSettingKeys.proxy: "0",
  AppSettingKeys.readingMode: "1",
  AppSettingKeys.continuousChapterReading: "1",
  AppSettingKeys.preventScreenshots: "0",
  AppSettingKeys.requireAuthentication: "0",
  AppSettingKeys.jmAutoSelectDomain: "1",
  AppSettingKeys.jmApiStream: "0",
  AppSettingKeys.dimImagesInDarkMode: "0",
  AppSettingKeys.ehSite: "0",
  AppSettingKeys.downloadDirectory: "",
  AppSettingKeys.initialPage: "0",
  AppSettingKeys.comicsListDisplayMode: "0",
  AppSettingKeys.downloadSort: "00",
  AppSettingKeys.preloadPages: "2",
  AppSettingKeys.ehPreferOriginal: "0",
  AppSettingKeys.picacgFavoritesNewestFirst: "1",
  AppSettingKeys.htmangaDomain: "https://www.wn10.cfd",
  AppSettingKeys.autoPageInterval: "5",
  AppSettingKeys.cacheLimitMb: "500",
  AppSettingKeys.jmImageStream: "0",
  AppSettingKeys.highRefreshRate: "0",
  AppSettingKeys.tapTurnPageRange: "25",
  AppSettingKeys.readerImageLayout: "0",
  AppSettingKeys.jmFavoritesOrder: "0",
  AppSettingKeys.limitReaderImageWidth: "1",
  AppSettingKeys.comicTileDisplay: "0,1.0",
  AppSettingKeys.webdavConfig: "",
  AppSettingKeys.webdavVersion: "0",
  AppSettingKeys.ehIgnoreWarnings: "0",
  AppSettingKeys.doubleTapZoom: "1",
  AppSettingKeys.language: "",
  AppSettingKeys.defaultFavoriteFolder: "",
  AppSettingKeys.localFavoriteInsertPosition: "0",
  AppSettingKeys.localFavoriteMoveAfterReading: "0",
  AppSettingKeys.longPressZoom: "1",
  AppSettingKeys.showReaderPageInfo: "1",
  AppSettingKeys.hostsEnabled: "0",
  AppSettingKeys.localFavoriteTapAction: "0",
  AppSettingKeys.checkClipboardLinks: "0",
  AppSettingKeys.defaultSearchSource: "0",
  AppSettingKeys.showListSidePaging: "0",
  AppSettingKeys.thumbnailFit: "0",
  AppSettingKeys.categoryPages: "picacg,ehentai,jm,htmanga,nhentai",
  AppSettingKeys.networkFavoritePages: "picacg,ehentai,jm,htmanga,nhentai",
  AppSettingKeys.searchLanguageFilter: "0",
  AppSettingKeys.reverseTapTurnPage: "0",
  AppSettingKeys.favoriteSyncPages: "1",
  AppSettingKeys.showComicFavoriteStatus: "1",
  AppSettingKeys.showComicReadingProgress: "0",
  AppSettingKeys.imageFavoriteScale: "1.0",
  AppSettingKeys.ehProfile: "",
  AppSettingKeys.readerOrientation: "0",
  AppSettingKeys.explorePages: "picacg,Eh主页,Eh热门,禁漫主页,禁漫最新,hitomi,绅士漫画,nhentai",
  AppSettingKeys.ehDownloadedUseSubtitle: "0",
  AppSettingKeys.parallelDownloads: "6",
  AppSettingKeys.readerDarkBackground: "0",
  AppSettingKeys.enabledBuiltInSources: "1111111",
  AppSettingKeys.fullyHideBlockedComics: "1",
  AppSettingKeys.jmApiDomains:
      "www.cdntwice.org,www.cdnsha.org,www.cdnaspa.cc,www.cdnntr.cc",
  AppSettingKeys.jmImageDomain: "https://cdn-msp.jmapiproxy3.cc",
  AppSettingKeys.hitomiCdnDomain: "gold-usergeneratedcontent.net",
  AppSettingKeys.jmAutoCheckIn: "0",
  AppSettingKeys.jmAppVersion: "2.0.11",
  AppSettingKeys.logLevel: "auto",
  AppSettingKeys.translationResultDirectory: "",
  AppSettingKeys.networkBackend: "rhttp",
  AppSettingKeys.networkProtocol: "auto",
  AppSettingKeys.showNetworkSpeedBall: "0",
  AppSettingKeys.collectNetworkLogs: "0",
  AppSettingKeys.downloadPageDragDisabled: "1",
};
