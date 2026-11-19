#!/usr/bin/env bash

set -euo pipefail

REPO="Innerfrost/Post-Install"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/scripts"

DEST_DIR="${HOME}/scripts"

echo
echo "=================================="
echo "       POST-INSTALL LOADER"
echo "=================================="
echo
echo "Select your Linux distribution:"
echo
echo "  1) Ubuntu"
echo "  2) Arch Linux / CachyOS"
echo "  3) Fedora"
echo "  0) Exit"
echo

read -r -p "Your choice: " choice

case "$choice" in
1)
    filename="ubuntu-post.sh"
    ;;
2)
    filename="arch-post-v2.sh"
    ;;
3)
    filename="fedora-post-v2.sh"
    ;;
0)
    echo "Cancelled."
    exit 0
    ;;
*)
    echo "Invalid selection."
    exit 1
    ;;
esac

if command -v curl >/dev/null 2>&1; then
    downloader="curl"
elif command -v wget >/dev/null 2>&1; then
    downloader="wget"
else
    echo "Error: curl or wget is required."
    exit 1
fi

mkdir -p "$DEST_DIR"

destination="${DEST_DIR}/${filename}"
url="${BASE_URL}/${filename}"

if [[ -e "$destination" ]]; then
    echo "Error: file already exists: $destination"
    echo "Existing file was not modified."
    exit 1
fi

tmp_file="$(mktemp "${DEST_DIR}/.${filename}.XXXXXX")"
trap 'rm -f "$tmp_file"' EXIT

echo
echo "Downloading ${filename}..."

if [[ "$downloader" == "curl" ]]; then
    curl -fL --retry 2 --connect-timeout 10 \
        --silent --show-error \
        "$url" -o "$tmp_file"
else
    wget -q --timeout=20 -O "$tmp_file" "$url"
fi

echo "Checking Bash syntax..."

if ! bash -n "$tmp_file"; then
    echo "Error: downloaded script has invalid Bash syntax."
    exit 1
fi

chmod 755 "$tmp_file"
mv -n "$tmp_file" "$destination"

echo
echo "Download completed successfully!"
echo "Saved to: $destination"
echo
echo "The script was NOT executed."
echo "Review it before running."
