#!/bin/bash
set -e
echo "=== Setting up create_account_review task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (critical for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Record initial state of account reviews
# We check a few likely table names since Eramba schema can vary by version, 
# but 'account_reviews' is standard.
echo "Recording initial database state..."
INITIAL_COUNT=$(eramba_db_query "SELECT COUNT(*) FROM account_reviews;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_count.txt
echo "Initial account_reviews count: $INITIAL_COUNT"

# 3. Ensure Eramba is running and accessible
# The utils function checks if Firefox is running; if not, starts it pointing to Eramba
ensure_firefox_eramba "http://localhost:8080/dashboard/dashboard"

# 4. Maximize window to ensure UI elements are visible to agent
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="