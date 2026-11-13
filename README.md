# OpenCode mobile for iOS

Experimental native iOS port of the Android OpenCode mobile app. The default interface follows **cl0udly**, and the app is designed to run **OpenCode 1.19.4 on the iPhone**, using a native Node.js runtime instead of Ubuntu/proot.

**Status: development build, not a verified drop-in replacement for the Android app.** The bundled server passes host integration tests. Native builds and real-device acceptance must pass before claiming a working TrollStore release. See [iOS port status](ios/README.md) for the feature matrix and remaining work.

## Build

The [iOS app workflow](../../actions/workflows/ios-app.yml) builds and tests the SwiftUI app, builds the pinned OpenCode server, then builds the native iPhoneOS runtime and packages `OpenCode-TrollStore.ipa`. The complete IPA is uploaded as the `OpenCode-TrollStore` Actions artifact only when all required jobs succeed. The first native runtime build can take over an hour; subsequent builds cache the runtime.

Requirements: iOS 17+, arm64 iPhone/iPad, and a compatible TrollStore installation. This is not an App Store or ordinary sideloading build. TrollStore Lite compatibility is **unverified**. Native shell/git commands additionally require an accessible bootstrap with those executables; the app does not install Ubuntu or a jailbreak.

## Source

- [`ios/OpenCode`](ios/OpenCode): SwiftUI interface, REST/SSE client, Keychain, native process lifecycle, files, dictation.
- [`ios/runtime`](ios/runtime): pinned OpenCode Node bundle and SQLite runtime compatibility patch.
- [`ios/scripts`](ios/scripts): integration tests, icon conversion and IPA packaging.
- [`app`](app): original Android implementation, retained as the porting reference.
- [Original Android README](README.android.md).

## License and attribution

Original mobile client: MIT, copyright retained in [LICENSE](LICENSE). OpenCode: MIT. The native runtime uses Node.js/nodejs-mobile and the iOS work by [Justintunsday/opencode-ios](https://github.com/Justintunsday/opencode-ios). See [iOS notices](ios/NOTICE.md) for pins and third-party notices.

Unofficial client; not affiliated with the OpenCode developers.
