# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Development Commands

```bash
# Get dependencies
flutter pub get

# Run in debug mode
flutter run
flutter run -d windows
flutter run -d android

# Build for release
flutter build windows
flutter build apk
flutter build ios

# Analyze code
flutter analyze

# Run tests
flutter test
```

Windows deployment: `build_win.bat` copies build artifacts to Program Files.

## Architecture Overview

Pica Comic is a multi-source comic reader using a **plugin-like architecture** where each comic source implements a uniform interface.

### Directory Structure
```
lib/
├── base.dart              # Appdata singleton (global settings, history)
├── init.dart              # App initialization
├── main.dart              # Entry point
├── comic_source/          # Source abstraction layer
├── network/               # Per-source network implementations
├── pages/                 # UI screens
├── foundation/            # State management, utilities
├── components/            # Reusable widgets
└── tools/                 # Helper functions
```

### Core Pattern: ComicSource Interface

**Key file**: `lib/comic_source/comic_source.dart`

Every comic source (picacg, ehentai, jm, hitomi, htmanga, nhentai) implements `ComicSource`:

```dart
ComicSource {
  name, key                      // Identity
  account: AccountConfig?        // Login/logout
  categoryData: CategoryData?    // Category browsing
  favoriteData: FavoriteData?    // Favorites management
  explorePages: List<ExplorePageData>  // Browse features
  searchPageData: SearchPageData?      // Search
  loadComicInfo: LoadComicFunc?        // Get comic details
  loadComicPages: LoadComicPagesFunc?  // Get page URLs
  data: Map<String, dynamic>     // Persistent source data
}
```

**Source registration**: `ComicSource.sources` holds all active sources
- Built-in: 6 hardcoded sources
- Custom: JS-based extensions loaded from `${App.dataPath}/comic_source/*.js`

### Network Layer

Each source has its own network module in `lib/network/`:
- `picacg_network/`, `eh_network/`, `jm_network/`, `hitomi_network/`, `htmanga_network/`, `nhentai_network/`

**Response pattern**: All network calls return `Res<T>`:
```dart
Res<T> {
  _data: T?           // Success data
  errorMessage: String?  // Error if present
  subData: dynamic    // Extra data (e.g., maxPage)
}
```

### State Management

**Key file**: `lib/foundation/state_controller.dart`

Uses a service locator + observable pattern:
```dart
StateController.put<T>(controller)  // Register
StateController.find<T>()           // Retrieve
controller.update()                 // Notify subscribers
```

`StateBuilder` widget binds controllers to UI and triggers rebuilds on updates.

### Reader System

**Location**: `lib/pages/reader/`

**ReadingData** (abstract base) - defines how to load pages per source:
```dart
abstract class ReadingData {
  Stream<Res<List<String>>> loadEp(int ep)  // Load page URLs
  Stream<DownloadProgress> loadImage(ep, page, url)  // Stream with progress
  ImageProvider createImageProvider(ep, page, url)
}
```

**ComicReadingPageLogic** (`reading_logic.dart`) - main controller:
- `PageController` for page-by-page mode
- `ItemScrollController` for continuous scroll mode
- `PhotoViewController` per image for zoom

Reading modes: page-by-page, continuous vertical, dual-page spread.

### Data Persistence

| Data | Storage | Location |
|------|---------|----------|
| Settings | JSON + SharedPreferences | `${App.dataPath}/settings` |
| History | SQLite | `history` table |
| Downloads | Files + SQLite | `${App.dataPath}/downloads/` |
| Source data | JSON per source | `comic_source/{key}.data` |
| Image cache | Disk LRU | Managed by `DiskCache` |

### Data Flow: Loading a Comic

1. User taps comic → navigate with `sourceKey` + `id`
2. `ComicSource.find(sourceKey)` → get source
3. `source.loadComicInfo(id)` → fetch `ComicInfoData`
4. User selects episode → create `ReadingData` subclass
5. `readingData.loadEp(ep)` → stream of image URLs
6. `readingData.loadImage()` → `Stream<DownloadProgress>`
7. `ImageProvider` renders to UI

### Key Design Patterns

- **Source-agnostic UI**: All UI code works with `ComicSource` interface, not specific sources
- **Stream-based loading**: Image loading returns streams for progress UI and cancellation
- **Lazy initialization**: Sources and data loaded on-demand
- **Dual favorites**: Network favorites (from source API) + local SQLite favorites
- **Configuration-driven pages**: Category/search UI built from `*Data` configs, not hardcoded

### Extension System

**File**: `lib/comic_source/parser.dart`

Custom sources via JavaScript (QuickJS engine):
- Load from `${App.dataPath}/comic_source/*.js`
- Implement same `ComicSource` interface
- Seamlessly integrated with built-in sources

## Platform Notes

- Flutter 3.35.7 with several forked dependencies
- Primary: Android; also supports Windows, iOS, macOS
- Desktop: window management via `window_manager`
- Uses `event_bus` for cross-component communication