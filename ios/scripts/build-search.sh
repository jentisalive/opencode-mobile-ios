#!/bin/bash
# Run on macOS with the pinned runtime reference repository as the working directory.
set -euo pipefail
export SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)"
export IPHONEOS_DEPLOYMENT_TARGET=16.1
export CARGO_HOME="$RUNNER_TEMP/opencode-cargo"
rustup toolchain install 1.88.0 --profile minimal --target aarch64-apple-ios
cargo +1.88.0 install ripgrep --version 15.1.0 --locked --no-default-features \
  --target aarch64-apple-ios --root "$RUNNER_TEMP/ios-search"
mkdir -p dist/ios-node-runtime/bin
cp "$RUNNER_TEMP/ios-search/bin/rg" dist/ios-node-runtime/bin/rg
ldid -S dist/ios-node-runtime/bin/rg
python3 scripts/check_macho.py dist/ios-node-runtime/bin/rg --max-minos 17.0
python3 - <<'PY'
import os, pathlib, shutil
source = pathlib.Path(os.environ['CARGO_HOME']) / 'registry' / 'src'
target = pathlib.Path('dist/ios-node-runtime/Licenses/ripgrep-dependencies')
for registry in source.iterdir():
    for package in registry.iterdir():
        for file in package.iterdir():
            if file.name.upper().startswith(('LICENSE', 'COPYING', 'NOTICE')) and file.is_file():
                destination = target / package.name / file.name
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(file, destination)
PY
