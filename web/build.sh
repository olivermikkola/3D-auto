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
cp index.html gl.js dist/
cp target/wasm32-unknown-unknown/release/auto.wasm dist/
ls -l dist
