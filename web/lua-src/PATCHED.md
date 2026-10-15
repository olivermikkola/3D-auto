# lua-src 547.0.0, patched for the browser

This is a copy of [lua-src](https://github.com/khvzak/lua-src-rs) (MIT), keeping only the Lua 5.4
sources. It adds one build target, `wasm32-unknown-unknown`, which is miniquad's web target. For
that target, Lua is compiled with wasi-sdk's clang against wasi-libc (`WASI_SDK_PATH`), and Lua's
errors (setjmp/longjmp) become wasm exceptions in the legacy encoding, which Safari has supported
since iOS 15.2. `wasm_stubs.c` stands in for the two libc functions WASI doesn't have
(`tmpfile`, `system`). The libc's system calls are answered inside the module by `src/web.rs`.

Only `web/Cargo.toml` uses this copy. The native game builds with the crates.io release as before.
