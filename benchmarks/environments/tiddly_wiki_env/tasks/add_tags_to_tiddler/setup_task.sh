#!/bin/bash
echo "=== Setting up add_tags_to_tiddler task ==="

source /workspace/scripts/task_utils.sh

# Record current tags on the target tiddler
TARGET="CRISPR Gene Editing"
CURRENT_TAGS=$(get_tiddler_field "$TARGET" "tags")
echo "$CURRENT_TAGS" > /tmp/initial_tags
echo "Initial tags on '$TARGET': $CURRENT_TAGS"

# Verify the target tiddler exists
if [ "$(tiddler_exists "$TARGET")" = "true" ]; then
    echo "Target tiddler '$TARGET' exists"
else
    echo "WARNING: Target tiddler '$TARGET' not found!"
fi

# Verify TiddlyWiki is running
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
fi

# Ensure Firefox is focused
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

take_screenshot /tmp/add_tags_initial.png

echo "=== Task setup complete ==="
