#!/bin/bash
echo "=== Setting up fiction_worldbuilding_wiki task ==="

source /workspace/scripts/task_utils.sh

INITIAL_COUNT=$(count_user_tiddlers)
echo "$INITIAL_COUNT" > /tmp/fiction_worldbuilding_wiki_initial_count
echo "Initial tiddler count: $INITIAL_COUNT"

date +%s > /tmp/fiction_worldbuilding_wiki_start_ts

if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
else
    echo "WARNING: TiddlyWiki server not accessible"
fi

DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

take_screenshot /tmp/fiction_worldbuilding_wiki_initial.png

echo "=== Task setup complete ==="
