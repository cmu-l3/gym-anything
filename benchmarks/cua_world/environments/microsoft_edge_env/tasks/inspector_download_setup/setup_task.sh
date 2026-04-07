#!/bin/bash
# Setup for Inspector Download Station task
# Ensures clean state for Edge preferences and file system.

set -e

TASK_NAME="inspector_download_setup"
START_TS_FILE="/tmp/task_start_ts_${TASK_NAME}.txt"
DOCS_DIR="/home/ga/Documents/InspectionDocs"
MANIFEST_FILE="/home/ga/Desktop/download_manifest.txt"

echo "=== Setting up ${TASK_NAME} ==="

# Source shared utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# ── STEP 1: Kill any running Edge instances ──────────────────────────────────
echo "[1/4] Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# ── STEP 2: Clean up previous run artifacts ──────────────────────────────────
echo "[2/4] Cleaning filesystem..."
rm -rf "${DOCS_DIR}"
rm -f "${MANIFEST_FILE}"
# Also clear default Downloads to avoid confusion
rm -f /home/ga/Downloads/*.pdf 2>/dev/null || true

# ── STEP 3: Reset Edge Preferences to default ────────────────────────────────
# We want to ensure the download path is NOT already set to the target
echo "[3/4] Resetting Edge Preferences..."
PREFS_DIR="/home/ga/.config/microsoft-edge/Default"
mkdir -p "$PREFS_DIR"

python3 << 'PYEOF'
import json, os

prefs_path = "/home/ga/.config/microsoft-edge/Default/Preferences"
default_download = "/home/ga/Downloads"

if os.path.exists(prefs_path):
    try:
        with open(prefs_path, 'r') as f:
            prefs = json.load(f)
    except:
        prefs = {}
else:
    prefs = {}

# Ensure download directory is default
if 'download' not in prefs:
    prefs['download'] = {}
prefs['download']['default_directory'] = default_download
prefs['download']['prompt_for_download'] = True # Default is usually to prompt or save to Downloads

# Ensure savefile directory is default
if 'savefile' not in prefs:
    prefs['savefile'] = {}
prefs['savefile']['default_directory'] = default_download

with open(prefs_path, 'w') as f:
    json.dump(prefs, f)
PYEOF

chown -R ga:ga "/home/ga/.config/microsoft-edge"

# ── STEP 4: Record task start timestamp and Launch ───────────────────────────
echo "[4/4] Recording start time and launching..."
date +%s > "${START_TS_FILE}"

# Launch Edge
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    > /tmp/edge.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "edge|microsoft"; then
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true

echo "=== Setup complete ==="