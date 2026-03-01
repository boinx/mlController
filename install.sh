#!/bin/bash
# mlController — Full Install Script
# Builds, installs to /Applications, and sets up launch-at-login

set -euo pipefail

APP_NAME="mlController"
BUNDLE_ID="com.boinx.mlcontroller"
INSTALL_DIR="/Applications"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
PLIST_NAME="$BUNDLE_ID.plist"

echo "╔══════════════════════════════════════╗"
echo "║   mlController Installer             ║"
echo "╚══════════════════════════════════════╝"
echo ""

# Check Swift is available
if ! command -v swift &>/dev/null; then
  echo "Error: Swift is not installed. Install Xcode or the Swift toolchain."
  exit 1
fi

echo "==> Building $APP_NAME..."
make bundle

echo ""
echo "==> Installing to $INSTALL_DIR/$APP_NAME.app..."
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -r "$APP_NAME.app" "$INSTALL_DIR/$APP_NAME.app"

echo ""
echo "==> Setting up LaunchAgent (launch at login)..."
mkdir -p "$LAUNCH_AGENTS"

# Unload existing agent if present
launchctl unload -w "$LAUNCH_AGENTS/$PLIST_NAME" 2>/dev/null || true

cp "LaunchAgents/$PLIST_NAME" "$LAUNCH_AGENTS/$PLIST_NAME"
launchctl load -w "$LAUNCH_AGENTS/$PLIST_NAME"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║   Installation Complete!             ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "  App: $INSTALL_DIR/$APP_NAME.app"
echo "  Launch at login: enabled"
echo "  Web dashboard: http://localhost:8990"
echo ""
echo "==> Launching now..."
open "$INSTALL_DIR/$APP_NAME.app"
