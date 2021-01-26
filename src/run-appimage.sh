#!/bin/bash
set -eo pipefail
shopt -s extglob

# Utility for using the Electrum AppImage with the Bitcoin Wallet Tracker plugin.
# Extracts the AppImage into a directory, adds the bwt plugin, and runs Electrum.

APPIMAGE_PATH=$(realpath "${1:?"Missing AppImage path, run with: $0 path/to/Electrum-x.y.z.AppImage"}")
BWT_PLUGIN_DIR=$(dirname "$(readlink -e "$0")")
SQUASH_ROOT=$BWT_PLUGIN_DIR/squashfs-root

if [ ! -d "$SQUASH_ROOT" ]; then
  (cd "$BWT_PLUGIN_DIR" && "$APPIMAGE_PATH" --appimage-extract)

  PLUGINS_DIR=$(echo "$SQUASH_ROOT"/usr/lib/python3.*/site-packages/electrum/plugins)
  ln -s ../../../../../../.. "$PLUGINS_DIR/bwt"

  echo Electrum AppImage extracted to $SQUASH_ROOT with the Bitcoin Wallet Tracker plugin.
fi

echo You may also run Electrum directly with:
echo $ $SQUASH_ROOT/AppRun

exec "$SQUASH_ROOT/AppRun" "${@:2}"
