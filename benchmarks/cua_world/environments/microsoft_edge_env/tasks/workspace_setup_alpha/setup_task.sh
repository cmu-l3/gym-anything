#!/bin/bash
# Setup for Workspace Setup task
# Ensures clean state for Edge bookmarks and preferences.

set -e

TASK_NAME="workspace_setup_alpha"
DOCUMENTS_DIR="/home/ga/Documents"
TARGET_EXPORT="$DOCUMENTS_DIR/initial_setup.html"
START_TS_FILE="/tmp/task_start_ts.txt"

echo "=== Setting up ${TASK_NAME} ==="

# 1. Stop Edge
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true

# 2. clean up previous artifacts
echo "Cleaning up artifacts..."
rm -f "$TARGET_EXPORT"
mkdir -p "$DOCUMENTS_DIR"
chown ga:ga "$DOCUMENTS_DIR"

# 3. Reset Edge User Data to a known clean state (bookmarks/prefs)
# We overwrite Bookmarks with a clean skeleton to ensure no pre-existing 'Dev Tools' folder
PROFILE_DIR="/home/ga/.config/microsoft-edge/Default"
mkdir -p "$PROFILE_DIR"

cat > "$PROFILE_DIR/Bookmarks" << 'EOF'
{
   "roots": {
      "bookmark_bar": {
         "children": [],
         "date_added": "13200000000000000",
         "date_last_used": "0",
         "date_modified": "0",
         "guid": "00000000-0000-4000-a000-000000000002",
         "id": "1",
         "name": "Favorites bar",
         "type": "folder"
      },
      "other": {
         "children": [],
         "date_added": "13200000000000000",
         "date_last_used": "0",
         "date_modified": "0",
         "guid": "00000000-0000-4000-a000-000000000003",
         "id": "2",
         "name": "Other favorites",
         "type": "folder"
      },
      "synced": {
         "children": [],
         "date_added": "13200000000000000",
         "date_last_used": "0",
         "date_modified": "0",
         "guid": "00000000-0000-4000-a000-000000000004",
         "id": "3",
         "name": "Mobile favorites",
         "type": "folder"
      }
   },
   "version": 1
}
EOF
chown ga:ga "$PROFILE_DIR/Bookmarks"

# Reset Preferences to ensure startup settings are default
# (We use python to preserve other needed prefs if they exist, or create new)
python3 << 'PYEOF'
import json, os
prefs_path = "/home/ga/.config/microsoft-edge/Default/Preferences"
prefs = {}

# Default minimal prefs
if os.path.exists(prefs_path):
    try:
        with open(prefs_path, 'r') as f:
            prefs = json.load(f)
    except:
        pass

# Ensure bookmark bar is visible so agent can see what they are doing
if "bookmark_bar" not in prefs:
    prefs["bookmark_bar"] = {}
prefs["bookmark_bar"]["show_on_all_tabs"] = True

# Reset startup settings (restore_on_startup: 5 = open new tab page, 1 = restore last session, 4 = open specific URLs)
# We want to reset it so it's NOT already set to the target
if "session" not in prefs:
    prefs["session"] = {}
prefs["session"]["restore_on_startup"] = 5
prefs["session"]["startup_urls"] = []

with open(prefs_path, 'w') as f:
    json.dump(prefs, f)
PYEOF
chown ga:ga "$PROFILE_DIR/Preferences"

# 4. Record Start Time
date +%s > "$START_TS_FILE"

# 5. Launch Edge
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    > /tmp/edge.log 2>&1 &"

# Wait for window
TIMEOUT=30
for i in $(seq 1 $TIMEOUT); do
    if DISPLAY=:1 wmctrl -l | grep -iE "edge|microsoft"; then
        echo "Edge window found."
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Edge" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== Setup complete ==="