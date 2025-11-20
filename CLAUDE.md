# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Development Commands

### Build Commands
```bash
# Get dependencies
flutter pub get

# Build for release (Windows)
flutter build windows

# Build for release (Android)
flutter build apk

# Build for release (iOS)
flutter build ios
```

### Development Commands
```bash
# Run in debug mode
flutter run

# Run on specific device
flutter run -d windows
flutter run -d android
flutter run -d ios

# Analyze code
flutter analyze

# Run tests
flutter test
```

### Windows Deployment
The project includes `build_win.bat` for copying Windows build artifacts to Program Files.

## Architecture Overview

### Core Structure
Pica Comic is a Flutter-based multi-source comic reader application with the following key architectural components:

#### 1. Comic Sources (`lib/comic_source/`)
- **Built-in sources**: 6 supported platforms (picacg, e-hentai/exhentai, jmcomic, hitomi, htcomic, nhentai)
- **Category management**: `category.dart`, `app_build_in_category.dart`
- **Favorites management**: `favorites.dart`, `app_build_in_favorites.dart`

#### 2. Network Layer (`lib/network/`)
- **Source-specific implementations**: Each comic source has its own network module
  - `picacg_network/`: Picacg API implementation
  - `eh_network/`: E-Hentai/ExHentai implementation
  - `jm_network/`: JMComic implementation
  - `hitomi_network/`: Hitomi.la implementation
  - `htmanga_network/`: HTManga implementation
  - `nhentai_network/`: Nhentai implementation
- **Common utilities**: `base_comic.dart`, `http_client.dart`, `download_model.dart`
- **WebDAV sync**: `webdav.dart` for data synchronization

#### 3. UI Components (`lib/components/`)
- Reusable widgets and UI components
- Custom navigation, layouts, and interactive elements
- Platform-specific adaptations

#### 4. Pages (`lib/pages/`)
- **Main pages**: `main_page.dart`, `welcome_page.dart`, `auth_page.dart`
- **Reader system**: `reader/` directory with reading logic and controls
- **Source-specific pages**: Each comic source has dedicated page implementations
- **Settings**: Comprehensive settings system in `settings/` directory
- **Local management**: `local/` for local comic storage

#### 5. Foundation (`lib/foundation/`)
- Core app utilities and state management
- Image loading and caching systems
- Platform detection and adaptations

### Key Features Implementation

#### Multi-Source Architecture
The app uses a plugin-like architecture where each comic source implements a common interface defined in `base_comic.dart`. This allows for:
- Uniform API across different sources
- Easy addition of new sources
- Source-specific authentication and data handling

#### Reading System
- Advanced image viewer with zoom, pan, and gesture controls
- Episode/chapter management
- Reading progress tracking
- Download management for offline reading

#### Data Synchronization
- WebDAV-based sync for favorites and reading progress
- Local SQLite database for caching and offline storage
- Import/export functionality

#### Security & Privacy
- Authentication system with biometric support
- Screenshot blocking capability
- Content hiding on app backgrounding

## Development Notes

### Dependencies
- Uses Flutter 3.35.7
- Several custom forked dependencies for specific features
- SQLite for local data storage
- WebDAV client for cloud sync

### Platform Support
- Primary focus on Android, with Windows and iOS support
- Desktop-specific features like window management
- Platform-specific UI adaptations

### State Management
- Uses a combination of StatefulWidget and custom state controllers
- Event bus for inter-component communication
- Local storage for persistent settings

### Custom Components
The project includes several custom components and utilities, particularly for:
- Image loading and display optimization
- Custom scroll behaviors
- Platform-specific UI adaptations