#!/bin/bash
echo "=== Setting up create_external_image_gallery task ==="

source /workspace/scripts/task_utils.sh

# Record initial tiddler count
INITIAL_COUNT=$(count_user_tiddlers)
echo "$INITIAL_COUNT" > /tmp/initial_tiddler_count
echo "Initial tiddler count: $INITIAL_COUNT"

# Verify TiddlyWiki is running
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
else
    echo "WARNING: TiddlyWiki server not accessible"
fi

# Ensure clean slate: Remove target tiddlers if they exist from a previous broken run
for target in "Colosseum" "Taj Mahal" "Machu Picchu" "World Heritage Gallery"; do
    sanitized=$(echo "$target" | sed 's/[\/\\:*?"<>|]/_/g')
    rm -f "$TIDDLER_DIR/${sanitized}.tid" 2>/dev/null || true
done

# Ensure Firefox is focused on TiddlyWiki
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

# Task timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

echo "=== Task setup complete ==="