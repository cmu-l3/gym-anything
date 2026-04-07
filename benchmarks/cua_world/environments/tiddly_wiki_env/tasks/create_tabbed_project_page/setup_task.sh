#!/bin/bash
echo "=== Setting up create_tabbed_project_page task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Record initial tiddler count
INITIAL_COUNT=$(count_user_tiddlers)
echo "$INITIAL_COUNT" > /tmp/initial_tiddler_count
echo "Initial tiddler count: $INITIAL_COUNT"

# Verify TiddlyWiki is running
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
else
    echo "WARNING: TiddlyWiki server not responding!"
fi

# Ensure Firefox is focused on TiddlyWiki
DISPLAY=:1 wmctrl -a "TiddlyWiki" 2>/dev/null || DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
sleep 1
# Maximize browser window to ensure agent can see UI elements
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/tabbed_page_initial.png

echo "=== Task setup complete ==="