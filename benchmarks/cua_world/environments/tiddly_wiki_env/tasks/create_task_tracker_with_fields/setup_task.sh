#!/bin/bash
echo "=== Setting up create_task_tracker_with_fields task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure clean state (remove target tiddlers if they somehow exist)
TARGETS=(
    "Migrate Database to PostgreSQL 16"
    "Update API Documentation"
    "Fix Authentication Timeout Bug"
    "Design New Dashboard Mockups"
    "Set Up CI-CD Pipeline for Staging"
    "Sprint Board"
)

for target in "${TARGETS[@]}"; do
    sanitized=$(echo "$target" | sed 's/[\/\\:*?"<>|]/_/g')
    rm -f "$TIDDLER_DIR/${sanitized}.tid" 2>/dev/null || true
done

# Wait for TiddlyWiki server
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
fi

# Ensure Firefox is focused
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/tracker_initial.png

echo "=== Task setup complete ==="