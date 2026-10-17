#!/bin/sh
# Build the browser version into web/dist: index.html, gl.js and auto.wasm.
# Needs the wasm32-unknown-unknown Rust target and a wasi-sdk (WASI_SDK_PATH);
# see web/README.md.
set -e
cd "$(dirname "$0")"
: "${WASI_SDK_PATH:?set WASI_SDK_PATH to a wasi-sdk (https://github.com/WebAssembly/wasi-sdk/releases)}"
export WASI_SDK_PATH
cargo build --release --target wasm32-unknown-unknown
mkdir -p dist
cp index.html gl.js manifest.webmanifest dist/
cp -r icons dist/
cp target/wasm32-unknown-unknown/release/auto.wasm dist/
# The offline cache's version is the module's hash, so every build replaces it.
version=$( (sha256sum dist/auto.wasm 2>/dev/null || shasum -a 256 dist/auto.wasm) | cut -c1-12)
sed "s/__VERSION__/$version/" sw.js > dist/sw.js
ls -l dist
