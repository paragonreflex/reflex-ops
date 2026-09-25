#!/usr/bin/env bash
set -euo pipefail

APP=reflex
ALIAS=opencode
SOURCE_APP=opencode
REPO=paragonreflex/reflex-ops
requested_version=${VERSION:-}
no_modify_path=false
binary_path=""

usage() {
    cat <<EOF
Reflex Ops Installer

Usage: install.sh [options]

Options:
    -h, --help              Display this help message
    -v, --version <tag>     Install a specific release (e.g. v0.9.0)
    -b, --binary <path>     Install from a local binary instead of downloading
        --no-modify-path    Don't modify shell config files (.zshrc, .bashrc, etc.)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -v|--version)
            if [[ -n "${2:-}" ]]; then requested_version="$2"; shift 2
            else echo "Error: --version requires a version argument" >&2; exit 1; fi ;;
        -b|--binary)
            if [[ -n "${2:-}" ]]; then binary_path="$2"; shift 2
            else echo "Error: --binary requires a path argument" >&2; exit 1; fi ;;
        --no-modify-path) no_modify_path=true; shift ;;
        *) echo "Warning: Unknown option '$1'" >&2; shift ;;
    esac
done

INSTALL_DIR=$HOME/.reflex/bin
mkdir -p "$INSTALL_DIR"

if [ -n "$binary_path" ]; then
    if [ ! -f "$binary_path" ]; then echo "Error: Binary not found at $binary_path" >&2; exit 1; fi
    specific_version="local"
else
    raw_os=$(uname -s)
    case "$raw_os" in
      Darwin*) os="darwin" ;;
      Linux*) os="linux" ;;
      MINGW*|MSYS*|CYGWIN*) os="windows" ;;
      *) echo "Unsupported OS: $raw_os" >&2; exit 1 ;;
    esac

    arch=$(uname -m)
    if [[ "$arch" == "aarch64" ]]; then arch="arm64"; fi
    if [[ "$arch" == "x86_64" ]]; then arch="x64"; fi
    if [ "$os" = "darwin" ] && [ "$arch" = "x64" ]; then
      if [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = "1" ]; then arch="arm64"; fi
    fi

    case "$os-$arch" in
      linux-x64|linux-arm64|darwin-x64|darwin-arm64|windows-x64) ;;
      *) echo "Unsupported OS/Arch: $os/$arch" >&2; exit 1 ;;
    esac

    is_musl=false
    if [ "$os" = "linux" ]; then
      if [ -f /etc/alpine-release ]; then is_musl=true; fi
      if command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; then is_musl=true; fi
    fi

    needs_baseline=false
    if [ "$arch" = "x64" ]; then
      if [ "$os" = "linux" ]; then
        if ! grep -qwi avx2 /proc/cpuinfo 2>/dev/null; then needs_baseline=true; fi
      fi
      if [ "$os" = "darwin" ]; then
        if [ "$(sysctl -n hw.optional.avx2_0 2>/dev/null || echo 0)" != "1" ]; then needs_baseline=true; fi
      fi
    fi

    target="$os-$arch"
    if [ "$needs_baseline" = "true" ]; then target="$target-baseline"; fi
    if [ "$is_musl" = "true" ]; then target="$target-musl"; fi

    if [ -z "$requested_version" ]; then
        site_version=$(curl -fsSL https://reflex.riif.com/version.txt | tr -d '[:space:]')
        if [ -n "$site_version" ]; then
            specific_version="$site_version"
        else
            final_url=$(curl -fsSL -o /dev/null -w "%{url_effective}" "https://github.com/$REPO/releases/latest")
            specific_version="${final_url##*/}"
            if [ -z "$specific_version" ]; then echo "Error: could not resolve latest release" >&2; exit 1; fi
        fi
    else
        specific_version="$requested_version"
    fi

    if [ "$specific_version" != "local" ]; then
        specific_version="v${specific_version#v}"
    fi

    if [ "$os" = "windows" ]; then ext="zip"; asset="opencode-$target.zip"
    elif [ "$os" = "linux" ]; then ext="tar.gz"; asset="opencode-$target.tar.gz"
    else ext="zip"; asset="opencode-$target.zip"; fi
    url="https://github.com/$REPO/releases/download/$specific_version/$asset"

    if [ "$(curl -s -o /dev/null -w "%{http_code}" -L "$url")" = "404" ]; then
        echo "Error: $asset not found in release $specific_version" >&2; exit 1
    fi
    filename="$asset"
    _ext="$ext"
fi

echo "Installing $APP ${specific_version:-} (${target:-local})"
tmp_dir="${TMPDIR:-/tmp}/reflex_install_$$"
mkdir -p "$tmp_dir"

if [ -n "$binary_path" ]; then
    cp "$binary_path" "$INSTALL_DIR/$APP"
else
    curl -f -# -L -o "$tmp_dir/$filename" "$url"
    if [[ "$filename" == *.zip ]]; then
        unzip -q -o "$tmp_dir/$filename" -d "$tmp_dir"
    else
        tar -xzf "$tmp_dir/$filename" -C "$tmp_dir"
    fi
    if [ -f "$tmp_dir/$SOURCE_APP" ]; then
        mv "$tmp_dir/$SOURCE_APP" "$INSTALL_DIR/$APP"
    elif [ -f "$tmp_dir/bin/$SOURCE_APP" ]; then
        mv "$tmp_dir/bin/$SOURCE_APP" "$INSTALL_DIR/$APP"
    elif [ -f "$tmp_dir/package/bin/$SOURCE_APP" ]; then
        mv "$tmp_dir/package/bin/$SOURCE_APP" "$INSTALL_DIR/$APP"
    else
        echo "Error: binary not found inside $filename" >&2; exit 1
    fi
    rm -rf "$tmp_dir"
fi
chmod 755 "$INSTALL_DIR/$APP"

rm -f "$INSTALL_DIR/$ALIAS" "$INSTALL_DIR/$ALIAS.exe"
if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* || "$(uname -s)" == CYGWIN* ]]; then
    cp "$INSTALL_DIR/$APP" "$INSTALL_DIR/$ALIAS.exe"
else
    printf '#!/bin/sh\nexec "$(dirname "$0")/%s" "$@"\n' "$APP" > "$INSTALL_DIR/$ALIAS"
    chmod 755 "$INSTALL_DIR/$ALIAS"
fi

current_shell=$(basename "$SHELL")
case $current_shell in
    fish) config_files="$HOME/.config/fish/config.fish"; path_cmd="fish_add_path $INSTALL_DIR" ;;
    zsh) config_files="${ZDOTDIR:-$HOME}/.zshrc"; path_cmd="export PATH=$INSTALL_DIR:\$PATH" ;;
    *) config_files="$HOME/.bashrc $HOME/.bash_profile"; path_cmd="export PATH=$INSTALL_DIR:\$PATH" ;;
esac

if [[ "$no_modify_path" != "true" && ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    for file in $config_files; do
        if [[ -f $file ]]; then
            if ! grep -Fq "$INSTALL_DIR" "$file"; then
                printf '\n# reflex ops\nexport PATH=%s:$PATH\n' "$INSTALL_DIR" >> "$file"
                echo "Added $INSTALL_DIR to PATH in $file (restart your shell)"
            fi
            break
        fi
    done
    if [[ "$current_shell" == "fish" && -f "$HOME/.config/fish/config.fish" ]]; then
        grep -Fq "$INSTALL_DIR" "$HOME/.config/fish/config.fish" || echo "fish_add_path $INSTALL_DIR" >> "$HOME/.config/fish/config.fish"
    fi
fi

echo ""
echo "REFLEX OPS installed. Start:"
echo ""
echo "  cd <project>  # open directory"
echo "  reflex        # run command"
echo ""
