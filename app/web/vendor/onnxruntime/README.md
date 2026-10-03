# ONNX Runtime Web 1.23.0

The browser uses the WebAssembly-only build, served from this app's own origin. There is no CDN dependency. `index.html` selects one inference thread so deployment does not require cross-origin isolation headers.

Source package: https://registry.npmjs.org/onnxruntime-web/-/onnxruntime-web-1.23.0.tgz

Package SHA-256: `7e0074d9319fdef002bcf28ef73eb119dd6302083fa0395ec560cb4e5ca0970b`

Copied unmodified from `package/dist/`:

| File | SHA-256 |
|---|---|
| ort.wasm.min.js | aec37bf5b223afd8ac358e6647369c724cc08727c258760bb88e4f6ce69ab68f |
| ort-wasm-simd-threaded.mjs | c0bc2244e2c95fbf39a5eccb595bca31defb9eefdffa6f9ce0325a1c47524461 |
| ort-wasm-simd-threaded.wasm | 3260fcdb33b4fc4ec33e89caf392e13625823e01049d3bf32c38464f9dbfe14c |

MIT license and third-party notices are adjacent files, copied from the upstream `v1.23.0` tag. See [official deployment guidance](https://onnxruntime.ai/docs/tutorials/web/deploy.html).

The native app has all inference assets installed and works without a network. The browser needs the site to load; local hosting avoids public network requests but full offline browser relaunch is not promised by this alpha.
