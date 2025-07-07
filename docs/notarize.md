# Correct Mac App Notarization Steps

## Issues with Current Process
The "team is not configured" error typically occurs due to:
1. Using generic password instead of app-specific password
2. Missing bundle ID verification
3. Improper entitlements handling
4. Incorrect team ID configuration

## Prerequisites
- Apple Developer Account ($99/year)
- Valid Developer ID Application certificate
- App-specific password (NOT regular Apple ID password)

## Step 1: Generate App-Specific Password
1. Go to https://appleid.apple.com
2. Sign in with your Apple ID (glotera.ai@gmail.com)
3. Go to "Security" section
4. Under "App-Specific Passwords", click "Generate Password"
5. Label it "Glotera Notarization"
6. Save the generated password (format: xxxx-xxxx-xxxx-xxxx)

## Step 2: Verify Certificate Installation
```bash
security find-identity -v -p codesigning
```
Should show:
```
3) 90E8D8FA31547D951B07B1E83687BA35F7B7D4AB "Developer ID Application: Xinbo Zhang (6Q3GB859VC)"
```

## Step 3: Verify Bundle ID and Team Configuration
Check that your app's bundle ID matches your Apple Developer account:
```bash
# Check current bundle ID
plutil -p release/Glotera-0.2.0/Glotera.app/Contents/Info.plist | grep CFBundleIdentifier
# Should show: "CFBundleIdentifier" => "ai.glotera.desktop"
```

Verify in Xcode:
- Project Settings > Signing & Capabilities
- Team should be: "Xinbo Zhang (6Q3GB859VC)"
- Bundle Identifier: "ai.glotera.desktop"

## Step 4: Export App from Xcode
Xcode → Product → Archive → Distribute App → Custom → Copy App

## Step 5: Verify Entitlements Before Signing
```bash
# Check entitlements
codesign -d --entitlements - release/Glotera-0.2.0/Glotera.app
# Should show hardened runtime and any required entitlements
```

## Step 6: Code Signing (Corrected)
```bash
# Sign with proper entitlements
codesign --force \
  --sign "Developer ID Application: Xinbo Zhang (6Q3GB859VC)" \
  --options runtime \
  --entitlements desktop/desktop.entitlements \
  --timestamp \
  --verbose \
  release/Glotera-0.2.0/Glotera.app

# Verify signing
codesign --verify --verbose=4 release/Glotera-0.2.0/Glotera.app
spctl --assess --type exec --verbose release/Glotera-0.2.0/Glotera.app
```

## Step 7: Create ZIP for Notarization
```bash
ditto -c -k --keepParent release/Glotera-0.2.0/Glotera.app glotera-0.2.0.zip
```

## Step 8: Setup Notarytool Profile (CORRECTED)
```bash
xcrun notarytool store-credentials "glotera-profile2" \
  --apple-id "glotera.ai@gmail.com" \
  --team-id "6Q3GB859VC" \
  --password "mnop-ypju-znye-yzsi"
```
**Important**: Replace with your actual app-specific password from Step 1

## Step 9: Submit for Notarization
```bash
xcrun notarytool submit glotera-0.2.0.zip \
  --keychain-profile "glotera-profile2" \
  --wait
```

## Step 10: Check Notarization Status
```bash
# View history
xcrun notarytool history --keychain-profile "glotera-profile2"

# Check specific submission (if needed)
xcrun notarytool log 38658fe3-5761-4cac-97a7-fef400849d68 --keychain-profile "glotera-profile2"
```

## Step 11: Staple Notarization (After Success)
```bash
xcrun stapler staple release/Glotera-0.2.0/Glotera.app
```

## Step 12: Final Verification
```bash
# Verify app is properly notarized
spctl --assess --type exec --verbose release/Glotera-0.2.0/Glotera.app

# Should show: accepted
# source=Notarized Developer ID
```

## Common Issues and Solutions

### "team is not configured"
- Ensure you're using app-specific password, not regular password
- Verify team ID matches your Apple Developer account
- Check bundle ID is registered in your Apple Developer account

### "invalid signature"
- Re-export from Xcode with proper signing
- Ensure entitlements file exists and is correct
- Use --timestamp flag in codesign

### "notarization failed"
- Check the log with `notarytool log SUBMISSION-ID`
- Common issues: missing entitlements, unsigned frameworks, hardened runtime issues

## Key Changes from Original Process:
1. ✅ Use app-specific password instead of generic password
2. ✅ Added entitlements verification and proper signing order
3. ✅ Added bundle ID verification steps
4. ✅ Added timestamp to code signing for better security
5. ✅ Added proper verification steps at each stage
6. ✅ Added troubleshooting section for common errors