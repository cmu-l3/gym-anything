#!/bin/bash
echo "=== Setting up create_kb_article task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Record initial KB article count
# Note: SuiteCRM uses aok_knowledgebase for Advanced OpenKnowledgebase
INITIAL_KB_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM aok_knowledgebase WHERE deleted=0" 2>/dev/null | tr -d '[:space:]')
if [ -z "$INITIAL_KB_COUNT" ]; then
    INITIAL_KB_COUNT="0"
fi
echo "$INITIAL_KB_COUNT" > /tmp/initial_kb_count.txt
echo "Initial KB article count: $INITIAL_KB_COUNT"

# 3. Verify the target article does not already exist (clean state)
TARGET_NAME="Resolving Payment Gateway Timeout Errors (Code PG-408)"
TARGET_EXISTS=$(suitecrm_db_query "SELECT COUNT(*) FROM aok_knowledgebase WHERE name='${TARGET_NAME}' AND deleted=0" 2>/dev/null | tr -d '[:space:]')

if [ -n "$TARGET_EXISTS" ] && [ "$TARGET_EXISTS" -gt 0 ]; then
    echo "WARNING: KB Article already exists, removing for clean state"
    soft_delete_record "aok_knowledgebase" "name='${TARGET_NAME}'"
fi

# 4. Ensure logged in and navigate to Home dashboard
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"
sleep 3

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== create_kb_article task setup complete ==="
echo "Task: Create a new Knowledge Base article regarding payment gateway timeouts."