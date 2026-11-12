# Source and third-party notices

- Original Android OpenCode mobile UI and client: repository `mistqkw/opencode-mobile`, inherited in this repository; MIT, original root LICENSE retained. cl0udly vector artwork is adapted from `app/src/main/res/drawable/ic_fg_look_cloud.xml`.
- OpenCode server: `anomalyco/opencode`, commit `148842ef7cb1bc34192b3fff57d0f9721ab9c801`, version 1.19.4, MIT. The bundle is generated from source, not committed.
- Native iOS runtime build/patches: `Justintunsday/opencode-ios`, commit `deb21deca5c430869ef98ae5e472d004481c680e`, MIT. Its scripts are checked out at build time; they are not represented as original work here.
- Node.js mobile: `nodejs-mobile/nodejs-mobile`, commit `106c51f95d55d1010de56a2ffd09bfb4ba819a47`, Node.js 22.9.0. Node's LICENSE includes third-party notices for V8, OpenSSL, SQLite, ICU and other components.
- `ios/runtime/patches/0007-sqlite-return-arrays.patch` backports the ordered result behavior of Node's `StatementSync.setReturnArrays` to the pinned mobile runtime. Node.js MIT attribution applies to the underlying code.
- Generated server dependencies retain their own licenses. In particular, Photon is Apache-2.0, jsonc-parser is MIT, and tree-sitter runtime/grammars have their respective upstream licenses.

The build gathers upstream license files into `NativeRuntime/Licenses`. Keep them with redistributed binary builds. Runtime JIT and signing work is experimental outside the upstream port's documented test device.
