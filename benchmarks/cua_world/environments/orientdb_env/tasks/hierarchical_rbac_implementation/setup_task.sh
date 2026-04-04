#!/bin/bash
echo "=== Setting up Hierarchical RBAC Implementation Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is ready
wait_for_orientdb 60

# Clean up any previous attempts (Idempotency)
echo "Cleaning up any existing RBAC classes in demodb..."
# We use a broad suppression here because commands fail if classes don't exist
orientdb_sql "demodb" "DROP CLASS HasAccess UNSAFE" > /dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS MemberOf UNSAFE" > /dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS AppUser UNSAFE" > /dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS AppGroup UNSAFE" > /dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS AppResource UNSAFE" > /dev/null 2>&1 || true

# Remove any previous result file
rm -f /home/ga/sarah_entitlements.json

# Launch Firefox to OrientDB Studio
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="