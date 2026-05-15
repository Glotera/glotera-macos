# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Glotera is a macOS menubar application for real-time translation. It monitors keyboard input and selected text, providing on-demand translation via hotkeys and trigger patterns (e.g., `@en`, `@zh`). The app integrates with chat applications (WeChat, WhatsApp) for message translation and supports screenshot translation.

**Product Name**: Glotera
**Bundle ID**: ai.glotera.desktop
**Minimum macOS**: 13.0
**Architecture**: Swift/SwiftUI for macOS with AppKit

## Build & Development Commands

### Build Commands
```bash
# Open in Xcode
open desktop.xcodeproj

# Build from command line (Debug)
xcodebuild -scheme desktop -configuration Debug build

# Build from command line (Release)
xcodebuild -scheme desktop -configuration Release build

# Run tests
xcodebuild test -scheme desktop -destination 'platform=macOS'
```

### Installation & Deployment
```bash
# Install to /Applications (after building in Xcode)
./install_app.sh

# Deploy to /Applications via Xcode scheme
# Use the "deployToLocal" target in Xcode

# Package for distribution with notarization
./package.sh <version> <build> --notarize
# Example: ./package.sh 0.2.0 2025070701 --notarize

# Package without notarization
./package.sh <version> <build>
```

### Running the App
The app runs as a menubar-only application (LSUIElement=YES in Info.plist). After building, either:
- Run from Xcode (⌘R)
- Install via `./install_app.sh` and launch from /Applications
- Use the "deployToLocal" scheme to build and auto-install

## Architecture Overview

### Core Application Flow

1. **Entry Point**: `TranslateAgent.swift` (@main) → `AppDelegate.swift`
2. **AppDelegate** initializes core managers in sequence:
   - `MenuBarController` - System tray UI
   - `InputMonitor` - Keyboard event monitoring via Event Tap
   - `DatabaseManager` - SQLite database for chat messages
   - `QuotaManager` - API usage tracking
   - `ChatTranslationManager` - Chat app integration
   - `ScreenshotTranslationManager` - Screenshot translation with hotkeys
   - `UpdateManager` - Sparkle auto-updates
   - `PermissionManager` - macOS permission checks (Accessibility, Screen Recording)

3. **Event Flow**:
   - Global event tap (CGEvent) captures all keyboard/mouse events
   - `InputMonitor.handleEvent()` processes events for translation triggers
   - Pattern matching: `@<lang>` or `#<lang>` triggers translation
   - Double-space detection for quick translation

### Key Subsystems

#### Permission Management
- **PermissionManager**: Handles Accessibility and Screen Recording permissions
- Accessibility required for: reading selected text, inserting translations, app detection
- Screen Recording required for: screenshot translation feature
- Permission flow shows minimal UI on first launch only

#### Translation Pipeline
1. **Trigger Detection**: `InputMonitor` monitors for `@lang` or `#lang` patterns
2. **Text Extraction**:
   - Via Accessibility API (`AXController`) for text fields
   - Via clipboard for chat apps (WeChat/WhatsApp)
   - Via OCR for screenshots (`ScreenshotManager`)
3. **Translation**: `TranslatorClient` sends to backend API with authentication
4. **Result Display**:
   - `TranslationResultWindow` - Main result popup
   - `TranslationStatusWindow` - Loading indicator
   - `TranslationMenuWindow` - Language selection menu
   - `ChatTranslationWindow` - Chat-specific overlay

#### Chat Application Integration
- **AppDetectionManager**: Detects active app via bundle ID (WeChat: com.tencent.xinWeChat, WhatsApp: net.whatsapp.WhatsApp)
- **ChatMessagesProcessor**: Protocol for extracting chat messages via Accessibility API
  - `WeChatMessagesProcessor`
  - `WhatsAppMessagesProcessor`
- **ChatTranslationManager**: Coordinates chat message extraction and translation
- Database stores chat messages with deduplication via SHA-256 hashing

#### Screenshot Translation
- **HotkeyManager**: Carbon-based global hotkey registration (legacy)
- **ModernHotkeyManager**: Uses modern CGEvent monitoring for Command+Shift+S
- **ScreenshotManager**: Captures screen region via macOS screencapture command-line tool
- **ScreenshotTranslationManager**: Orchestrates screenshot → OCR → translation flow
- **ImageTranslationWindow**: SwiftUI interface for screenshot translation results
- **ImageTranslationHistory**: Persistent storage of screenshot translations

#### Authentication & Session
- **SessionManager**: JWT token management, cached validation (5min TTL)
- **UserManager**: User profile and settings
- **EnvironmentManager**: Environment-based API endpoint configuration
- Token stored in UserDefaults (migrated from Keychain to reduce permission prompts)
- Deep link handler for OAuth callback: `glotera://` scheme

#### Performance & Telemetry
- **PerformanceTelemetry**: Tracks translation latency, cache hit rates
- **SimpleMemoryManager**: Manages translation window lifecycle to prevent memory leaks
- **Logger**: File-based logging to ~/Library/Logs/Glotera/ (5MB max, 3 files rotation)
- Event Tap health monitoring: 15-second retry loop with exponential backoff

### Data Storage

#### SQLite Database
- Location: `~/Library/Glotera/desktop.db`
- Initialized from: `desktop/config/desktop.sql` (bundled resource)
- Tables: chat_messages, users, settings, etc.
- Managed by: `DatabaseManager.swift`

#### UserDefaults Storage
- Authentication tokens (migrated from Keychain)
- User preferences and settings
- Permission flow state
- Quota information cache

#### File System
- Logs: `~/Library/Logs/Glotera/glotera.log`
- Database: `~/Library/Glotera/desktop.db`
- Screenshot cache: Temporary directory

### External Dependencies

- **Sparkle 2.7.1**: Auto-update framework (SwiftPM dependency)
  - EdDSA signature verification
  - Appcast feed: Configured via `UpdateManager`
  - See docs/SPARKLE_INTEGRATION.md for details

## Important Implementation Notes

### Event Tap Management
- Event Tap requires Accessibility permission
- Can become invalidated if permission is revoked or system events intervene
- AppDelegate maintains health check timer (15s interval) to restart Event Tap
- When Event Tap fails, app continues but translation triggers won't work

### Chat App Quirks
- **WeChat**: Forces clipboard mode due to Accessibility restrictions. Cannot directly read/write text fields.
- **WhatsApp**: Supports both Accessibility and clipboard modes
- Chat message extraction uses Accessibility element tree traversal (AXUIElement API)
- Element trees documented in: `docs/chat/elementTree/`

### Translation Caching
- InputMonitor maintains 5-minute translation cache to avoid duplicate API calls
- Cache key: SHA-256 hash of (originalText + sourceLanguage + targetLanguage)
- Prevents re-translation when user presses Enter or double-space on same text

### Hotkey Conflicts
- Two hotkey systems coexist:
  - Legacy `HotkeyManager` (Carbon Event Handlers) - being phased out
  - Modern approach via CGEvent tap monitoring in InputMonitor
- Screenshot hotkey: Command+Shift+S (customizable in settings)

### Permission Flow
- First launch: Shows permission setup alerts sequentially
- Accessibility: Opens System Settings > Privacy & Security > Accessibility
- Screen Recording: Shows alert with "Don't remind" option
- Permission state stored in UserDefaults to avoid repeated prompts

## Common Gotchas

1. **Xcode DerivedData path in install_app.sh is hardcoded**: Update if your DerivedData location differs
2. **package.sh expects codesigning**: Developer ID and notarization profile must be configured
3. **Event Tap can silently fail**: Always check logs if translation triggers stop working
4. **Info.plist LSUIElement=YES**: App has no dock icon or main window by design
5. **SQL schema in bundle**: Changes to desktop.sql require rebuilding; migrations handled separately in DatabaseManager

## Testing Notes

- Unit tests: `desktopTests/` (run via `xcodebuild test`)
- UI tests: `desktopUITests/`
- Manual testing: Use Debug menu items (only available in DEBUG builds)
  - Force Clipboard Mode toggle
  - Accessibility Debug Info
  - Print Chat Element Tree
  - Check Logo Bar Status

## Related Documentation

- `docs/SPARKLE_INTEGRATION.md` - Auto-update integration
- `docs/sparkle_update.md` - Update process workflow
- `docs/workflow.md` - Development workflow
- `docs/notarize_my.md` - Notarization process
- `docs/chat/` - Chat app integration details
