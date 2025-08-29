#!/bin/bash

echo "Installing Glotera app to Applications folder..."

# Find the latest built app
BUILD_PATH="/Users/bryanzh/Library/Developer/Xcode/DerivedData/desktop-cxmnybbtsqklfrbblgrogmxiiwgu/Build/Products/Debug/Glotera.app"

if [ ! -d "$BUILD_PATH" ]; then
    echo "Error: App not found at $BUILD_PATH"
    echo "Please build the app first using Xcode or xcodebuild command"
    exit 1
fi

# Remove existing app if it exists
if [ -d "/Applications/Glotera.app" ]; then
    echo "Removing existing Glotera app..."
    rm -rf "/Applications/Glotera.app"
fi

# Copy the app to Applications folder
echo "Copying app to Applications folder..."
cp -R "$BUILD_PATH" "/Applications/"

# Make sure the app is executable
chmod +x "/Applications/Glotera.app/Contents/MacOS/Glotera"

echo "Installation completed!"
echo ""
echo "IMPORTANT:"
echo "1. Grant Accessibility permissions: System Settings > Privacy & Security > Accessibility"
echo "2. Add Glotera to the list and enable it"
echo "3. Launch the app from Applications folder"
echo ""
echo "The app requires accessibility permissions to monitor keyboard events and extract text from other applications."