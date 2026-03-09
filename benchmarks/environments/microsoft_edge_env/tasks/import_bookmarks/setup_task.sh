#!/bin/bash
# setup_task.sh - Pre-task hook for import_bookmarks task
# Prepares Microsoft Edge environment for bookmark import

set -e

echo "=== Setting up import_bookmarks task ==="

# Source utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# Kill any existing Edge instances
echo "Killing any existing Edge instances..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# Get profile path
PROFILE_DIR="/home/ga/.config/microsoft-edge/Default"
BOOKMARKS_FILE="$PROFILE_DIR/Bookmarks"

echo "Edge profile: $PROFILE_DIR"

# Clear any existing bookmarks to start fresh
if [ -f "$BOOKMARKS_FILE" ]; then
    echo "Clearing existing bookmarks for fresh import test..."
    # Create empty bookmarks structure without checksum (Edge will regenerate)
    cat > "$BOOKMARKS_FILE" << 'EOF'
{
   "roots": {
      "bookmark_bar": {
         "children": [  ],
         "date_added": "13377882825000000",
         "date_last_used": "0",
         "date_modified": "0",
         "guid": "0bc5d13f-2cba-5d74-951f-3f233fe6c908",
         "id": "1",
         "name": "Favorites bar",
         "source": "unknown",
         "type": "folder"
      },
      "other": {
         "children": [  ],
         "date_added": "13377882825000000",
         "date_last_used": "0",
         "date_modified": "0",
         "guid": "82b081ec-3dd3-529c-8475-ab6c344590dd",
         "id": "2",
         "name": "Other favorites",
         "source": "unknown",
         "type": "folder"
      },
      "synced": {
         "children": [  ],
         "date_added": "13377882825000000",
         "date_last_used": "0",
         "date_modified": "0",
         "guid": "4cf2e351-0e85-532b-bb37-df045d8f8d0f",
         "id": "3",
         "name": "Mobile favorites",
         "source": "unknown",
         "type": "folder"
      }
   },
   "version": 1
}
EOF
    chown ga:ga "$BOOKMARKS_FILE"
fi

# Count initial bookmarks (should be 0)
INITIAL_BOOKMARK_COUNT=0
echo "$INITIAL_BOOKMARK_COUNT" > /tmp/initial_bookmark_count
echo "Initial bookmark count: $INITIAL_BOOKMARK_COUNT"

# Copy the bookmarks HTML file to user's home for easy access
BOOKMARKS_HTML="/workspace/assets/sample_bookmarks.html"
if [ -f "$BOOKMARKS_HTML" ]; then
    cp "$BOOKMARKS_HTML" /home/ga/bookmarks_to_import.html
    chown ga:ga /home/ga/bookmarks_to_import.html
    echo "Bookmarks file copied to: /home/ga/bookmarks_to_import.html"

    # Count bookmarks in the HTML file for reference
    EXPECTED_COUNT=$(grep -c '<DT><A HREF=' "$BOOKMARKS_HTML" || echo "0")
    echo "Expected bookmarks to import: $EXPECTED_COUNT"
    echo "$EXPECTED_COUNT" > /tmp/expected_bookmark_count
else
    echo "ERROR: Bookmarks HTML file not found at $BOOKMARKS_HTML"
    echo "0" > /tmp/expected_bookmark_count
fi

# Ensure Downloads directory exists
sudo -u ga mkdir -p /home/ga/Downloads

# Create task info file for reference
cat > /home/ga/TASK_INFO.txt << 'EOF'
TASK: Import Bookmarks

Your task is to import bookmarks from an HTML file into Microsoft Edge.

The bookmarks file is located at: /home/ga/bookmarks_to_import.html

Steps to import bookmarks in Edge:
1. Click the three dots menu (...) in the top right corner
2. Select "Settings"
3. Click "Profiles" in the left sidebar
4. Click "Import browser data"
5. In the "Import from" dropdown, select "Favorites or bookmarks HTML file"
6. Click "Choose file" and navigate to /home/ga/bookmarks_to_import.html
7. Select the file and click "Import"

The bookmarks should appear in your Favorites after import.
EOF
chown ga:ga /home/ga/TASK_INFO.txt

# Launch Microsoft Edge
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
    > /tmp/edge.log 2>&1 &"

# Wait for Edge to start
echo "Waiting for Microsoft Edge to start..."
TIMEOUT=30
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if pgrep -u ga -f microsoft-edge > /dev/null || pgrep -u ga -f msedge > /dev/null; then
        echo "Edge process started after ${ELAPSED}s"
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# Wait for Edge window to appear
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "edge|microsoft"; then
        echo "Edge window appeared after ${ELAPSED}s"
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# Give Edge a moment to fully initialize
sleep 5

# Focus Edge window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "edge|microsoft" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
    echo "Focused Edge window: $WINDOW_ID"
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== import_bookmarks task setup complete ==="
echo "Microsoft Edge is running."
echo "Import the bookmarks from: /home/ga/bookmarks_to_import.html"
