#!/bin/bash
# setup_task.sh - Pre-task hook for add_bookmark task
# Prepares Microsoft Edge environment for bookmark addition

set -e

echo "=== Setting up add_bookmark task ==="

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

# Count existing bookmarks before task
INITIAL_BOOKMARK_COUNT=0
WIKIPEDIA_ALREADY_BOOKMARKED="false"

if [ -f "$BOOKMARKS_FILE" ]; then
    # Count bookmarks using Python
    INITIAL_BOOKMARK_COUNT=$(python3 << 'PYEOF'
import json
import sys

try:
    with open("/home/ga/.config/microsoft-edge/Default/Bookmarks", 'r') as f:
        data = json.load(f)

    def count_bookmarks(node):
        count = 0
        if node.get('type') == 'url':
            count = 1
        elif node.get('type') == 'folder':
            for child in node.get('children', []):
                count += count_bookmarks(child)
        return count

    total = 0
    for root_name, root_node in data.get('roots', {}).items():
        if isinstance(root_node, dict):
            total += count_bookmarks(root_node)

    print(total)
except:
    print(0)
PYEOF
)

    # Check if wikipedia.org is already bookmarked
    EXISTING=$(python3 << 'PYEOF'
import json

try:
    with open("/home/ga/.config/microsoft-edge/Default/Bookmarks", 'r') as f:
        data = json.load(f)

    def find_wikipedia(node):
        if node.get('type') == 'url':
            url = node.get('url', '').lower()
            if 'wikipedia.org' in url:
                return True
        elif node.get('type') == 'folder':
            for child in node.get('children', []):
                if find_wikipedia(child):
                    return True
        return False

    found = False
    for root_name, root_node in data.get('roots', {}).items():
        if isinstance(root_node, dict) and find_wikipedia(root_node):
            found = True
            break

    print("true" if found else "false")
except:
    print("false")
PYEOF
)
    WIKIPEDIA_ALREADY_BOOKMARKED="$EXISTING"
fi

echo "Initial bookmark count: $INITIAL_BOOKMARK_COUNT"
echo "$INITIAL_BOOKMARK_COUNT" > /tmp/initial_bookmark_count

if [ "$WIKIPEDIA_ALREADY_BOOKMARKED" = "true" ]; then
    echo "WARNING: Wikipedia already bookmarked"
fi
echo "$WIKIPEDIA_ALREADY_BOOKMARKED" > /tmp/wikipedia_already_bookmarked

# Ensure Downloads directory exists
sudo -u ga mkdir -p /home/ga/Downloads

# Create task info file for reference
cat > /home/ga/TASK_INFO.txt << 'EOF'
TASK: Add Bookmark

Your task is to add Wikipedia as a bookmark in Microsoft Edge.

Steps:
1. Open Microsoft Edge (it may already be open)
2. Navigate to https://www.wikipedia.org
3. Add the page as a bookmark using:
   - Press Ctrl+D, OR
   - Click the star icon in the address bar, OR
   - Use the "..." menu -> Favorites -> Add current page

The bookmark should be saved successfully.
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

echo "=== add_bookmark task setup complete ==="
echo "Microsoft Edge is running. Ready for agent to navigate to wikipedia.org and add bookmark."
