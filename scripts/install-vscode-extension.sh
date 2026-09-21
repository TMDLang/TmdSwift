#!/usr/bin/env bash
# ==============================================================================
# install-vscode-extension.sh
#
# Installs or symlinks the TMD VS Code extension locally without relying on the
# official Microsoft VS Code Extension Marketplace.
#
# Supported Editors:
#   - VS Code (`~/.vscode/extensions`)
#   - VS Code Insiders (`~/.vscode-insiders/extensions`)
#   - Cursor (`~/.cursor/extensions`)
#   - VSCodium (`~/.vscode-oss/extensions`)
#
# Installation Modes:
#   --link, -l      : Create symbolic link (Recommended for developers; instant reload)
#   --copy, -c      : Copy extension files directly (Self-contained offline install)
#   --vsix          : Package into a .vsix file and install via `code --install-extension`
#   --uninstall, -u : Uninstall the extension from all detected editor extension folders
#
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
EXTENSION_SRC="${ROOT_DIR}/editor/vscode"
EXTENSION_NAME="tmd-vscode"

MODE="link"
DRY_RUN=0
TARGET_EDITOR=""

show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Install the local TMD VS Code extension directly without Microsoft Marketplace.

Options:
  -l, --link         Symlink extension folder into editors' extensions directory (Default, best for development).
  -c, --copy         Copy extension folder into editors' extensions directory (Standalone offline install).
  --vsix             Package extension using 'vsce' / 'npx @vscode/vsce' and install via 'code --install-extension'.
  -u, --uninstall    Remove TMD extension from all installed editors.
  -e, --editor NAME  Target specific editor: vscode, insiders, cursor, codium (Default: all detected).
  -n, --dry-run      Show planned actions without making filesystem changes.
  -h, --help         Show this help message.

Examples:
  ./scripts/install-vscode-extension.sh             # Symlinks into all detected editors
  ./scripts/install-vscode-extension.sh --copy      # Copies extension files cleanly
  ./scripts/install-vscode-extension.sh --vsix      # Packages .vsix and runs code --install-extension
  ./scripts/install-vscode-extension.sh --uninstall # Removes extension
EOF
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -l|--link)
            MODE="link"
            shift
            ;;
        -c|--copy)
            MODE="copy"
            shift
            ;;
        --vsix)
            MODE="vsix"
            shift
            ;;
        -u|--uninstall)
            MODE="uninstall"
            shift
            ;;
        -e|--editor)
            TARGET_EDITOR="$2"
            shift 2
            ;;
        -n|--dry-run)
            DRY_RUN=1
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

# Verify source extension folder exists
if [ ! -f "${EXTENSION_SRC}/package.json" ]; then
    echo "Error: Cannot find extension source at '${EXTENSION_SRC}'."
    exit 1
fi

EXT_VERSION=$(grep -m 1 '"version"' "${EXTENSION_SRC}/package.json" | tr -s ' ' | cut -d '"' -f 4)
echo "=== TMD VS Code Extension Local Installer ==="
echo "Extension: ${EXTENSION_NAME} (v${EXT_VERSION:-0.1.0})"
echo "Source:    ${EXTENSION_SRC}"
echo "Mode:      ${MODE}"
echo ""

# Discover target editor extension directories
declare -a DETECTED_NAMES=()
declare -a DETECTED_DIRS=()
declare -a DETECTED_CLIS=()

check_editor() {
    local name="$1"
    local dir="$2"
    local cli="$3"

    if [ -n "${TARGET_EDITOR}" ] && [ "${TARGET_EDITOR}" != "${name}" ]; then
        return
    fi

    # Check if directory exists or if CLI exists
    local has_dir=0
    local has_cli=0
    if [ -d "$(dirname "${dir}")" ] || [ -d "${dir}" ]; then
        has_dir=1
    fi
    if command -v "${cli}" >/dev/null 2>&1; then
        has_cli=1
    fi

    if [ $has_dir -eq 1 ] || [ $has_cli -eq 1 ]; then
        DETECTED_NAMES+=("${name}")
        DETECTED_DIRS+=("${dir}")
        DETECTED_CLIS+=("${cli}")
    fi
}

# Check common editor suites
check_editor "vscode" "${HOME}/.vscode/extensions" "code"
check_editor "insiders" "${HOME}/.vscode-insiders/extensions" "code-insiders"
check_editor "cursor" "${HOME}/.cursor/extensions" "cursor"
check_editor "codium" "${HOME}/.vscode-oss/extensions" "codium"

if [ ${#DETECTED_NAMES[@]} -eq 0 ]; then
    # Fallback to standard VS Code directory if none explicitly detected
    echo "Notice: No existing editor directories found. Defaulting to standard VS Code directory."
    DETECTED_NAMES+=("vscode")
    DETECTED_DIRS+=("${HOME}/.vscode/extensions")
    DETECTED_CLIS+=("code")
fi

# ------------------------------------------------------------------------------
# Action: Uninstall
# ------------------------------------------------------------------------------
if [ "${MODE}" = "uninstall" ]; then
    echo "Uninstalling ${EXTENSION_NAME}..."
    for i in "${!DETECTED_NAMES[@]}"; do
        name="${DETECTED_NAMES[$i]}"
        ext_dir="${DETECTED_DIRS[$i]}/${EXTENSION_NAME}"
        cli="${DETECTED_CLIS[$i]}"

        if [ -e "${ext_dir}" ] || [ -L "${ext_dir}" ]; then
            echo "  [$name] Removing: ${ext_dir}"
            if [ $DRY_RUN -eq 0 ]; then
                rm -rf "${ext_dir}"
            fi
        else
            echo "  [$name] Not installed in ${ext_dir}"
        fi

        # Also attempt CLI uninstall if available
        if command -v "${cli}" >/dev/null 2>&1; then
            if [ $DRY_RUN -eq 0 ]; then
                "${cli}" --uninstall-extension "${EXTENSION_NAME}" 2>/dev/null || true
            fi
        fi
    done
    echo "Uninstall complete."
    exit 0
fi

# ------------------------------------------------------------------------------
# Action: VSIX Packaging & Installation
# ------------------------------------------------------------------------------
if [ "${MODE}" = "vsix" ]; then
    echo "Building .vsix package..."
    VSIX_DIR="${ROOT_DIR}/build"
    mkdir -p "${VSIX_DIR}"
    VSIX_FILE="${VSIX_DIR}/${EXTENSION_NAME}-${EXT_VERSION}.vsix"

    # Find vsce or npx
    if command -v vsce >/dev/null 2>&1; then
        VSCE_CMD="vsce"
    elif command -v npx >/dev/null 2>&1; then
        VSCE_CMD="npx @vscode/vsce"
    else
        echo "Error: Neither 'vsce' nor 'npx' is available. Please install Node.js/npm or use --link / --copy instead."
        exit 1
    fi

    if [ $DRY_RUN -eq 0 ]; then
        (cd "${EXTENSION_SRC}" && ${VSCE_CMD} package --out "${VSIX_FILE}" --allow-missing-repository)
        echo "Packaged: ${VSIX_FILE}"
    else
        echo "  [dry-run] Would package to ${VSIX_FILE}"
    fi

    for i in "${!DETECTED_NAMES[@]}"; do
        name="${DETECTED_NAMES[$i]}"
        cli="${DETECTED_CLIS[$i]}"

        if command -v "${cli}" >/dev/null 2>&1; then
            echo "  [$name] Installing via '${cli} --install-extension ${VSIX_FILE}'..."
            if [ $DRY_RUN -eq 0 ]; then
                "${cli}" --install-extension "${VSIX_FILE}" --force
            fi
        else
            echo "  [$name] CLI '${cli}' not found in PATH; skipping CLI install."
        fi
    done

    echo "VSIX installation complete."
    exit 0
fi

# ------------------------------------------------------------------------------
# Action: Symlink or Copy Directory
# ------------------------------------------------------------------------------
for i in "${!DETECTED_NAMES[@]}"; do
    name="${DETECTED_NAMES[$i]}"
    target_base="${DETECTED_DIRS[$i]}"
    target_ext="${target_base}/${EXTENSION_NAME}"

    echo "[$name] Target directory: ${target_ext}"

    if [ $DRY_RUN -eq 0 ]; then
        mkdir -p "${target_base}"
        if [ -e "${target_ext}" ] || [ -L "${target_ext}" ]; then
            echo "  Removing existing installation..."
            rm -rf "${target_ext}"
        fi
    fi

    if [ "${MODE}" = "link" ]; then
        echo "  Linking: ${target_ext} -> ${EXTENSION_SRC}"
        if [ $DRY_RUN -eq 0 ]; then
            ln -sfn "${EXTENSION_SRC}" "${target_ext}"
        fi
    elif [ "${MODE}" = "copy" ]; then
        echo "  Copying files to: ${target_ext}"
        if [ $DRY_RUN -eq 0 ]; then
            mkdir -p "${target_ext}"
            if command -v rsync >/dev/null 2>&1; then
                rsync -a --delete \
                    --exclude '.git*' \
                    --exclude '.DS_Store' \
                    --exclude '*.vsix' \
                    --exclude 'node_modules' \
                    "${EXTENSION_SRC}/" "${target_ext}/"
            else
                cp -R "${EXTENSION_SRC}/"* "${target_ext}/"
            fi
        fi
    fi
done

echo ""
echo "Installation complete!"
echo "To activate changes:"
echo "  1. In your editor, press 'Cmd+Shift+P' (macOS) or 'Ctrl+Shift+P' (Linux/Windows)."
echo "  2. Run 'Developer: Reload Window'."
echo "  3. Open any .tmd file to enjoy syntax highlighting, previews, and Song Inspector!"
