#!/usr/bin/env bash
# ------------------------------------------------------------
#  Hotloader installer (Linux)
#  Run from the Hotloader repo folder (next to addon.json).
#  Usage:  ./installer.sh
#          ./installer.sh /path/to/GarrysMod
#          ./installer.sh /path/to/gmod-server   (dedicated server root)
# ------------------------------------------------------------
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$SRC/addon.json" ]]; then
    echo "[ERROR] addon.json not found in $SRC"
    echo "Put installer.sh in the Hotloader folder and run it again."
    exit 1
fi

# ---- Find Garry's Mod ---------------------------------------
GMOD="${1:-}"

if [[ -z "$GMOD" ]]; then
    for candidate in \
        "$HOME/.steam/steam/steamapps/common/GarrysMod" \
        "$HOME/.local/share/Steam/steamapps/common/GarrysMod" \
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/common/GarrysMod"; do
        if [[ -d "$candidate/garrysmod" ]]; then
            GMOD="$candidate"
            break
        fi
    done
fi

if [[ -z "$GMOD" ]]; then
    read -r -p "Could not find Garry's Mod. Enter the full path to your GarrysMod folder: " GMOD
fi

GMOD="${GMOD/#\~/$HOME}"
GMOD="${GMOD%/}"

if [[ ! -d "$GMOD/garrysmod" ]]; then
    echo "[ERROR] $GMOD/garrysmod does not exist. Check the path."
    exit 1
fi

echo
echo "Source : $SRC"
echo "Target : $GMOD/garrysmod"
echo

# ---- Install binary modules ---------------------------------
BIN="$GMOD/garrysmod/lua/bin"
mkdir -p "$BIN"

shopt -s nullglob
modules=("$SRC"/gmcl_*_linux64.so "$SRC"/gmsv_*_linux64.so "$SRC"/gmcl_*_linux.so "$SRC"/gmsv_*_linux.so)
shopt -u nullglob

if (( ${#modules[@]} == 0 )); then
    echo "[WARNING] No Linux module (.so) files found next to this script."
    echo "          The repo currently ships Windows DLLs only. The Lua files will"
    echo "          still be installed, but the binary modules will not load on Linux"
    echo "          until you add gmcl_*_linux64.so / gmsv_*_linux64.so builds."
else
    for f in "${modules[@]}"; do
        cp -f "$f" "$BIN/"
        echo "Installed module: $(basename "$f")"
    done
fi

# ---- Install addon files (lua + addon.json) -----------------
ADDON="$GMOD/garrysmod/addons/Hotloader"
mkdir -p "$ADDON"

if [[ -d "$SRC/lua" ]]; then
    cp -rf "$SRC/lua" "$ADDON/"
    echo "Installed addon files: $ADDON/lua"
fi
cp -f "$SRC/addon.json" "$ADDON/"
echo "Installed addon.json"

echo
echo "Done. Restart Garry's Mod (or your server) to load Hotloader."
