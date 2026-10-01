#!/usr/bin/env bash
# ==============================================================================
# package-vscode-extension.sh
#
# Packages the TMD VS Code extension into a .vsix archive and optionally publishes
# it to Visual Studio Marketplace and/or Open VSX Registry.
#
# Usage:
#   ./scripts/package-vscode-extension.sh [OPTIONS]
#
# Options:
#   -o, --out DIR       Output directory for the .vsix package (Default: ./dist)
#   --prebuild          Run TypeScript compile scripts before packaging (Default: enabled)
#   --no-prebuild       Skip TypeScript compilation step
#   --publish           Package and publish directly using vsce publish
#   --open-vsx          Publish to Open VSX registry (requires OVSX_PAT or token arg)
#   -h, --help          Show this help message
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
EXTENSION_SRC="${ROOT_DIR}/editor/vscode"
OUT_DIR="${ROOT_DIR}/dist"
DO_PREBUILD=1
DO_PUBLISH=0
DO_OPEN_VSX=0

show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Packages the TMD VS Code extension into a redistributable .vsix package.

Options:
  -o, --out DIR      Output directory for generated .vsix (Default: ./dist)
  --prebuild         Run 'npm run build:humming' before packaging (Default)
  --no-prebuild      Skip TypeScript build step
  --publish          Publish to Visual Studio Marketplace via 'vsce publish'
  --open-vsx         Publish to Open VSX Registry via 'npx ovsx publish'
  -h, --help         Show this help message

Environment Variables (Optional for publishing):
  VSCE_PAT           Personal Access Token for Visual Studio Marketplace
  OVSX_PAT           Personal Access Token for Open VSX Registry

Examples:
  ./scripts/package-vscode-extension.sh                  # Build .vsix to dist/
  ./scripts/package-vscode-extension.sh -o ./build       # Build .vsix to ./build
  ./scripts/package-vscode-extension.sh --publish        # Build and publish to VS Marketplace
EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--out)
            OUT_DIR="$2"
            shift 2
            ;;
        --prebuild)
            DO_PREBUILD=1
            shift
            ;;
        --no-prebuild)
            DO_PREBUILD=0
            shift
            ;;
        --publish)
            DO_PUBLISH=1
            shift
            ;;
        --open-vsx)
            DO_OPEN_VSX=1
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

if [ ! -f "${EXTENSION_SRC}/package.json" ]; then
    echo "Error: Cannot find extension source at '${EXTENSION_SRC}'."
    exit 1
fi

EXT_NAME=$(grep -m 1 '"name"' "${EXTENSION_SRC}/package.json" | tr -s ' ' | cut -d '"' -f 4)
EXT_PUBLISHER=$(grep -m 1 '"publisher"' "${EXTENSION_SRC}/package.json" | tr -s ' ' | cut -d '"' -f 4)
EXT_VERSION=$(grep -m 1 '"version"' "${EXTENSION_SRC}/package.json" | tr -s ' ' | cut -d '"' -f 4)

echo "=== Packaging TMD VS Code Extension ==="
echo "Extension: ${EXT_PUBLISHER}.${EXT_NAME}"
echo "Version:   ${EXT_VERSION}"
echo "Source:    ${EXTENSION_SRC}"
echo "Output:    ${OUT_DIR}"
echo ""

# Find vsce or npx
if command -v vsce >/dev/null 2>&1; then
    VSCE_CMD="vsce"
elif command -v npx >/dev/null 2>&1; then
    VSCE_CMD="npx --yes @vscode/vsce"
else
    echo "Error: Neither 'vsce' nor 'npx' is installed. Please install Node.js."
    exit 1
fi

# Step 1: Pre-build TypeScript files if requested
if [ ${DO_PREBUILD} -eq 1 ]; then
    echo "[1/3] Building TypeScript sources..."
    if [ -f "${EXTENSION_SRC}/node_modules/typescript/bin/tsc" ]; then
        (cd "${EXTENSION_SRC}" && npm run build:humming)
    elif command -v tsc >/dev/null 2>&1; then
        (cd "${EXTENSION_SRC}" && tsc -p tsconfig.json && tsc -p tsconfig.humming-panel.json)
    elif command -v npx >/dev/null 2>&1; then
        (cd "${EXTENSION_SRC}" && npx --yes --package typescript@5.5.4 tsc -p tsconfig.json && npx --yes --package typescript@5.5.4 tsc -p tsconfig.humming-panel.json)
    else
        echo "Warning: TypeScript compiler (tsc) not found. Skipping build step."
    fi
else
    echo "[1/3] Skipping pre-build step (--no-prebuild)."
fi

# Step 2: Package .vsix
echo "[2/3] Packaging .vsix archive..."
mkdir -p "${OUT_DIR}"
VSIX_FILENAME="${EXT_NAME}-${EXT_VERSION}.vsix"
VSIX_FILEPATH="${OUT_DIR}/${VSIX_FILENAME}"

(cd "${EXTENSION_SRC}" && ${VSCE_CMD} package --out "${VSIX_FILEPATH}")

echo ""
echo "Successfully created package:"
echo "  ${VSIX_FILEPATH}"
echo "  Size: $(du -h "${VSIX_FILEPATH}" | cut -f1)"

# Step 3: Optional Publish
if [ ${DO_PUBLISH} -eq 1 ]; then
    echo ""
    echo "[3/3] Publishing to Visual Studio Marketplace..."
    PUBLISH_ARGS=()
    if [ -n "${VSCE_PAT}" ]; then
        PUBLISH_ARGS+=(--pat "${VSCE_PAT}")
    fi
    (cd "${EXTENSION_SRC}" && ${VSCE_CMD} publish "${PUBLISH_ARGS[@]}")
    echo "Published to Visual Studio Marketplace!"
elif [ ${DO_OPEN_VSX} -eq 1 ]; then
    echo ""
    echo "[3/3] Publishing to Open VSX Registry..."
    OVSX_ARGS=()
    if [ -n "${OVSX_PAT}" ]; then
        OVSX_ARGS+=(-p "${OVSX_PAT}")
    fi
    npx --yes ovsx publish "${VSIX_FILEPATH}" "${OVSX_ARGS[@]}"
    echo "Published to Open VSX Registry!"
else
    echo ""
    echo "[3/3] Done. To install locally:"
    echo "  code --install-extension \"${VSIX_FILEPATH}\""
    echo ""
    echo "To publish to Visual Studio Marketplace:"
    echo "  ./scripts/package-vscode-extension.sh --publish"
    echo "  (or: npx @vscode/vsce publish --packagePath \"${VSIX_FILEPATH}\")"
fi
