# Glotera macOS Open Source Security Checklist

## ⚠️ Critical - Must Remove Before Publishing

### 1. Private Keys and Certificates
- [ ] **eddsa_priv.pem** - Sparkle EdDSA private key (CRITICAL)
- [ ] **eddsa_pub.pem** - Sparkle EdDSA public key (recommended to keep, but regenerate pair)
- [ ] Any .p12 or .key files in the project

### 2. Apple Developer Credentials
Files containing sensitive Apple Developer information:
- [ ] **package.sh** (line 17) - Developer ID: "Xinbo Zhang (6Q3GB859VC)"
- [ ] **package.sh** (line 18) - Keychain profile: "glotera-profile"
- [ ] **package.sh** (line 210) - Team ID: 6Q3GB859VC
- [ ] **package.sh** (line 324) - Apple ID: glotera.ai@gmail.com
- [ ] **docs/notarize_my.md** (multiple lines) - Contains Apple ID, Team ID, and app-specific password
- [ ] **export_options.plist** - Team ID: 6Q3GB859VC
- [ ] **desktop.xcodeproj/project.pbxproj** - Team ID: 6Q3GB859VC

### 3. Email Addresses
- [ ] **package.sh** - glotera.ai@gmail.com
- [ ] **docs/notarize_my.md** - glotera.ai@gmail.com, yikebocai@gmail.com
- [ ] **desktop/EnvironmentManager.swift** (line 229) - support@glotera.ai

### 4. API Endpoints (Review)
Current production endpoints in **desktop/EnvironmentManager.swift**:
- https://glotera.ai (base URL)
- https://api.glotera.ai (API server)

**Decision needed**: Keep these or replace with placeholder/configurable values?

### 5. Documentation to Remove or Sanitize
- [ ] **docs/notarize_my.md** - Contains complete notarization tutorial with real credentials
- [ ] **CLAUDE.md** - Contains project-specific instructions (keep but review)

## ⚠️ Recommended Actions

### 1. Update .gitignore
Add the following entries:
```
# Signing keys
*.pem
*.key
*.p12

# Apple Developer credentials
export_options.plist

# Build artifacts
build/
release/
*.xcarchive
*.app
*.dmg
*.zip

# macOS
.DS_Store
```

### 2. Replace Hardcoded Credentials

#### package.sh - Parameterize credentials:
```bash
# Replace:
DEVELOPER_ID="Developer ID Application: Xinbo Zhang (6Q3GB859VC)"
KEYCHAIN_PROFILE="glotera-profile"

# With environment variables or config file:
DEVELOPER_ID="${DEVELOPER_ID:-Developer ID Application: YOUR_NAME (TEAM_ID)}"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-your-profile}"
```

#### docs/notarize_my.md - Create generic template:
Remove the app-specific password and real credentials, replace with placeholders:
```bash
xcrun notarytool store-credentials "your-profile" \
  --apple-id your-apple-id@example.com \
  --team-id YOUR_TEAM_ID \
  --password YOUR_APP_SPECIFIC_PASSWORD
```

### 3. Environment Configuration

Consider creating a template configuration file:

**config/developer.env.template**:
```bash
# Apple Developer Configuration
DEVELOPER_ID="Developer ID Application: YOUR NAME (TEAM_ID)"
TEAM_ID="YOUR_TEAM_ID"
APPLE_ID="your-email@example.com"
KEYCHAIN_PROFILE="your-profile"

# Sparkle Update Keys
# Generate using: ../Sparkle-2.7.1/bin/generate_keys
SPARKLE_PRIVATE_KEY_PATH="./eddsa_priv.pem"
SPARKLE_PUBLIC_KEY_PATH="./eddsa_pub.pem"
```

### 4. Update References in Code

Files to update with placeholders:
- desktop.xcodeproj/project.pbxproj (Team ID)
- export_options.plist (Team ID)
- package.sh (Developer ID, Team ID, Apple ID)

### 5. Build Artifacts Cleanup

Remove or move to private location:
- [ ] **build/** directory (contains compiled apps with your signature)
- [ ] **release/** directory (contains packaged apps with your credentials)
- [ ] **desktop/build/** directory

## ✅ Safe to Keep (Public Information)

These items contain only public/domain information:
- Desktop app source code (Swift files)
- UI assets and resources
- SQLite database schema (config/desktop.sql)
- Language configuration (config/language-iso-639.json)
- Public documentation (CLAUDE.md - after review)
- Test files

## 📋 Pre-Publication Checklist

- [ ] Generate new Sparkle key pair for public distribution
- [ ] Remove all instances of Team ID (6Q3GB859VC)
- [ ] Remove all instances of Apple ID (glotera.ai@gmail.com)
- [ ] Remove all instances of developer name (Xinbo Zhang)
- [ ] Create template files for credentials
- [ ] Update package.sh to use environment variables
- [ ] Clean and remove build/ and release/ directories
- [ ] Update .gitignore with comprehensive patterns
- [ ] Sanitize docs/notarize_my.md with placeholders
- [ ] Test build process with new configuration system
- [ ] Add CONTRIBUTING.md with setup instructions for contributors
- [ ] Add LICENSE file
- [ ] Update README.md with clear setup instructions

## 🔐 Security Best Practices

1. **Never commit**:
   - Private keys (.pem, .key, .p12)
   - App-specific passwords
   - API tokens or secrets
   - Signed/notarized binaries

2. **Use environment variables** for all sensitive configuration

3. **Provide templates** for required configuration files

4. **Document** the setup process clearly for contributors

## 📝 Suggested README Sections for Open Source

Add these sections to README.md:

### For Contributors - Apple Developer Setup
```markdown
## Development Setup

### Prerequisites
- macOS 13.0 or later
- Xcode 14.0 or later
- Apple Developer account (for code signing and notarization)

### Configuration
1. Copy `config/developer.env.template` to `config/developer.env`
2. Fill in your Apple Developer credentials
3. Generate Sparkle update keys: `../Sparkle-2.7.1/bin/generate_keys`
4. Configure Xcode with your Team ID

See CONTRIBUTING.md for detailed setup instructions.
```

## 🎯 Summary

**Critical removals**: 3 items (private keys, credentials in docs)
**High priority**: 5 items (hardcoded Team IDs, Apple IDs, developer name)
**Recommended**: 8 items (configuration refactoring, build cleanup)

**Estimated effort**: 2-3 hours to properly sanitize and refactor
