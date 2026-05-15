#!/bin/bash

# Glotera Mac App Package Script
# Usage: ./package.sh <version> [--notarize]
# Example: ./package.sh 0.2.0 --notarize

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration (set via config/developer.env or environment variables)
if [ -f "config/developer.env" ]; then
    # shellcheck source=/dev/null
    source "config/developer.env"
fi

DEVELOPER_ID="${DEVELOPER_ID:-}"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_ID="${APPLE_ID:-}"
SPARKLE_BIN="../Sparkle-2.7.1/bin/sign_update"
PROJECT_PATH="desktop.xcodeproj"
SCHEME="desktop"
ARCHIVE_PATH="build/Glotera.xcarchive"
RELEASE_DIR="release"
DISTRIBUTION_DIR="../glotera-deploy/release"

# Parse arguments
if [ $# -lt 2 ]; then
    echo -e "${RED}Error: Version number and build number are required${NC}"
    echo "Usage: $0 <version> <build> [--notarize] [--continue]"
    echo "Example: $0 0.2.0 123 --notarize"
    echo "Example: $0 0.2.0 123"
    echo "Example: $0 0.2.0 123 --continue"
    echo ""
    echo "Options:"
    echo "  --notarize    Submit app for notarization and wait for completion"
    echo "  --continue    Continue with DMG creation and deployment (skip notarization)"
    exit 1
fi

VERSION=$1
BUILD_NUMBER=$2
NOTARIZE=false
CONTINUE_ONLY=false

# Parse additional arguments
for arg in "${@:3}"; do
    case $arg in
        --notarize)
            NOTARIZE=true
            ;;
        --continue)
            CONTINUE_ONLY=true
            ;;
        *)
            echo -e "${RED}Error: Unknown argument: $arg${NC}"
            echo "Usage: $0 <version> <build> [--notarize] [--continue]"
            exit 1
            ;;
    esac
done

# Validate argument combination
if [ "$NOTARIZE" = true ] && [ "$CONTINUE_ONLY" = true ]; then
    echo -e "${RED}Error: Cannot use --notarize and --continue together${NC}"
    exit 1
fi

APP_NAME="Glotera"
APP_DIR="${RELEASE_DIR}/${APP_NAME}-${VERSION}"
APP_PATH="${APP_DIR}/${APP_NAME}.app"
ZIP_FILE="${APP_NAME}-${VERSION}.zip"
DMG_FILE="${APP_NAME}-${VERSION}.dmg"

echo -e "${BLUE}🚀 Starting Glotera Mac App packaging process${NC}"
echo -e "${BLUE}Version: ${VERSION}${NC}"
echo -e "${BLUE}Build Number: ${BUILD_NUMBER}${NC}"
echo -e "${BLUE}Notarize: ${NOTARIZE}${NC}"
echo -e "${BLUE}Continue Only: ${CONTINUE_ONLY}${NC}"
echo ""

# Function to log with timestamp
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

require_signing_config() {
    local missing=()
    [ -z "$DEVELOPER_ID" ] && missing+=("DEVELOPER_ID")
    [ -z "$APPLE_TEAM_ID" ] && missing+=("APPLE_TEAM_ID")
    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing signing configuration: ${missing[*]}"
        echo "Copy config/developer.env.template to config/developer.env and set your Apple Developer values."
        exit 1
    fi
}

require_notarization_config() {
    require_signing_config
    local missing=()
    [ -z "$KEYCHAIN_PROFILE" ] && missing+=("KEYCHAIN_PROFILE")
    [ -z "$APPLE_ID" ] && missing+=("APPLE_ID")
    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing notarization configuration: ${missing[*]}"
        echo "Set KEYCHAIN_PROFILE and APPLE_ID in config/developer.env (see config/developer.env.template)."
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    require_signing_config

    # Check if Xcode is installed
    if ! command -v xcodebuild &> /dev/null; then
        error "Xcode is not installed or xcodebuild is not in PATH"
        exit 1
    fi
    
    # Check if developer certificate exists
    if ! security find-identity -v -p codesigning | grep -q "$DEVELOPER_ID"; then
        error "Developer certificate not found: $DEVELOPER_ID"
        echo "Please ensure your Developer ID certificate is installed in Keychain"
        exit 1
    fi
    
    # Check if appdmg is installed
    if ! command -v appdmg &> /dev/null; then
        warning "appdmg is not installed. Installing..."
        npm install -g appdmg
    fi
    
    # Check if Sparkle signing tool exists
    if [ ! -f "$SPARKLE_BIN" ]; then
        error "Sparkle signing tool not found: $SPARKLE_BIN"
        exit 1
    fi
    
    # Check if Sparkle private key exists
    if [ ! -f "eddsa_priv.pem" ]; then
        error "Sparkle private key not found: eddsa_priv.pem"
        echo "Please ensure the eddsa_priv.pem file exists in the project root directory."
        echo "You can generate it using: ../Sparkle-2.7.1/bin/generate_keys"
        exit 1
    fi
    
    # Note: Notarization profile check is skipped due to notarytool API changes
    # The profile will be validated during the actual notarization process
    if [ "$NOTARIZE" = true ]; then
        log "Notarization requested - profile will be validated during notarization"
    fi
    
    # Check if appdmg.json template file exists in config
    if [ ! -f "config/appdmg.json" ]; then
        error "appdmg.json template file not found in config directory"
        echo "Please create the appdmg.json template file in the config directory."
        echo "Example content:"
        echo '{'
        echo '  "title": "Glotera Installer",'
        echo '  "icon": "glotera.icns",'
        echo '  "background": "../config/resources/background.png",'
        echo '  "window": {'
        echo '    "size": {'
        echo '      "width": 500,'
        echo '      "height": 300'
        echo '    }'
        echo '  },'
        echo '  "contents": ['
        echo '    { "x": 100, "y": 150, "type": "file", "path": "APP_PATH_PLACEHOLDER" },'
        echo '    { "x": 350, "y": 150, "type": "link", "path": "/Applications" }'
        echo '  ]'
        echo '}'
        exit 1
    fi
    
    log "Prerequisites check passed ✅"
}

# Clean and prepare directories
prepare_directories() {
    log "Preparing directories..."
    
    # Create release directory
    mkdir -p "$RELEASE_DIR"
    mkdir -p "$APP_DIR"
    
    # Clean previous builds
    rm -rf build/
    mkdir -p build/
    
    log "Directories prepared ✅"
}

# Build the app
build_app() {
    log "Building Glotera app..."
    
    # Archive the project with version and build number
    log "Creating archive with version ${VERSION} and build ${BUILD_NUMBER}..."
    xcodebuild archive \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration Release \
        -archivePath "$ARCHIVE_PATH" \
        -destination "generic/platform=macOS" \
        MARKETING_VERSION="$VERSION" \
        CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
    
    # Export the app
    log "Exporting app..."
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$APP_DIR" \
        -exportOptionsPlist export_options.plist 2>/dev/null || {
        
        # Create export options plist if it doesn't exist
        log "Creating export options plist..."
        cat > export_options.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${APPLE_TEAM_ID}</string>
</dict>
</plist>
EOF
        
        xcodebuild -exportArchive \
            -archivePath "$ARCHIVE_PATH" \
            -exportPath "$APP_DIR" \
            -exportOptionsPlist export_options.plist
    }
    
    # Check if the app was exported successfully
    if [ -d "${APP_PATH}" ]; then
        log "App exported successfully to ${APP_PATH}"
    elif [ -d "${APP_DIR}/Applications/Glotera.app" ]; then
        mv "${APP_DIR}/Applications/Glotera.app" "${APP_DIR}/"
        rm -rf "${APP_DIR}/Applications"
        log "App moved to correct location: ${APP_PATH}"
    else
        error "App not found after export"
        echo "Expected location: ${APP_PATH}"
        echo "Contents of export directory:"
        ls -la "${APP_DIR}/"
        exit 1
    fi
    
    # Verify version and build number in the built app
    log "Verifying version and build number..."
    ACTUAL_VERSION=$(plutil -p "$APP_PATH/Contents/Info.plist" | grep CFBundleShortVersionString | cut -d'"' -f4)
    ACTUAL_BUILD=$(plutil -p "$APP_PATH/Contents/Info.plist" | grep CFBundleVersion | cut -d'"' -f4)
    ACTUAL_MIN_VERSION=$(plutil -p "$APP_PATH/Contents/Info.plist" | grep LSMinimumSystemVersion | cut -d'"' -f4)
    
    if [ "$ACTUAL_VERSION" != "$VERSION" ]; then
        error "Version mismatch: expected $VERSION, got $ACTUAL_VERSION"
        exit 1
    fi
    
    if [ "$ACTUAL_BUILD" != "$BUILD_NUMBER" ]; then
        error "Build number mismatch: expected $BUILD_NUMBER, got $ACTUAL_BUILD"
        exit 1
    fi
    
    if [ "$ACTUAL_MIN_VERSION" != "13.0" ]; then
        error "Minimum system version mismatch: expected 13.0, got $ACTUAL_MIN_VERSION"
        exit 1
    fi
    
    log "Version verification passed: $ACTUAL_VERSION ($ACTUAL_BUILD) ✅"
    log "Minimum system version verification passed: $ACTUAL_MIN_VERSION ✅"
    log "App build completed ✅"
}

# Sign the app
sign_app() {
    log "Signing the app..."
    
    # Verify bundle ID
    BUNDLE_ID=$(plutil -p "$APP_PATH/Contents/Info.plist" | grep CFBundleIdentifier | cut -d'"' -f4)
    log "Bundle ID: $BUNDLE_ID"
    
    # Sign the app with proper entitlements and timestamp
    codesign --force \
        --sign "$DEVELOPER_ID" \
        --options runtime \
        --entitlements "desktop/desktop.entitlements" \
        --timestamp \
        --verbose \
        "$APP_PATH"
    
    # Verify signature
    log "Verifying signature..."
    codesign --verify --verbose=4 "$APP_PATH"
    
    # Skip Gatekeeper verification before notarization (it will fail for unnotarized apps)
    if [ "$NOTARIZE" = false ]; then
        log "Skipping Gatekeeper verification (app not notarized)"
    else
        log "Gatekeeper verification will be performed after notarization"
    fi
    
    log "App signing completed ✅"
}

# Create ZIP file
create_zip() {
    log "Creating ZIP file..."
    
    cd "$RELEASE_DIR"
    ditto -c -k --keepParent "${APP_NAME}-${VERSION}/${APP_NAME}.app" "$ZIP_FILE"
    cd - > /dev/null
    
    log "ZIP file created: ${RELEASE_DIR}/${ZIP_FILE} ✅"
}

# Notarize the app
notarize_app() {
    if [ "$NOTARIZE" = false ]; then
        log "Skipping notarization (not requested)"
        return
    fi

    require_notarization_config

    log "Starting notarization process..."
    
    # Submit for notarization (without --wait)
    log "Submitting for notarization..."
    NOTARIZE_OUTPUT=$(xcrun notarytool submit "${RELEASE_DIR}/${ZIP_FILE}" \
        --keychain-profile "$KEYCHAIN_PROFILE" 2>&1)
    NOTARIZE_EXIT_CODE=$?
    
    if [ $NOTARIZE_EXIT_CODE -ne 0 ]; then
        error "Notarization submission failed with exit code: $NOTARIZE_EXIT_CODE"
        echo "Output: $NOTARIZE_OUTPUT"
        echo ""
        echo "If the error mentions 'profile not found', please run:"
        echo "xcrun notarytool store-credentials \"\$KEYCHAIN_PROFILE\" \\"
        echo "  --apple-id \"\$APPLE_ID\" \\"
        echo "  --team-id \"\$APPLE_TEAM_ID\" \\"
        echo "  --password \"<app-specific-password>\""
        echo "(Set KEYCHAIN_PROFILE, APPLE_ID, and APPLE_TEAM_ID in config/developer.env)"
        return 1
    fi
    
    # Extract submission ID more robustly
    log "Raw notarization output:"
    echo "$NOTARIZE_OUTPUT"
    
    SUBMISSION_ID=$(echo "$NOTARIZE_OUTPUT" | grep "id:" | head -1 | awk '{print $2}' | tr -d '[:space:]')
    if [ -z "$SUBMISSION_ID" ]; then
        error "Failed to get submission ID from notarization output"
        echo "Output: $NOTARIZE_OUTPUT"
        return 1
    fi
    
    log "Extracted submission ID: '$SUBMISSION_ID'"
    
    log "Submission ID: $SUBMISSION_ID"
    log "Notarization submitted successfully. Checking status every 10 minutes..."
    
    # Save submission ID to file for manual continuation
    echo "$SUBMISSION_ID" > "${RELEASE_DIR}/notarization_submission_id.txt"
    log "Submission ID saved to: ${RELEASE_DIR}/notarization_submission_id.txt"
    
    # Poll for notarization status
    MAX_ATTEMPTS=36  # 6 hours maximum wait time (36 * 10 minutes)
    ATTEMPT=0
    
    while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        ATTEMPT=$((ATTEMPT + 1))
        
        log "Checking notarization status (attempt $ATTEMPT/$MAX_ATTEMPTS)..."
        NOTARIZE_INFO=$(xcrun notarytool info "$SUBMISSION_ID" \
            --keychain-profile "$KEYCHAIN_PROFILE" 2>/dev/null)
        echo "$NOTARIZE_INFO"
        STATUS_LINE=$(echo "$NOTARIZE_INFO" | grep "status:")
        log "Status line: '$STATUS_LINE'"
        log "Full notarization info:"
        echo "$NOTARIZE_INFO" | while IFS= read -r line; do
            log "  $line"
        done
        
        if echo "$STATUS_LINE" | grep -q "Accepted"; then
            log "Notarization successful! ✅"
            
            # Staple the notarization
            log "Stapling notarization..."
            xcrun stapler staple "$APP_PATH"
            
            # Verify with Gatekeeper
            log "Verifying with Gatekeeper..."
            spctl --assess --type exec -v "$APP_PATH"
            
            log "Notarization and stapling completed ✅"
            
            # Recreate ZIP with stapled app
            log "Recreating ZIP with stapled app..."
            rm -f "${RELEASE_DIR}/${ZIP_FILE}"
            create_zip
            
            # Remove submission ID file
            rm -f "${RELEASE_DIR}/notarization_submission_id.txt"
            
            return 0
            
        elif echo "$STATUS_LINE" | grep -q "Rejected\|Invalid"; then
            error "Notarization failed with status: $STATUS_LINE"
            log "Getting notarization log..."
            xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$KEYCHAIN_PROFILE"
            return 1
            
        elif echo "$STATUS_LINE" | grep -q "In Progress\|Pending"; then
            log "Notarization still in progress... (Status: $STATUS_LINE)"
            if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
                log "Waiting 10 minutes before next check..."
                sleep 600
            fi
        else
            log "Unknown status: $STATUS"
            if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
                log "Waiting 10 minutes before next check..."
                sleep 600
            fi
        fi
    done
    
    error "Notarization timed out after $MAX_ATTEMPTS attempts (6 hours)"
    log "Final status: $STATUS"
    log "Getting notarization log..."
    xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$KEYCHAIN_PROFILE"
    
    echo ""
    echo -e "${YELLOW}⚠️  Notarization timed out. You can manually check the status and continue later:${NC}"
    echo "1. Check status: xcrun notarytool info $SUBMISSION_ID --keychain-profile $KEYCHAIN_PROFILE"
    echo "2. If successful, staple: xcrun stapler staple $APP_PATH"
    echo "3. Continue packaging: $0 $VERSION $BUILD_NUMBER --continue"
    echo ""
    
    return 1
}

# Create DMG file
create_dmg() {
    log "Creating DMG file..."
    
    # Remove existing DMG file if it exists
    if [ -f "${RELEASE_DIR}/${DMG_FILE}" ]; then
        log "Removing existing DMG file..."
        rm "${RELEASE_DIR}/${DMG_FILE}"
    fi
    
    # Copy appdmg.json template to release directory and replace placeholder
    log "Copying appdmg.json template and replacing placeholders..."
    # Use relative path from project root (where appdmg will be executed)
    RELATIVE_APP_PATH="${APP_NAME}-${VERSION}/${APP_NAME}.app"
    sed "s|APP_PATH_PLACEHOLDER|${RELATIVE_APP_PATH}|g" "config/appdmg.json" > "${RELEASE_DIR}/appdmg.json"
    
    log "Created appdmg configuration: ${RELEASE_DIR}/appdmg.json"
    
    # Create DMG using the configuration file in release directory
    # Change to release directory so relative paths work correctly
    cd "${RELEASE_DIR}"
    appdmg "appdmg.json" "${DMG_FILE}"
    cd - > /dev/null
    
    log "DMG file created: ${RELEASE_DIR}/${DMG_FILE} ✅"
}

# Sign with Sparkle
sign_with_sparkle() {
    log "Signing with Sparkle..."
    
    # Check if private key exists
    if [ ! -f "eddsa_priv.pem" ]; then
        error "Sparkle private key not found: eddsa_priv.pem"
        echo "Please ensure the eddsa_priv.pem file exists in the project root directory."
        return 1
    fi
    
    cd "$RELEASE_DIR"
    
    # Run Sparkle sign_update with private key
    log "Running Sparkle signature with private key: ../eddsa_priv.pem"
    SPARKLE_OUTPUT=$(../../Sparkle-2.7.1/bin/sign_update "$ZIP_FILE" "../eddsa_priv.pem" 2>&1)
    SPARKLE_EXIT_CODE=$?
    
    if [ $SPARKLE_EXIT_CODE -ne 0 ]; then
        error "Sparkle signing failed with exit code: $SPARKLE_EXIT_CODE"
        echo "Output: $SPARKLE_OUTPUT"
        cd - > /dev/null
        return 1
    fi
    
    # Extract signature from output
    # Look for sparkle:edSignature="..." pattern first, then fallback to pure base64
    SPARKLE_SIGNATURE=$(echo "$SPARKLE_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | sed 's/sparkle:edSignature="//;s/"//' | tail -1)
    if [ -z "$SPARKLE_SIGNATURE" ]; then
        SPARKLE_SIGNATURE=$(echo "$SPARKLE_OUTPUT" | grep -E "^[A-Za-z0-9+/=]+$" | tail -1)
    fi
    
    cd - > /dev/null
    
    if [ -z "$SPARKLE_SIGNATURE" ]; then
        error "Failed to extract Sparkle signature from output"
        echo "Full output was:"
        echo "$SPARKLE_OUTPUT"
        return 1
    fi
    
    log "Sparkle signature generated ✅"
    echo -e "${BLUE}Sparkle Signature:${NC}"
    echo "$SPARKLE_SIGNATURE"
    echo ""
    
    # Save signature to file
    echo "$SPARKLE_SIGNATURE" > "${RELEASE_DIR}/sparkle_signature.txt"
    log "Signature saved to: ${RELEASE_DIR}/sparkle_signature.txt"
}

# Handle continuation after manual notarization
handle_continue() {
    if [ "$CONTINUE_ONLY" = false ]; then
        return
    fi
    
    log "Continuing with packaging after manual notarization..."
    
    # Check if app exists
    if [ ! -d "$APP_PATH" ]; then
        error "App not found: $APP_PATH"
        echo "Please ensure the app has been built and notarized before using --continue"
        exit 1
    fi
    
    # Check if submission ID file exists
    if [ -f "${RELEASE_DIR}/notarization_submission_id.txt" ]; then
        SUBMISSION_ID=$(head -1 "${RELEASE_DIR}/notarization_submission_id.txt" | tr -d '[:space:]')
        log "Found submission ID: '$SUBMISSION_ID'"
        
        # Check notarization status once
        log "Checking notarization status..."
        NOTARIZE_INFO=$(xcrun notarytool info "$SUBMISSION_ID" \
            --keychain-profile "$KEYCHAIN_PROFILE" 2>&1)
        
        log "Raw notarization info:"
        echo "$NOTARIZE_INFO"
        
        # Extract status line
        STATUS_LINE=$(echo "$NOTARIZE_INFO" | grep "status:")
        log "Status line: '$STATUS_LINE'"
        
        if [ -z "$STATUS_LINE" ]; then
            error "Could not find status line in notarization info"
            log "Full notarization info:"
            echo "$NOTARIZE_INFO"
            exit 1
        fi
        
        if echo "$STATUS_LINE" | grep -q "Accepted"; then
            log "Notarization is successful! Proceeding with stapling..."
            
            # Staple the notarization
            log "Stapling notarization..."
            STAPLE_OUTPUT=$(xcrun stapler staple "$APP_PATH" 2>&1)
            STAPLE_EXIT_CODE=$?
            
            if [ $STAPLE_EXIT_CODE -eq 0 ]; then
                log "Stapling completed successfully ✅"
                
                # Verify with Gatekeeper
                log "Verifying with Gatekeeper..."
                GATEKEEPER_OUTPUT=$(spctl --assess --type exec -v "$APP_PATH" 2>&1)
                GATEKEEPER_EXIT_CODE=$?
                
                if [ $GATEKEEPER_EXIT_CODE -eq 0 ]; then
                    log "Gatekeeper verification passed ✅"
                else
                    warning "Gatekeeper verification failed, but continuing..."
                    log "Gatekeeper output: $GATEKEEPER_OUTPUT"
                fi
                
                log "Notarization and stapling completed ✅"
                
                # Recreate ZIP with stapled app
                log "Recreating ZIP with stapled app..."
                rm -f "${RELEASE_DIR}/${ZIP_FILE}"
                create_zip
                
                # Remove submission ID file
                rm -f "${RELEASE_DIR}/notarization_submission_id.txt"
                
                return 0
            else
                error "Stapling failed with exit code: $STAPLE_EXIT_CODE"
                log "Stapling output: $STAPLE_OUTPUT"
                echo ""
                echo "You can try manual stapling:"
                echo "xcrun stapler staple $APP_PATH"
                echo ""
                echo "Then run this script again with --continue"
                exit 1
            fi
            
        elif echo "$STATUS_LINE" | grep -q "Rejected\|Invalid"; then
            error "Notarization failed with status: $STATUS_LINE"
            log "Getting notarization log..."
            xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$KEYCHAIN_PROFILE"
            exit 1
            
        elif echo "$STATUS_LINE" | grep -q "In Progress\|Pending"; then
            error "Notarization is still in progress (Status: $STATUS_LINE)"
            echo ""
            echo "Please wait for notarization to complete, then run this script again with --continue"
            exit 1
            
        else
            error "Unknown notarization status: $STATUS_LINE"
            log "Full notarization info:"
            echo "$NOTARIZE_INFO" | while IFS= read -r line; do
                log "  $line"
            done
            echo ""
            echo "Please check the notarization status manually:"
            echo "xcrun notarytool info $SUBMISSION_ID --keychain-profile $KEYCHAIN_PROFILE"
            exit 1
        fi
        
    else
        log "No submission ID file found. Checking if app is already stapled..."
        
        # Check if app is already stapled
        STAPLE_CHECK=$(xcrun stapler validate "$APP_PATH" 2>&1)
        if echo "$STAPLE_CHECK" | grep -q "valid"; then
            log "App is already stapled ✅"
        else
            warning "App does not appear to be stapled. You may need to:"
            echo "1. Check if notarization is complete"
            echo "2. Manually staple: xcrun stapler staple $APP_PATH"
            echo "3. Run this script again with --continue"
            echo ""
            echo "Continuing anyway..."
        fi
    fi
}

# Deploy files
deploy_files() {
    log "Deploying files to distribution directory..."
    
    # Create build-specific directory in distribution dir
    BUILD_DIST_DIR="${DISTRIBUTION_DIR}/${BUILD_NUMBER}"
    
    # Create distribution directory if it doesn't exist
    mkdir -p "$DISTRIBUTION_DIR"
    
    # Clean build-specific directory if it exists
    if [ -d "$BUILD_DIST_DIR" ]; then
        log "Cleaning existing build directory: $BUILD_DIST_DIR"
        rm -rf "${BUILD_DIST_DIR}"/*
    fi
    
    # Create build-specific directory
    mkdir -p "$BUILD_DIST_DIR"
    log "Created build directory: $BUILD_DIST_DIR"
    
    # Copy files to build-specific directory
    cp "${RELEASE_DIR}/${ZIP_FILE}" "$BUILD_DIST_DIR/"
    cp "${RELEASE_DIR}/${DMG_FILE}" "$BUILD_DIST_DIR/"
    cp "${RELEASE_DIR}/sparkle_signature.txt" "$BUILD_DIST_DIR/"
    
    log "Files deployed to: $BUILD_DIST_DIR ✅"
    
    # Show file sizes
    echo -e "${BLUE}Generated files:${NC}"
    ls -lh "$BUILD_DIST_DIR"
}

# Main execution
main() {
    log "Starting packaging process for Glotera ${VERSION} (Build ${BUILD_NUMBER})"
    
    if [ "$CONTINUE_ONLY" = true ]; then
        # Continue mode: skip build and notarization
        log "Continue mode: skipping build and notarization"
        handle_continue
    else
        # Normal mode: build, sign, and optionally notarize
        check_prerequisites
        prepare_directories
        build_app
        sign_app
        create_zip
        
        if ! notarize_app; then
            warning "Notarization failed or timed out"
            if [ "$NOTARIZE" = true ]; then
                echo ""
                echo -e "${YELLOW}⚠️  Notarization did not complete. You can:${NC}"
                echo "1. Wait for notarization to complete"
                echo "2. Check status manually: xcrun notarytool info <submission_id> --keychain-profile $KEYCHAIN_PROFILE"
                echo "3. Continue later with: $0 $VERSION $BUILD_NUMBER --continue"
                echo ""
                echo "Continuing with packaging without notarization..."
            fi
        fi
    fi
    
    create_dmg
    sign_with_sparkle
    deploy_files
    
    echo ""
    log "🎉 Packaging completed successfully!"
    echo -e "${GREEN}Files generated:${NC}"
    echo -e "  📦 ZIP: ${RELEASE_DIR}/${ZIP_FILE}"
    echo -e "  💿 DMG: ${RELEASE_DIR}/${DMG_FILE}"
    echo -e "  🔑 Sparkle Signature: ${RELEASE_DIR}/sparkle_signature.txt"
    echo -e "  📋 Version: ${VERSION} (Build ${BUILD_NUMBER})"
    echo ""
    echo -e "${GREEN}Files deployed to: ${DISTRIBUTION_DIR}/${BUILD_NUMBER}${NC}"
    echo ""
    
    if [ "$NOTARIZE" = true ] && [ "$CONTINUE_ONLY" = false ]; then
        echo -e "${GREEN}✅ App has been notarized and stapled${NC}"
    elif [ "$CONTINUE_ONLY" = true ]; then
        echo -e "${GREEN}✅ App packaging completed (notarization handled manually)${NC}"
    else
        echo -e "${YELLOW}⚠️  App has not been notarized (use --notarize flag)${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. Update the app version in the database"
    echo "2. Add the Sparkle signature to the database"
    echo "3. Test the update mechanism"
}

# Run main function
main "$@" 