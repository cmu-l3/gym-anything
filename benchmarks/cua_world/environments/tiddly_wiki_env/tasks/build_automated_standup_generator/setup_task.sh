#!/bin/bash
echo "=== Setting up build_automated_standup_generator task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time

# Seed historical standups for the agent to use as validation context
cat > "$TIDDLER_DIR/2026-03-05 - Daily Standup.tid" << 'EOF'
created: 20260305100000000
modified: 20260305101500000
tags: Standup
title: 2026-03-05 - Daily Standup
type: text/vnd.tiddlywiki

! Yesterday
Finished the login page UI.

! Today
Starting on the backend API integration.

! Blockers
None.
EOF

cat > "$TIDDLER_DIR/2026-03-06 - Daily Standup.tid" << 'EOF'
created: 20260306100000000
modified: 20260306101500000
tags: Standup
title: 2026-03-06 - Daily Standup
type: text/vnd.tiddlywiki

! Yesterday
Backend API integration mostly done.

! Today
Writing tests for the API.

! Blockers
Waiting for DevOps to provision staging DB.
EOF

# Fix permissions to ensure node server can pick them up
chown ga:ga "$TIDDLER_DIR/"*.tid

# Wait for TW to detect changes
sleep 2

# Verify TiddlyWiki is running
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
fi

# Ensure Firefox is focused
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

take_screenshot /tmp/standup_initial.png

echo "=== Task setup complete ==="