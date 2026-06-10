#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 -u <username>"
    exit 1
}

# Parse arguments
USERNAME=""
while getopts "u:" opt; do
    case $opt in
        u) USERNAME="$OPTARG" ;;
        *) usage ;;
    esac
done

if [[ -z "$USERNAME" ]]; then
    echo "Error: username is required"
    usage
fi

NERSC_PORTAL="https://portal.nersc.gov/cfs/mfa"
BIN_DIR="$HOME/.ssh/sshproxy"

mkdir -p "$BIN_DIR"

# Detect OS and architecture
OS=$(uname -s)
ARCH=$(uname -m)

# Determine the OS-specific filename pattern and installed binary path
case "$OS" in
    Darwin)
        OS_PATTERN="macos-universal"
        FILE_EXT="pkg"
        SSHPROXY_BIN="/usr/local/bin/sshproxy"
        ;;
    Linux)
        case "$ARCH" in
            x86_64)  OS_PATTERN="linux-x86_64" ;;
            aarch64) OS_PATTERN="linux-aarch64" ;;
            *) echo "Error: unsupported architecture: $ARCH"; exit 1 ;;
        esac
        FILE_EXT="tar.gz"
        SSHPROXY_BIN="$BIN_DIR/sshproxy"
        ;;
    MINGW*|MSYS*|CYGWIN*)
        # Git Bash / MSYS2 / Cygwin. NERSC ships a single MSIX bundle
        # for Windows; installing it exposes an app-execution alias
        # 'sshproxy' under %LOCALAPPDATA%\Microsoft\WindowsApps, which
        # is on PATH — so the binary is resolved by name, not by path.
        OS_PATTERN="windows-universal"
        FILE_EXT="msixbundle"
        SSHPROXY_BIN="sshproxy"
        ;;
    *)
        echo "Error: unsupported OS: $OS"
        exit 1
        ;;
esac

# Is sshproxy already installed? On Windows it lives on PATH; elsewhere
# at a fixed location.
_sshproxy_installed() {
    case "$OS" in
        MINGW*|MSYS*|CYGWIN*) command -v sshproxy &>/dev/null ;;
        *)                    [[ -x "$SSHPROXY_BIN" ]] ;;
    esac
}

# Download and install sshproxy only if not already present
if ! _sshproxy_installed; then
    echo "==> Detecting latest sshproxy version for $OS_PATTERN from $NERSC_PORTAL"
    VERSION=$(curl -s "$NERSC_PORTAL/" \
        | grep -oE "sshproxy-[0-9]+\.[0-9]+\.[0-9]+-${OS_PATTERN}\.${FILE_EXT}" \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
        | sort -Vu \
        | tail -1)

    if [[ -z "$VERSION" ]]; then
        echo "Error: could not determine latest sshproxy version for $OS_PATTERN"
        exit 1
    fi
    echo "    Latest version: $VERSION"

    FILENAME="sshproxy-${VERSION}-${OS_PATTERN}.${FILE_EXT}"
    DOWNLOAD_PATH="$BIN_DIR/$FILENAME"

    echo "==> Downloading $FILENAME"
    curl -L -o "$DOWNLOAD_PATH" "$NERSC_PORTAL/$FILENAME"

    case "$OS" in
        Darwin)
            echo "==> Installing macOS package (requires sudo)"
            sudo installer -pkg "$DOWNLOAD_PATH" -target /
            rm "$DOWNLOAD_PATH"
            ;;
        Linux)
            echo "==> Extracting to $BIN_DIR"
            tar -xzf "$DOWNLOAD_PATH" -C "$BIN_DIR"
            rm "$DOWNLOAD_PATH"
            # The tarball may nest the binary inside a subdirectory
            if [[ ! -f "$BIN_DIR/sshproxy" ]]; then
                find "$BIN_DIR" -name "sshproxy" -type f ! -path "$BIN_DIR/sshproxy" \
                    -exec mv {} "$BIN_DIR/sshproxy" \;
            fi
            chmod +x "$SSHPROXY_BIN"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            echo "==> Installing MSIX package (per-user, no admin required)"
            # Native PowerShell needs a Windows-style path, and MSYS
            # does not auto-convert paths embedded in -Command strings.
            WIN_PATH="$(cygpath -w "$DOWNLOAD_PATH")"
            powershell.exe -NoProfile -Command "Add-AppxPackage -Path '$WIN_PATH'"
            rm "$DOWNLOAD_PATH"
            if ! command -v sshproxy &>/dev/null; then
                echo "Error: sshproxy installed but not found on PATH."
                echo "       Make sure %LOCALAPPDATA%\\Microsoft\\WindowsApps is in your"
                echo "       Windows PATH, then open a new terminal and re-run."
                exit 1
            fi
            ;;
    esac
    echo "==> sshproxy installed at $SSHPROXY_BIN"
fi

"$SSHPROXY_BIN" -u "$USERNAME"