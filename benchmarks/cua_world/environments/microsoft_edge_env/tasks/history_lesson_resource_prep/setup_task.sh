#!/bin/bash
# setup_task.sh - Pre-task hook for history_lesson_resource_prep

set -e

echo "=== Setting up History Lesson Resource Prep task ==="

# Source utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# 1. Kill any existing Edge instances
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# 2. Clean up artifacts from previous runs
echo "Cleaning up files..."
rm -f /home/ga/Documents/amendment_worksheet.txt
rm -rf /home/ga/Downloads/*
# Ensure directories exist
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Downloads
chown -R ga:ga /home/ga/Documents
chown -R ga:ga /home/ga/Downloads

# 3. Reset Bookmarks to a clean state
# We want to detect a *new* bookmark, so starting clean helps, 
# but preserving default structure is safer for Edge.
PROFILE_DIR="/home/ga/.config/microsoft-edge/Default"
mkdir -p "$PROFILE_DIR"
BOOKMARKS_FILE="$PROFILE_DIR/Bookmarks"

echo "Resetting bookmarks..."
cat > "$BOOKMARKS_FILE" << 'EOF'
{
   "roots": {
      "bookmark_bar": {
         "children": [],
         "date_added": "13300000000000000",
         "date_last_used": "0",
         "date_modified": "0",
         "guid": "00000000-0000-0000-0000-000000000001",
         "id": "1",
         "name": "Favorites bar",
         "type": "folder"
      },
      "other": {
         "children": [],
         "date_added": "13300000000000000",
         "date_last_used": "0",
         "date_modified": "0",
         "guid": "00000000-0000-0000-0000-000000000002",
         "id": "2",
         "name": "Other favorites",
         "type": "folder"
      },
      "synced": {
         "children": [],
         "date_added": "13300000000000000",
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
chown ga:ga "$BOOKMARKS_FILE"

# 4. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 5. Launch Microsoft Edge
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --disable-extensions \
    --disable-component-update \
    --disable-background-networking \
    --disable-client-side-phishing-detection \
    --disable-default-apps \
    --disable-infobars \
    --password-store=basic \
    about:blank > /tmp/edge.log 2>&1 &"

# 6. Wait for Edge window
echo "Waiting for Edge window..."
TIMEOUT=30
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "edge|microsoft"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# Maximize window
sleep 2
DISPLAY=:1 wmctrl -r "Microsoft Edge" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="