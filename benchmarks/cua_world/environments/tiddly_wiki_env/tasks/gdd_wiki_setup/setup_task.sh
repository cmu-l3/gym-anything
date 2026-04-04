#!/bin/bash
echo "=== Setting up gdd_wiki_setup task ==="

source /workspace/scripts/task_utils.sh

# Record initial tiddler count (before any agent actions)
INITIAL_COUNT=$(count_user_tiddlers)
echo "$INITIAL_COUNT" > /tmp/gdd_wiki_setup_initial_count
echo "Initial tiddler count: $INITIAL_COUNT"

# Record task start timestamp
date +%s > /tmp/gdd_wiki_setup_start_ts

# Verify TiddlyWiki is running
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
else
    echo "WARNING: TiddlyWiki server not accessible"
fi

# Ensure Firefox is focused on TiddlyWiki
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/gdd_wiki_setup_initial.png

echo "=== Task setup complete ==="
