#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
swift ios/scripts/icon.swift
cd ios
test -s NativeRuntime/node
test -s NativeRuntime/server.mjs
test -s NativeRuntime/entitlements.plist
chmod +x NativeRuntime/node
ldid -SNativeRuntime/entitlements.plist NativeRuntime/node
xcodegen generate
xcodebuild -project OpenCode.xcodeproj -scheme OpenCode -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
mkdir -p build/Payload
ditto build/Build/Products/Release-iphoneos/OpenCode.app build/Payload/OpenCode.app
ldid -STrollStore.entitlements build/Payload/OpenCode.app/OpenCode
ldid -e build/Payload/OpenCode.app/NativeRuntime/node > build/runtime-entitlements.xml
cd build
zip -qry OpenCode-TrollStore.ipa Payload
shasum -a 256 OpenCode-TrollStore.ipa > SHA256SUMS
