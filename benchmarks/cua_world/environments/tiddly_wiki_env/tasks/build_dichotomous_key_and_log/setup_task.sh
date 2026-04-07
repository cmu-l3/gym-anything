#!/bin/bash
echo "=== Setting up build_dichotomous_key_and_log task ==="

source /workspace/scripts/task_utils.sh

# Record initial tiddler count
INITIAL_COUNT=$(count_user_tiddlers)
echo "$INITIAL_COUNT" > /tmp/initial_tiddler_count
echo "Initial tiddler count: $INITIAL_COUNT"

# Record task start time
date +%s > /tmp/task_start_time

# Verify TiddlyWiki is running
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
else
    echo "WARNING: TiddlyWiki server not responding"
fi

# Ensure Firefox is focused
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/dichotomous_key_initial.png

echo "=== Task setup complete ==="