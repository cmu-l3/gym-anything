#!/bin/bash
echo "=== Exporting User Access Review Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# ---------------------------------------------------------------
# Extract Review Data
# ---------------------------------------------------------------
# We need to get the status and comments for the items in our specific review
# We'll use JSON output from MySQL for cleaner parsing in python verifier if possible,
# but simple CSV/TSV is more reliable with basic docker exec.

# Query explanation:
# Join items with review to ensure we get the right ones
# Select account name, status (integer), and feedback (comment)
# status in Eramba: typically 1=OK/Keep, 2=Problem/Revoke (checking actual values via logic later)

QUERY="SELECT 
    i.account, 
    COALESCE(i.status, 'NULL'), 
    COALESCE(i.feedback, ''), 
    UNIX_TIMESTAMP(i.modified)
FROM account_review_items i
JOIN account_reviews r ON i.account_review_id = r.id
WHERE r.name = 'Q3 2025 HR DB Access Review';"

# Create a temporary file for the SQL result
TEMP_SQL_RESULT=$(mktemp)
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "$QUERY" > "$TEMP_SQL_RESULT" 2>/dev/null

# Convert SQL result to JSON structure
# Format: [{"account": "...", "status": "...", "feedback": "...", "modified": ...}, ...]
JSON_ITEMS="[]"
if [ -s "$TEMP_SQL_RESULT" ]; then
    # Use jq to build the JSON array (safest way to handle strings)
    # We read the file line by line
    JSON_ITEMS=$(cat "$TEMP_SQL_RESULT" | jq -R -s -c '
      split("\n") | map(select(length > 0)) | map(
        split("\t") | {
          account: .[0],
          status: .[1],
          feedback: .[2],
          modified: .[3]
        }
      )
    ')
fi
rm -f "$TEMP_SQL_RESULT"

# Get initial count for comparison
INITIAL_COMPLETED=$(cat /tmp/initial_completed_count.txt 2>/dev/null || echo "0")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_completed_count": $INITIAL_COMPLETED,
    "review_items": $JSON_ITEMS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="