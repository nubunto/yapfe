#!/usr/bin/env bash
set -eu

# This script sets up your local raylib compilation to be used with Odin
# It compiles raylib from your vendor/raylib directory and installs it
# to the Odin vendor directory so it can be used by your project.

echo "Setting up local raylib..."

# Get Odin root directory
ROOT=$(odin root)
ODIN_RAYLIB_DIR="$ROOT/vendor/raylib/macos-arm64"

# Determine architecture
case $(uname -m) in
"arm64") ARCH_DIR="macos-arm64" ;;
*)       ARCH_DIR="macos" ;;
esac

ODIN_RAYLIB_DIR="$ROOT/vendor/raylib/$ARCH_DIR"

# Backup original raylib if it exists and hasn't been backed up yet
if [ -f "$ODIN_RAYLIB_DIR/libraylib.dylib" ] && [ ! -f "$ODIN_RAYLIB_DIR/libraylib.dylib.original" ]; then
    echo "Backing up original Odin raylib..."
    cp "$ODIN_RAYLIB_DIR/libraylib.dylib" "$ODIN_RAYLIB_DIR/libraylib.dylib.original"
fi

# Compile raylib as shared library
echo "Compiling raylib from vendor/raylib..."
cd vendor/raylib/src
make clean
make RAYLIB_LIBTYPE=SHARED

# Copy to Odin vendor directory
echo "Installing compiled raylib to Odin vendor directory..."
cp libraylib.dylib "$ODIN_RAYLIB_DIR/libraylib.dylib"
cp libraylib.*.dylib "$ODIN_RAYLIB_DIR/" 2>/dev/null || true

echo "Local raylib setup complete!"
echo "Your project will now use the raylib compiled from vendor/raylib"
echo ""
echo "To restore original raylib:"
echo "  cp $ODIN_RAYLIB_DIR/libraylib.dylib.original $ODIN_RAYLIB_DIR/libraylib.dylib"
