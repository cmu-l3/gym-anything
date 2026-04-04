#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting block_spam_domain result ==="

# Take final screenshot
take_screenshot /tmp/task_end.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_blacklist_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(fs_query "SELECT COUNT(*) FROM blacklists" 2>/dev/null || echo "0")

# Define target data
TARGET_DOMAIN="network-security-update.io"

echo "Checking for blacklist rules matching: $TARGET_DOMAIN"

# Query for any rules matching the domain
# getting: id, type, value, note, created_at
RULES_DATA=$(fs_query "SELECT id, type, value, note, created_at FROM blacklists WHERE value LIKE '%$TARGET_DOMAIN%' ORDER BY id DESC" 2>/dev/null || echo "")

# Count how many rules match
MATCHING_RULE_COUNT=0
if [ -n "$RULES_DATA" ]; then
    MATCHING_RULE_COUNT=$(echo "$RULES_DATA" | wc -l)
fi

# Parse the most recent rule if exists
RULE_FOUND="false"
RULE_ID=""
RULE_TYPE=""
RULE_VALUE=""
RULE_NOTE=""
RULE_CREATED_AT=""
RULE_CREATED_DURING_TASK="false"

if [ -n "$RULES_DATA" ]; then
    # Get the top row (most recent due to ORDER BY id DESC)
    TOP_RULE=$(echo "$RULES_DATA" | head -n 1)
    
    RULE_FOUND="true"
    RULE_ID=$(echo "$TOP_RULE" | cut -f1)
    RULE_TYPE=$(echo "$TOP_RULE" | cut -f2)
    RULE_VALUE=$(echo "$TOP_RULE" | cut -f3)
    RULE_NOTE=$(echo "$TOP_RULE" | cut -f4)
    RULE_CREATED_AT=$(echo "$TOP_RULE" | cut -f5)
    
    # Check timestamp (SQL created_at is usually YYYY-MM-DD HH:MM:SS)
    # We convert to unix timestamp for comparison
    CREATED_TS=$(date -d "$RULE_CREATED_AT" +%s 2>/dev/null || echo "0")
    
    # Allow 1 minute buffer for clock drift
    if [ "$CREATED_TS" -ge "$((TASK_START - 60))" ]; then
        RULE_CREATED_DURING_TASK="true"
    fi
fi

# Escape for JSON safety
RULE_VALUE_ESC=$(echo "$RULE_VALUE" | sed 's/"/\\"/g')
RULE_NOTE_ESC=$(echo "$RULE_NOTE" | sed 's/"/\\"/g')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "rule_found": $RULE_FOUND,
    "rule_id": "$RULE_ID",
    "rule_value": "$RULE_VALUE_ESC",
    "rule_note": "$RULE_NOTE_ESC",
    "rule_created_during_task": $RULE_CREATED_DURING_TASK,
    "target_domain": "$TARGET_DOMAIN",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="