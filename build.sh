#!/bin/sh
set -e

PREFIX="${PREFIX:-/usr/local}"
INSTALL_DIR="${INSTALL_DIR:-$PREFIX/bin}"
BINARY_NAME="${BINARY_NAME:-tmd}"
INSTALL_PATH="$INSTALL_DIR/$BINARY_NAME"
SIGN="${SIGN:-1}"

if [ "$(uname)" = "Darwin" ]; then
    echo "Building universal binary for macOS (arm64 + x86_64)..."
    swift build -c debug -Xswiftc -Osize --arch arm64 --arch x86_64
    BIN_DIR="$(swift build -c debug --arch arm64 --arch x86_64 --show-bin-path)"
    BINARY_PATH="$BIN_DIR/tmd"
else
    echo "Building debug binary..."
    swift build -c debug -Xswiftc -Osize
    BIN_DIR="$(swift build -c debug --show-bin-path)"
    BINARY_PATH="$BIN_DIR/tmd"
fi

if [ -f "$BINARY_PATH" ]; then
    echo "Installing tmd from $BINARY_PATH to $INSTALL_PATH..."
    mkdir -p "$INSTALL_DIR"
    cp "$BINARY_PATH" "$INSTALL_PATH"
    if command -v strip >/dev/null 2>&1; then
        echo "Stripping debug symbols..."
        strip "$INSTALL_PATH" 2>/dev/null || true
    fi
else
    echo "Error: Binary not found at $BINARY_PATH"
    exit 1
fi

if [ "$(uname)" = "Darwin" ] && [ "$SIGN" != "0" ]; then
    echo "Performing ad-hoc code signing..."
    codesign -f -s - "$INSTALL_PATH"
fi

echo "Build and installation complete: $INSTALL_PATH"
