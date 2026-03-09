#!/bin/bash
set -e
echo "=== Exporting add_document_category result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_count.txt 2>/dev/null || echo "0")

# Capture final screenshot for verification
take_screenshot /tmp/task_final.png

# Query the database for the requested category
# We select lft and rght (nested set model) to verify proper insertion via UI logic
# If lft/rght are 0, it suggests a raw SQL injection or improper creation
QUERY="SELECT id, name, parent, lft, rght FROM categories WHERE name='Telehealth Consent' LIMIT 1"
ROW=$(librehealth_query "$QUERY" 2>/dev/null || echo "")

CATEGORY_FOUND="false"
CAT_ID="0"
CAT_NAME=""
PARENT_ID="0"
LFT="0"
RGHT="0"
PARENT_NAME=""

if [ -n "$ROW" ]; then
    CATEGORY_FOUND="true"
    # Parse tab-separated values
    CAT_ID=$(echo "$ROW" | awk '{print $1}')
    CAT_NAME=$(echo "$ROW" | awk '{print $2}')
    PARENT_ID=$(echo "$ROW" | awk '{print $3}')
    LFT=$(echo "$ROW" | awk '{print $4}')
    RGHT=$(echo "$ROW" | awk '{print $5}')
    
    # Get parent name to verify it's under "Categories"
    if [ "$PARENT_ID" -ne "0" ]; then
        PARENT_NAME=$(librehealth_query "SELECT name FROM categories WHERE id='$PARENT_ID'" 2>/dev/null || echo "")
    fi
fi

# Get current total count
CURRENT_COUNT=$(librehealth_query "SELECT COUNT(*) FROM categories" 2>/dev/null || echo "0")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "category_found": $CATEGORY_FOUND,
    "category_details": {
        "id": $CAT_ID,
        "name": "$CAT_NAME",
        "parent_id": $PARENT_ID,
        "parent_name": "$PARENT_NAME",
        "lft": $LFT,
        "rght": $RGHT
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to expected location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="