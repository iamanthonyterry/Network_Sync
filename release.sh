#!/bin/bash
set -euo pipefail

# Network Sync release script
# Usage: ./release.sh 1.2
# Bumps MARKETING_VERSION, archives, exports, notarizes, staples, zips,
# and generates the Sparkle appcast — ready to upload to a GitHub Release.

if [ $# -ne 1 ]; then
  echo "Usage: ./release.sh <marketing-version, e.g. 1.2>"
  exit 1
fi

VERSION="$1"
PROJECT="Network Sync.xcodeproj"
SCHEME="Network Sync"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/NetworkSync.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_PATH="$EXPORT_PATH/Network Sync.app"
ZIP_PATH="$BUILD_DIR/NetworkSync-$VERSION.zip"
KEYCHAIN_PROFILE="AC_PASSWORD"

echo "==> Cleaning previous build output"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
