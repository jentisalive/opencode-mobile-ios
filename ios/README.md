# iOS port status

This branch is an **experimental, incomplete port** targeting iOS 17+ and TrollStore. It does not yet reproduce every Android feature. Do not label a build device-tested until the checklist below has been completed on an actual iPhone.

## Architecture

The SwiftUI app starts its bundled, native arm64 Node executable with `posix_spawn`. The server is OpenCode **1.19.4**, pinned to `148842ef7cb1bc34192b3fff57d0f9721ab9c801`. It runs on `127.0.0.1:4096`, requires a random password stored in Keychain, and stores its configuration/database in the app's Application Support directory. Projects live in Documents/Projects and are visible through Files.

This is not a remote-server substitute. Model inference still requires a provider, just as in the Android client. No Ubuntu, proot, Linux executable, or macOS executable is shipped as an iOS runtime.

The native runtime build reuses the pinned Node.js 22.9 iOS port from Justintunsday and adds ordered SQLite row support. The backport preserves duplicate column names; converting row objects with `Object.values` would corrupt some SQL query results. Startup explicitly checks this capability.

## Feature parity

| Android feature | Current iOS implementation |
| --- | --- |
| cl0udly home, composer and drawer | Native SwiftUI adaptation of the original palette/layout and cloud icon; visual/device review pending |
| Autonomous OpenCode | Native process launcher, pinned engine bundle and build pipeline; **not verified on TrollStore hardware** |
| Chat/history/streaming | REST/SSE, incremental text/tool parts, reconnect, fenced code blocks with copy, and server history reload |
| Models/providers | Model picker, API-key connection and provider OAuth flow; real account flows unverified |
| Permissions/questions | Allow once/always/deny; multiple-choice and free-text replies |
| Projects/files | Project creation, text editor, Files integration, attachments and native share sheet |
| Agent tools/review | Expandable commands/output/thinking, session diff, message revert and unrevert; no individual-file keep/undo UI yet |
| Agent selection/team | Select existing primary agents; configure subagents in JSON; Android's team dashboard is not ported |
| Skills/memory | Skill creation/editing, SKILL.md import, creation with the agent, server list and memory editor; ZIP/skill archive import is not ported |
| Voice | Native speech dictation and read-aloud; continuous voice mode is not ported |
| Usage | Current conversation cost and token totals; Android rolling limits/context ring not ported |
| File search | Bundled iPhoneOS arm64 ripgrep 15.1.0; device execution unverified |
| Shell/git/GitHub CLI | Uses compatible tools already available in the selected bootstrap; no bundled Ubuntu toolchain or GitHub device-login wizard |
| Phone MCP tools | Not ported |
| Scheduled tasks/live notifications | Not ported; iOS background time is bounded |
| Backup/restore/updater | Not ported; retain app data when updating in TrollStore |
| Alternate looks/mascot room/minigame | Not ported |
| QR remote-device connections | Not ported; this branch prioritizes the requested autonomous mode |

## Reliability updates

The native build now pins ICU host libraries to the runner architecture. Previously the Intel job linked an arm64 `libicutools.a` into an x86_64 V8 generator and failed before producing an IPA. A configure-time check rejects mixed architectures or iPhoneOS SDK flags on host generators before compilation.

Chat loads are scoped to the conversation generation and stream revision. Late HTTP snapshots cannot repopulate a closed/reopened conversation or replace newer streamed output. Stopped/replaced event streams cannot reconnect and mark a stopped engine online. Sending another prompt is disabled while the selected conversation is busy. An idle runtime remains Stopped when stopped again.

These changes have dedicated regression tests. Physical-device acceptance below is still required; a successful host build does not establish TrollStore compatibility.

## Build and checks

The `iOS app` workflow runs engine checks on Linux and application tests on an iOS simulator. After the engine checks, it calls `iOS native runtime`; packaging requires all checks to pass. Native runtime output is cached by source/patch/toolchain pins. The IPA job fails if either the native executable or the engine bundle is absent.

The engine integration test uses an isolated temporary project, a random local password and a local mock model endpoint. It verifies actual prompt execution, writing a file after permission, denial without writing, and question replies. It never uses real provider credentials or paid requests. The Swift tests cover request construction, JSON decoding, skill imports, streamed code blocks and SSE framing including UTF-8 and CR/LF boundaries. An iOS UI test creates a project and edits/reopens a file.

On a Mac, install Xcode and XcodeGen, then:

```sh
swift ios/scripts/icon.swift
cd ios
mkdir -p NativeRuntime
xcodegen generate
open OpenCode.xcodeproj
```

Simulator builds intentionally do not run the iPhoneOS Node executable. A full TrollStore build additionally needs the `ios-engine` and `ios-node-runtime` artifacts in `ios/NativeRuntime`. From the repository root, run `bash ios/scripts/package.sh` with `ldid` installed. Standard Apple signing does not grant the runtime's private entitlements.

## Device acceptance checklist

1. Install the complete IPA using TrollStore. Launch and confirm that `/global/health` becomes ready.
2. Verify restart, stop/start, Keychain persistence, background/foreground and force-quit behavior.
3. Connect a provider, send two consecutive prompts, interrupt a response, relaunch and reopen the same history.
4. Create a project, ask the agent to read/write a test file, inspect its diff, revert and unrevert.
5. Check permission denial/approval and multi-question replies.
6. With an accessible bootstrap, exercise shell, git and search; verify their versions and inspect failures.
7. Test dictation, attachments, Files sharing, keyboard layout, rotation and iPad.
8. Inspect device crash logs for V8 executable-memory failures or memory-pressure termination.

TrollStore Lite and rootHide have not been tested by this project. The native runtime's upstream device evidence is from a different jailbreak/device and is not evidence that this IPA works on those installations. Set an accessible bootstrap prefix in Settings → Runtime for shell tools. The app does not gain a Linux environment merely by being installed with TrollStore.
