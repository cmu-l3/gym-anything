#!/bin/bash
# setup_task.sh - Pre-task hook for bookmark_library_export
set -e

echo "=== Setting up Bookmark Library Export Task ==="

# 1. Record start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Kill Edge to ensure clean state and file access
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true

# 3. Clean up previous artifacts
rm -f /home/ga/Desktop/district_bookmarks.html
rm -f /home/ga/Desktop/bookmark_instructions.txt

# 4. Reset Bookmarks to a clean state (keep basic roots)
PROFILE_DIR="/home/ga/.config/microsoft-edge/Default"
mkdir -p "$PROFILE_DIR"
BOOKMARKS_FILE="$PROFILE_DIR/Bookmarks"

cat > "$BOOKMARKS_FILE" << 'EOF'
{
   "checksum": "0",
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

# 5. Launch Edge to ensure it's ready for the user
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    about:blank > /dev/null 2>&1 &"

# Wait for Edge window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "edge|microsoft"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="