#!/bin/bash
# Export script for Configure Prevention Alert task

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Record task timing
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Query the 'prevention' table for the newly created rule
# We look for the specific name requested
echo "Querying database for 'Senior Weight Monitor'..."

# Fetch columns: prevention_name, age_min, sex, duration, duration_unit, prevention_type, warning_msg
# Note: Schema column names can vary slightly by Oscar version, but these are standard.
# prevention_type is often a join key or a string code. We'll grab the raw row.

# Get the most recently added prevention rule (highest ID) as a fallback if name doesn't match perfectly
LATEST_RULE=$(oscar_query "SELECT prevention_id, prevention_name, age_min, duration, duration_unit, warning_msg, prevention_type FROM prevention ORDER BY prevention_id DESC LIMIT 1")

# Get the specific rule if it exists
TARGET_RULE=$(oscar_query "SELECT prevention_id, prevention_name, age_min, duration, duration_unit, warning_msg, prevention_type FROM prevention WHERE prevention_name LIKE 'Senior Weight Monitor%' LIMIT 1")

# If target rule found, use it; otherwise fallback to latest (for partial credit analysis)
if [ -n "$TARGET_RULE" ]; then
    echo "Found target rule: $TARGET_RULE"
    RULE_DATA="$TARGET_RULE"
    FOUND_BY_NAME="true"
else
    echo "Target rule not found by name. checking latest..."
    RULE_DATA="$LATEST_RULE"
    FOUND_BY_NAME="false"
fi

# Parse the tab-separated output
# Expected format: ID \t Name \t Age \t Duration \t Unit \t Msg \t Type
# Note: We'll construct the JSON carefully
RULE_ID=$(echo "$RULE_DATA" | cut -f1)
RULE_NAME=$(echo "$RULE_DATA" | cut -f2)
RULE_AGE=$(echo "$RULE_DATA" | cut -f3)
RULE_DUR=$(echo "$RULE_DATA" | cut -f4)
RULE_UNIT=$(echo "$RULE_DATA" | cut -f5)
RULE_MSG=$(echo "$RULE_DATA" | cut -f6)
RULE_TYPE=$(echo "$RULE_DATA" | cut -f7)

# Get Type Name if possible (prevention_type often joins to 'measurements' or similar, or is a code)
# Let's try to get the associated measurement name if it's an ID
TYPE_NAME=""
if [ -n "$RULE_TYPE" ]; then
    TYPE_NAME=$(oscar_query "SELECT val_desc FROM measurementMap WHERE val_name='$RULE_TYPE' LIMIT 1" 2>/dev/null || echo "$RULE_TYPE")
fi

# Check initial count
INITIAL_COUNT=$(cat /tmp/initial_prevention_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM prevention" || echo "0")

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "found_by_name": $FOUND_BY_NAME,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "rule": {
        "id": "$RULE_ID",
        "name": "$RULE_NAME",
        "age_min": "$RULE_AGE",
        "duration": "$RULE_DUR",
        "unit": "$RULE_UNIT",
        "message": "$RULE_MSG",
        "type_code": "$RULE_TYPE",
        "type_desc": "$TYPE_NAME"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="