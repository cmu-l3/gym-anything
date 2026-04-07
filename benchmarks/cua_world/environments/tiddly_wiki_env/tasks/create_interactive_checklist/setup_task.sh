#!/bin/bash
echo "=== Setting up create_interactive_checklist task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure TiddlyWiki is running
if ! curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "WARNING: TiddlyWiki server not accessible at start"
fi

# Seed the four task tiddlers
echo "Creating pre-requisite task tiddlers..."

cat > "$TIDDLER_DIR/Task_ Order Laptop.tid" << 'EOF'
title: Task: Order Laptop
status: pending
tags: HRTask

Request standard developer machine via IT portal. Ensure 32GB RAM minimum for engineering profiles.
EOF

cat > "$TIDDLER_DIR/Task_ Create Email Account.tid" << 'EOF'
title: Task: Create Email Account
status: pending
tags: HRTask

Provision Google Workspace account and assign to standard engineering mailing lists.
EOF

cat > "$TIDDLER_DIR/Task_ Building Access Badge.tid" << 'EOF'
title: Task: Building Access Badge
status: pending
tags: HRTask

Submit photo to security desk for keycard printing.
EOF

cat > "$TIDDLER_DIR/Task_ Benefits Enrollment.tid" << 'EOF'
title: Task: Benefits Enrollment
status: pending
tags: HRTask

Send portal link to new hire for healthcare and 401k selection.
EOF

# Ensure proper permissions so TiddlyWiki can read/write them
chown -R ga:ga "$TIDDLER_DIR"
chmod 644 "$TIDDLER_DIR"/Task_*.tid

# Wait a moment for TiddlyWiki's filesystem watcher to pick them up
sleep 2

# Refresh Firefox to ensure the new tiddlers are loaded in the frontend state
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key F5 2>/dev/null || true
sleep 2

take_screenshot /tmp/checklist_initial.png

echo "=== Task setup complete ==="