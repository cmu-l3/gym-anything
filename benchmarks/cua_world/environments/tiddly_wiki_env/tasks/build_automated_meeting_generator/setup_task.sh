#!/bin/bash
echo "=== Setting up build_automated_meeting_generator task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (critical for anti-gaming to ensure output is created DURING task)
date +%s > /tmp/task_start_time
touch /tmp/task_start_marker

# Seed a past retrospective to set context and prove system works
PAST_RETRO_FILE="$TIDDLER_DIR/Sprint Retrospective - 2026-02-23.tid"
cat > "$PAST_RETRO_FILE" << 'EOF'
created: 20260223120000000
modified: 20260223120000000
tags: Meeting Retrospective
title: Sprint Retrospective - 2026-02-23
type: text/vnd.tiddlywiki

! What went well
* Completed the API migration ahead of schedule.
* Good communication with the frontend team.

! What could be improved
* CI/CD pipeline was slow during peak hours.

! Action Items
* Investigate caching for CI runner (Assigned: Alex)
EOF
chown ga:ga "$PAST_RETRO_FILE"

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

# Ensure Firefox is focused on TiddlyWiki
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

# Take initial screenshot showing the starting state
sleep 1
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="