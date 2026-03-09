#!/bin/bash
echo "=== Setting up rename_tiddler task ==="

source /workspace/scripts/task_utils.sh

ORIGINAL_TITLE="Q1 2024 Product Roadmap"

# Verify original tiddler exists
if [ "$(tiddler_exists "$ORIGINAL_TITLE")" = "true" ]; then
    echo "Original tiddler '$ORIGINAL_TITLE' exists"
    # Save original content hash for later verification
    ORIGINAL_TAGS=$(get_tiddler_field "$ORIGINAL_TITLE" "tags")
    ORIGINAL_TEXT=$(get_tiddler_text "$ORIGINAL_TITLE")
    echo "$ORIGINAL_TAGS" > /tmp/original_tags
    echo "$ORIGINAL_TEXT" | wc -w > /tmp/original_word_count
    echo "Original tags: $ORIGINAL_TAGS"
    echo "Original word count: $(cat /tmp/original_word_count)"
else
    echo "WARNING: Original tiddler '$ORIGINAL_TITLE' not found!"
fi

# Record initial state
count_user_tiddlers > /tmp/initial_tiddler_count

# Verify TiddlyWiki is running
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
fi

DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

take_screenshot /tmp/rename_initial.png

echo "=== Task setup complete ==="
