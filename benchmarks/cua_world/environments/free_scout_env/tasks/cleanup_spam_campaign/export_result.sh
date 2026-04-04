#!/bin/bash
echo "=== Exporting Cleanup Spam Campaign Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Capture timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# SQL Queries to check status
# We join conversations -> customers -> emails to identify tickets by sender email
# 'deleted_at' column in 'conversations' table is non-null if deleted/trashed

# 1. Get stats for SPAM tickets
SPAM_QUERY="
SELECT 
    COUNT(*) as total, 
    SUM(CASE WHEN c.deleted_at IS NOT NULL THEN 1 ELSE 0 END) as deleted 
FROM conversations c
JOIN customers cu ON c.customer_id = cu.id
JOIN emails e ON cu.id = e.customer_id
WHERE e.email LIKE '%@spam-lottery.xyz'
"
SPAM_RESULT=$(fs_query "$SPAM_QUERY")
SPAM_TOTAL=$(echo "$SPAM_RESULT" | awk '{print $1}')
SPAM_DELETED=$(echo "$SPAM_RESULT" | awk '{print $2}')

# Handle NULL return from SQL SUM if 0
if [ "$SPAM_DELETED" == "NULL" ] || [ -z "$SPAM_DELETED" ]; then SPAM_DELETED=0; fi

# 2. Get stats for LEGIT tickets
LEGIT_QUERY="
SELECT 
    COUNT(*) as total, 
    SUM(CASE WHEN c.deleted_at IS NOT NULL THEN 1 ELSE 0 END) as deleted 
FROM conversations c
JOIN customers cu ON c.customer_id = cu.id
JOIN emails e ON cu.id = e.customer_id
WHERE e.email LIKE '%@legit-lotto.com'
"
LEGIT_RESULT=$(fs_query "$LEGIT_QUERY")
LEGIT_TOTAL=$(echo "$LEGIT_RESULT" | awk '{print $1}')
LEGIT_DELETED=$(echo "$LEGIT_RESULT" | awk '{print $2}')

# Handle NULL return
if [ "$LEGIT_DELETED" == "NULL" ] || [ -z "$LEGIT_DELETED" ]; then LEGIT_DELETED=0; fi

# 3. Check for Anti-Gaming (Bulk deletion of everything)
# Count TOTAL active non-spam conversations in the mailbox
# This ensures the agent didn't just delete the whole mailbox
OTHER_ACTIVE_QUERY="
SELECT COUNT(*) 
FROM conversations c
JOIN customers cu ON c.customer_id = cu.id
JOIN emails e ON cu.id = e.customer_id
WHERE e.email NOT LIKE '%@spam-lottery.xyz'
AND c.deleted_at IS NULL
"
OTHER_ACTIVE_COUNT=$(fs_query "$OTHER_ACTIVE_QUERY" 2>/dev/null || echo "0")


# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "spam_total": ${SPAM_TOTAL:-0},
    "spam_deleted": ${SPAM_DELETED:-0},
    "legit_total": ${LEGIT_TOTAL:-0},
    "legit_deleted": ${LEGIT_DELETED:-0},
    "other_active_count": ${OTHER_ACTIVE_COUNT:-0},
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="