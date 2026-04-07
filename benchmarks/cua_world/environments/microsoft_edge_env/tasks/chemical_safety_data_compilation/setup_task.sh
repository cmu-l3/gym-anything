#!/bin/bash
# setup_task.sh - Pre-task hook for chemical_safety_data_compilation
set -e

echo "=== Setting up Chemical Safety Data Compilation Task ==="

# 1. Kill any running Edge instances
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true

# 2. Clean up previous run artifacts
TARGET_DIR="/home/ga/Documents/Safety_Data"
echo "Cleaning target directory: $TARGET_DIR"
rm -rf "$TARGET_DIR"

# 3. Reset Bookmarks to clean state (no "Emergency Protocols" folder)
PROFILE_DIR="/home/ga/.config/microsoft-edge/Default"
BOOKMARKS_FILE="$PROFILE_DIR/Bookmarks"

mkdir -p "$PROFILE_DIR"

# Create a basic bookmarks file if it doesn't exist or overwrite to ensure clean state
cat > "$BOOKMARKS_FILE" << 'EOF'
{
   "roots": {
      "bookmark_bar": {
         "children": [],
         "date_added": "13200000000000000",
         "date_last_used": "0",
         "date_modified": "0",
         "guid": "00000000-0000-0000-0000-000000000000",
         "id": "1",
         "name": "Favorites bar",
         "type": "folder"
      },
      "other": {
         "children": [],
         "date_added": "13200000000000000",
         "date_last_used": "0",
         "date_modified": "0",
         "guid": "00000000-0000-0000-0000-000000000001",
         "id": "2",
         "name": "Other favorites",
         "type": "folder"
      },
      "synced": {
         "children": [],
         "date_added": "13200000000000000",
         "date_last_used": "0",
         "date_modified": "0",
         "guid": "00000000-0000-0000-0000-000000000002",
         "id": "3",
         "name": "Mobile favorites",
         "type": "folder"
      }
   },
   "version": 1
}
EOF
chown ga:ga "$BOOKMARKS_FILE"

# 4. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 5. Launch Edge to Ensure it's ready
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    --start-maximized \
    'about:blank' > /tmp/edge.log 2>&1 &"

# Wait for Edge window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "edge|microsoft"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
done

# Ensure maximized
sleep 2
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="