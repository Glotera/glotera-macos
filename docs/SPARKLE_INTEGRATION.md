# Sparkle Update System Integration for Glotera Desktop App

## Overview

This document provides step-by-step instructions for integrating Sparkle update framework into the Glotera macOS desktop application.

## 1. Add Sparkle Framework to Xcode Project

### Option A: Using Swift Package Manager (Recommended)
1. Open your Xcode project
2. Go to `File → Add Package Dependencies`
3. Enter URL: `https://github.com/sparkle-project/Sparkle`
4. Select version `2.5.2` or latest
5. Add to your target

### Option B: Manual Installation
1. Download Sparkle from: https://sparkle-project.org/
2. Drag `Sparkle.framework` into your Xcode project
3. Ensure it's added to "Embedded Binaries"

## 2. Generate EdDSA Key Pair for Code Signing (Sparkle 2.7.1+)

```bash
# Generate ed25519 private key (keep this SECRET!)
openssl genpkey -algorithm ed25519 -out eddsa_priv.pem

# Generate public key (embed in app)
openssl pkey -in eddsa_priv.pem -pubout -out eddsa_pub.pem
```

**IMPORTANT**: Store `eddsa_priv.pem` securely. This is used to sign updates.

**Note**: 
- Sparkle 2.7.1+ requires EdDSA (ed25519) keys instead of DSA for security reasons.
- The public key should be added as base64 content directly in Info.plist, not as a file path.

To extract the base64 content from the PEM file:
```bash
grep -v "BEGIN\|END" eddsa_pub.pem | tr -d '\n'
```

## 3. Configure Info.plist

Add these keys to your app's `Info.plist`:

```xml
<!-- Sparkle Configuration -->
<key>SUFeedURL</key>
<string>https://glotera.ai/api/appcast.xml</string>

<key>SUPublicEDKey</key>
<string>MCowBQYDK2VwAyEATaknS0b0arjE4RL9PYjmNIe8EXk7owV/0X7B3TO/gzc=</string>

<key>SUAutomaticallyUpdate</key>
<false/>

<key>SUScheduledCheckInterval</key>
<integer>86400</integer>

<key>SUEnableAutomaticChecks</key>
<true/>

<key>SUShowReleaseNotes</key>
<true/>

<!-- Optional: Custom update check URL for beta users -->
<key>SUFeedURLForChannel</key>
<dict>
    <key>beta</key>
    <string>https://glotera.ai/api/appcast.xml?channel=beta</string>
</dict>
```

## 4. Swift Code Integration

### AppDelegate.swift
```swift
import Cocoa
import Sparkle

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    @IBOutlet var window: NSWindow!
    @IBOutlet var updaterController: SPUStandardUpdaterController!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Start Sparkle updater
        updaterController.startUpdater()
        
        // Optional: Check for updates on first launch
        if isFirstLaunch() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.checkForUpdatesInBackground()
            }
        }
    }
    
    // MARK: - Update Methods
    
    @IBAction func checkForUpdates(_ sender: Any?) {
        updaterController.updater.checkForUpdates()
    }
    
    func checkForUpdatesInBackground() {
        updaterController.updater.checkForUpdatesInBackground()
    }
    
    private func isFirstLaunch() -> Bool {
        let hasLaunchedKey = "HasLaunchedBefore"
        let hasLaunched = UserDefaults.standard.bool(forKey: hasLaunchedKey)
        if !hasLaunched {
            UserDefaults.standard.set(true, forKey: hasLaunchedKey)
            return true
        }
        return false
    }
}
```

### Custom Update Manager (Optional)
```swift
import Sparkle

class UpdateManager: NSObject, ObservableObject {
    static let shared = UpdateManager()
    
    private var updater: SPUUpdater
    @Published var updateAvailable = false
    @Published var updateInfo: SPUAppcastItem?
    
    override init() {
        self.updater = SPUStandardUpdaterController.sharedUpdater()
        super.init()
        
        self.updater.delegate = self
    }
    
    func checkForUpdates() {
        updater.checkForUpdates()
    }
    
    func checkForUpdatesInBackground() {
        updater.checkForUpdatesInBackground()
    }
    
    func setUpdateChannel(_ channel: String) {
        let feedURL = channel == "beta" 
            ? "https://glotera.ai/api/appcast.xml?channel=beta"
            : "https://glotera.ai/api/appcast.xml"
        updater.feedURL = URL(string: feedURL)
    }
}

// MARK: - SPUUpdaterDelegate
extension UpdateManager: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SPUAppcastItem) {
        DispatchQueue.main.async {
            self.updateAvailable = true
            self.updateInfo = item
        }
        
        // Optional: Send analytics
        sendUpdateAnalytics(event: "update_available", 
                          currentVersion: Bundle.main.version,
                          targetVersion: item.versionString)
    }
    
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        DispatchQueue.main.async {
            self.updateAvailable = false
        }
    }
}
```

## 5. Custom Update Analytics (Optional)

Add this to track update events:

```swift
extension UpdateManager {
    private func sendUpdateAnalytics(event: String, currentVersion: String, targetVersion: String? = nil) {
        guard let url = URL(string: "https://glotera.ai/api/app/analytics") else { return }
        
        let payload: [String: Any] = [
            "event_type": event,
            "app_version": currentVersion,
            "target_version": targetVersion ?? "",
            "user_id": UserManager.shared.userId
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            URLSession.shared.dataTask(with: request).resume()
        } catch {
            print("Failed to send analytics: \(error)")
        }
    }
}
```

## 6. Menu Bar Integration

Add update check to your menu:

```swift
// In your menu setup code
let updateMenuItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
updateMenuItem.target = NSApp.delegate
menu.addItem(updateMenuItem)
```

## 7. Build Script for Signing Updates (EdDSA)

Create `sign_update.sh` in your project root:

```bash
#!/bin/bash

# Usage: ./sign_update.sh path/to/glotera-0.1.6.zip

if [ $# -ne 1 ]; then
    echo "Usage: $0 <path-to-zip-file>"
    exit 1
fi

ZIP_FILE="$1"
PRIVATE_KEY_PATH="./eddsa_priv.pem"

if [ ! -f "$PRIVATE_KEY_PATH" ]; then
    echo "Error: Private key not found at $PRIVATE_KEY_PATH"
    exit 1
fi

# Generate EdDSA signature for Sparkle 2.7.1+
SIGNATURE=$(openssl dgst -sha256 -sign "$PRIVATE_KEY_PATH" "$ZIP_FILE" | openssl enc -base64 | tr -d '\n')

echo "EdDSA Signature for $ZIP_FILE:"
echo "$SIGNATURE"

# Calculate file size
FILE_SIZE=$(stat -f%z "$ZIP_FILE")
echo "File size: $FILE_SIZE bytes"

# Calculate SHA256 checksum
CHECKSUM=$(shasum -a 256 "$ZIP_FILE" | cut -d' ' -f1)
echo "SHA256: $CHECKSUM"
```

Make it executable: `chmod +x sign_update.sh`

## 8. Release Process

### Step 1: Build and Archive
1. Set release configuration
2. Archive your app (`Product → Archive`)
3. Export as signed application

### Step 2: Create Update Package
```bash
# Create ZIP for update (preserve app structure)
ditto -c -k --keepParent Glotera.app glotera-0.1.6.zip

# Sign the update
./sign_update.sh glotera-0.1.6.zip
```

### Step 3: Upload and Create Release
1. Upload ZIP to your server: `/web/resources/download/`
2. Use the admin interface at `https://glotera.ai/admin` to create new release
3. Fill in version info, download URL, and DSA signature

### Step 4: Test Update
1. Install old version
2. Check appcast: `https://glotera.ai/appcast.xml`
3. Test update flow

## 9. Testing Checklist

- [ ] Sparkle framework properly linked
- [ ] Info.plist configured correctly
- [ ] DSA public key included in app bundle
- [ ] Appcast XML accessible and valid
- [ ] Update checking works (manual and automatic)
- [ ] Download and installation works
- [ ] App launches correctly after update
- [ ] Rollback works if update fails

## 10. Channel Management

### Stable Channel (Default)
- URL: `https://glotera.ai/api/appcast.xml`
- Fully tested releases only
- 24-hour check interval

### Beta Channel
- URL: `https://glotera.ai/api/appcast.xml?channel=beta`
- Early access releases
- 12-hour check interval

### Development Channel
- URL: `https://glotera.ai/api/appcast.xml?channel=dev`
- Latest builds for internal testing
- 6-hour check interval

## 11. Troubleshooting

### Common Issues:

1. **Update not detected**
   - Check appcast.xml syntax
   - Verify version comparison logic
   - Check rollout percentage

2. **Download fails**
   - Verify download URL accessibility
   - Check file permissions
   - Verify DSA signature

3. **Installation fails**
   - Check app code signing
   - Verify notarization status
   - Check disk space and permissions

### Debug Commands:
```bash
# Test appcast parsing
curl "https://glotera.ai/api/appcast.xml?version=0.1.5&user_id=test"

# Check version API

# Validate XML
xmllint --noout https://glotera.ai/api/appcast.xml
```

## 12. Security Considerations

1. **Keep private key secure**: Never commit `dsa_priv.pem` to version control
2. **Use HTTPS only**: All update URLs must use HTTPS
3. **Verify signatures**: Always include DSA signature for releases
4. **Code signing**: Ensure all releases are properly code signed
5. **Gradual rollouts**: Use rollout percentage for safer deployments

## 13. Admin Interface

Access the release management interface at: `https://glotera.ai/admin`

Features:
- View all versions and their status
- Create new releases
- Manage rollout percentages
- View update analytics
- Activate/deactivate versions

This completes the Sparkle integration for Glotera's update system.