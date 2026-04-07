#!/bin/bash
# Setup for Electronics Sourcing Research task
set -e

TASK_NAME="electronics_sourcing_research"
REPORT_FILE="/home/ga/Desktop/sourcing_report.txt"
EVIDENCE_DIR="/home/ga/Pictures/Evidence"
START_TS_FILE="/tmp/task_start_ts_${TASK_NAME}.txt"

echo "=== Setting up ${TASK_NAME} ==="

# 1. Kill any running Edge instances to ensure clean state
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# 2. clean up previous artifacts
echo "Cleaning up artifacts..."
rm -f "${REPORT_FILE}"
rm -rf "${EVIDENCE_DIR}"
# Create Pictures folder if it doesn't exist, but NOT the Evidence subfolder (agent should do that)
mkdir -p /home/ga/Pictures
chown ga:ga /home/ga/Pictures

# 3. Reset Bookmarks to default/clean state
echo "Resetting bookmarks..."
BOOKMARKS_FILE="/home/ga/.config/microsoft-edge/Default/Bookmarks"
mkdir -p "$(dirname "$BOOKMARKS_FILE")"
# Simple default bookmarks file
cat > "$BOOKMARKS_FILE" << 'EOF'
{
   "roots": {
      "bookmark_bar": {
         "children": [],
         "date_added": "0",
         "date_last_used": "0",
         "date_modified": "0",
         "guid": "00000000-0000-0000-0000-000000000001",
         "id": "1",
         "name": "Favorites bar",
         "type": "folder"
      },
      "other": {
         "children": [],
         "date_added": "0",
         "date_last_used": "0",
         "date_modified": "0",
         "guid": "00000000-0000-0000-0000-000000000002",
         "id": "2",
         "name": "Other favorites",
         "type": "folder"
      },
      "synced": {
         "children": [],
         "date_added": "0",
         "date_last_used": "0",
         "date_modified": "0",
         "guid": "00000000-0000-0000-0000-000000000003",
         "id": "3",
         "name": "Mobile favorites",
         "type": "folder"
      }
   },
   "version": 1
}
EOF
chown -R ga:ga "/home/ga/.config/microsoft-edge"

# 4. Record task start timestamp
echo "Recording start time..."
date +%s > "${START_TS_FILE}"

# 5. Launch Edge to a blank page
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    about:blank > /tmp/edge.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "edge|microsoft"; then
        echo "Edge started."
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Microsoft Edge" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true

echo "=== Setup complete ==="