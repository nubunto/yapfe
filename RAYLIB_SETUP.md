# Local Raylib Setup

This project is now configured to use a locally compiled version of raylib from the `vendor/raylib` directory.

## What was done

1. **Compiled raylib as a shared library**: The raylib source in `vendor/raylib` was compiled as a dynamic library (`.dylib`) using the Makefile with `RAYLIB_LIBTYPE=SHARED`.

2. **Installed to Odin vendor directory**: The compiled `libraylib.dylib` was copied to the Odin compiler's vendor directory at `/Users/bruno.panuto/dev/tools/Odin/vendor/raylib/macos-arm64/`.

3. **Backed up original**: The original Odin raylib library was backed up as `libraylib.dylib.original`.

## Files created/modified

- `scripts/setup_local_raylib.sh` - Script to recompile and install your local raylib
- `vendor/raylib/src/libraylib.dylib` - Your compiled raylib dynamic library
- `RAYLIB_SETUP.md` - This documentation file

## Usage

### Building your project
Use the existing build scripts as normal:
```bash
./scripts/build_hot_reload.sh
./scripts/build_debug.sh
./scripts/build_release.sh
```

### Updating raylib
If you make changes to the raylib source in `vendor/raylib`, run:
```bash
./scripts/setup_local_raylib.sh
```

This will recompile raylib and install it to the Odin vendor directory.

### Restoring original raylib
If you want to go back to the original Odin raylib:
```bash
cp /Users/bruno.panuto/dev/tools/Odin/vendor/raylib/macos-arm64/libraylib.dylib.original /Users/bruno.panuto/dev/tools/Odin/vendor/raylib/macos-arm64/libraylib.dylib
```

## Technical details

- **Raylib version**: Your local raylib is version 5.6-dev (from the vendor/raylib directory)
- **Original version**: The original Odin raylib was version 5.5.0
- **Architecture**: Built for macOS ARM64 (Apple Silicon)
- **Library type**: Dynamic library (.dylib) with proper framework dependencies
- **Installation path**: `/Users/bruno.panuto/dev/tools/Odin/vendor/raylib/macos-arm64/libraylib.dylib`

## Verification

You can verify that your local raylib is being used by running:
```bash
DYLD_PRINT_LIBRARIES=1 ./game_hot_reload.bin 2>&1 | grep raylib
```

This should show that the raylib library is being loaded from the Odin vendor directory, but it's actually your compiled version.

## Why do I need to do this?

The Odin bindings actually expect Raylib to be at `$(odin root)/vendor/raylib/macos-arm64`. This setup allows us to compile a local version of Raylib and expose it to the Odin bindings.

Alternatively, we could also set up our own Raylib bindings here. But I... am... lazy.