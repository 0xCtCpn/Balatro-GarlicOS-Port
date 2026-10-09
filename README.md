# Balatro - GarlicOS (RG35XX) Port

Balatro on the Anbernic RG35XX running GarlicOS, using the open-source `balatro-miyoo-mini-port` runtime.

You need: RG35XX with GarlicOS, the release zip, and your own Balatro `Balatro.exe` or `Balatro.love` from Steam. Balatro is made by LocalThunk and must be purchased separately — game files are never included in this repo or the release zip.

## Overview

This is a **native port** - no emulation, no PC compatibility layers. The game's Lua logic runs on LuaJIT and every frame is drawn by a CPU renderer straight to the framebuffer. To get there, the port works around three things the RG35XX can't do:

* **Software rendering** - the device's GPU (PowerVR SGX544) has no working GL driver on GarlicOS, so the runtime draws every frame in software directly to `/dev/fb0` (scalar + NEON, 640x480 native). Desktop CRT/bloom/shadow paths are disabled upstream. Expect 25-38fps after the Garlic patches - normal for this chip.
* **musl libc** - the device ships a 2012-era system libc too old for anything modern compilers emit, so the port carries its own (`libc.so` + `ld-musl-armhf.so.1`, staged to `/tmp` at launch).
* **Raw controller input** - no SDL gamepad stack on the device; buttons are read straight from Linux evdev, auto-scanned across `/dev/input/event*` (event0 is the power button, event1 is the RG35XX gamepad). L2/R2 shelf buttons arrive as `ABS_Z`/`ABS_RZ` axes, d-pad axes are folded into the hat.

What's in the zip is everything except the game itself: runtime, audio helper, dependencies, and launcher all cross-compiled for `armhf`. The actual game content (`Balatro.exe` / `Balatro.love`, DLLs, soundtrack, saves) is commercial data that runs on any architecture - it stays in your `Balatro/` folder, supplied from your own copy of the game.

What was compiled: [Producdevity/balatro-miyoo-mini-port](https://github.com/Producdevity/balatro-miyoo-mini-port) (GPLv3-only, pinned v0.1.3 `908c3e8`, vendored under `upstream/` with Garlic edits applied in-tree) - Rust CPU renderer + LuaJIT runtime - plus `native/garlic-audio.c` (ALSA helper) and alsa-lib as support libraries - all in Docker from source, with device-specific patches applied first (see `Dockerfile`). The original Balatro game code and art were never released and are not part of this.

## Install

1. Download the latest clean zip from Releases and extract it into SD `ROMS/PORTS/`
2. Copy your `Balatro.exe` (Steam Manage > Browse local files) or `Balatro.love` (macOS: inside `Balatro.app` > Contents > Resources) into `ROMS/PORTS/Balatro/`
3. Leave 250MB free. Safely eject, boot, go to PORTS -> Balatro. First launch prepares audio and looks frozen - let it finish, do not power off.
4. Saves live in `ROMS/PORTS/Balatro/`. Back up before updating.

## SD folder structure

```
ROMS/PORTS/
  Balatro.sh
  Balatro/
    balatro-runtime (static musl armv7)
    balatro-audio (ALSA helper)
    libasound.so* libc.so ld-musl-armhf.so.1
    share/alsa/
    Balatro.exe       # YOUR game copy goes here (never in zip/repo)
    audio-cache/      # generated on first launch
```

## Build from source

Only needed if you change the runtime or want fresh binaries

Prerequisites:

* Windows PC with Docker Desktop installed
* WSL2 enabled - this is Docker Desktop's backend on Windows. Needs virtualization turned on in BIOS, plus a reboot on first setup (Docker Desktop installs the WSL2 kernel for you)
* ~10GB free disk

Steps:

1. Open this folder (`Port_Balatro/`) and double-click `build.bat`
2. Wait for it to finish - success ends with `=== Built ===` plus a listing of `out/`
3. Fresh binaries land in `out/`: `balatro-runtime`, `balatro-audio`, ALSA libs (`libasound.so*`), musl `libc.so` / `ld-musl-armhf.so.1`, `share/alsa/`
4. Run `package-release.bat` to stage a clean zip (no game files): `Balatro_UPD/ROMS/` -> `Balatro_Garlic_v11-clean.zip`

What the build does (`Dockerfile`):

* Starts from `debian:bookworm`, installs compilers and build tools
* Fetches a prebuilt musl cross toolchain (`armv7l-linux-musleabihf`) - musl is required because the device libc (EGLIBC 2.15) is too old for glibc builds
* Cross-compiles alsa-lib for ARM (Garlic audio path, same prefix layout as the Half-Life port)
* Installs Rust 1.97.1 + Zig 0.16.0 + cargo-zigbuild 0.23.4 (matches upstream). If ziglang.org is down, falls back to the GitHub Zig release mirror.
* Cross-builds static LuaJIT from the locked cargo registry (`gcc -m32` host + `CROSS=armv7l-linux-musleabihf-`, per LuaJIT "pointer size mismatch" guidance)
* Retargets SLEEF from Cortex-A7+VFPv4 to Cortex-A9+NEON (base RG35XX is A9: VFPv4 traps as SIGILL otherwise), then `cargo zigbuild` the runtime with `-C target-cpu=cortex-a9 -C target-feature=+neon`
* Builds `garlic-audio` helper (musl + ALSA, INTERP `/tmp/ld-musl-armhf.so.1`)
* Prints checks at the end: helper INTERP/needed libs, and no `GLIBC_*` version deps in the static runtime

To install your own build: copy `out/balatro-runtime` + `out/balatro-audio` + `out/libasound.so*` + `out/libc.so` + `out/ld-musl-armhf.so.1` + `out/share` to SD `ROMS/PORTS/Balatro/`, then copy `Balatro.sh` to SD `ROMS/PORTS/` (next to the other `.sh` launchers), then add your `Balatro.exe`.

If the build fails: make sure Docker Desktop is running first, then re-run `build.bat`. A stale half-finished image can be cleared with `docker rmi balatro-garlic`.

## Garlic changes from upstream

Garlic modification 2026-10 (GPLv3, see `patches/`):

* `patches/garlic-platform.patch`: `BALATRO_PLATFORM=garlic` reuses the Onion PCM pipe but skips `libpadsp.so`/`LD_PRELOAD`.
* `native/garlic-audio.c`: stdin S16LE 44.1kHz stereo to ALSA `default` (vs Onion `/dev/dsp` server).
* `Balatro.sh`: `ROMS/PORTS/` layout, musl loader staging to `/tmp`, ALSA config, `debug.log` probe, `BALATRO_ROTATE_180=0`, `BALATRO_FB_PAGES=1` single-buffer default.
* `upstream/` snapshot: pinned v0.1.3 with Garlic edits applied in-tree; `patches/garlic-platform.patch` is the reference for the audio-platform part.

Version history (Garlic releases):

* v1: initial (Miyoo A7 flags - SIGILL on A9, do not use)
* v2-a9: Cortex-A9 build, input auto-scan. Booted, audio prep OK, then ENXIO crash
* v3-garlic: `garlic` platform gates (runner/event). Game runs ~8fps, no audio
* v4-audio: helper INTERP `/tmp/ld-musl-armhf.so.1`. Audio starts
* v5-diag: audio write counters, Menu key 317, cpu/ALSA probe. Found mixer got 0 frames
* v6-patches: all `miyoo` gates extended to `garlic` (Lua patches, async raster, bg cache). Sound + 25-38fps, tearing visible
* v7-vsync: vsync wait before pan - owlfb lacks the ioctl, reverted in v8
* v8-singlebuf: single-buffer default + `BALATRO_FB_PAGES` knob (1/2, no rebuild)
* v9-fastblit: XRGB-aware blit fast path (`update=37ms` -> ~4ms)
* v10-axes: L2/R2 shelf buttons mapped from ABS_Z/ABS_RZ, d-pad axes folded into hat
* v11-clean: game-free release zip (no `Balatro.exe`), GitHub-ready repo with `.gitignore`

## Debugging

If crashing open `ROMS/PORTS/Balatro/debug.log` + `runtime.log` on PC after power-off.
Key lines: `[video] update=` (blit cost), `[FRAME]` (lua/raster/FPS), `[input] code=` (first-press map), `[audio] exit frames=` (samples written).

## Credits

Thanks to:

* Producdevity — [balatro-miyoo-mini-port](https://github.com/Producdevity/balatro-miyoo-mini-port) runtime, renderer, audio and input work (GPLv3)
* [4RH1T3CT0R7/balatro-port-tui](https://github.com/4RH1T3CT0R7/balatro-port-tui) (Apache-2.0) and [PortMaster](https://github.com/PortsMaster/PortMaster-New) (MIT) upstreams, SLEEF (Boost), Nunito font (OFL), LuaJIT, musl — see `upstream/NOTICE` + `upstream/licenses/`
* LocalThunk — Balatro itself (commercial, must be purchased separately; game files, artwork and audio are not covered by the project license)
* [Black-Seraph](https://www.patreon.com/blackseraph/posts/garlicos-for-76561333) for GarlicOS

License: GPLv3-only, see `LICENSE` (copy of `upstream/LICENSE`). Corresponding source for release binaries is this repo + `Dockerfile`/`build.bat` build instructions.
