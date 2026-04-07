#!/bin/bash
# Export script for Create Appointment Category task

echo "=== Exporting Create Appointment Category Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    echo "Final screenshot captured"
else
    echo "WARNING: Could not capture final screenshot"
fi

# Get baseline data
BASELINE_MAX_ID=$(cat /tmp/baseline_category_id.txt 2>/dev/null || echo "0")
BASELINE_COUNT=$(cat /tmp/baseline_category_count.txt 2>/dev/null || echo "0")

echo "Baseline - Max ID: $BASELINE_MAX_ID, Count: $BASELINE_COUNT"

# Get current category count
CURRENT_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM openemr_postcalendar_categories" 2>/dev/null || echo "0")
echo "Current category count: $CURRENT_COUNT"

# Check if new categories were added
NEW_CATEGORIES_ADDED=$((CURRENT_COUNT - BASELINE_COUNT))
echo "New categories added: $NEW_CATEGORIES_ADDED"

# Query for Telehealth category (case-insensitive)
echo ""
echo "=== Searching for Telehealth category ==="
TELEHEALTH_QUERY=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT pc_catid, pc_catname, pc_duration, pc_catcolor, pc_catdesc, pc_active 
     FROM openemr_postcalendar_categories 
     WHERE LOWER(pc_catname) LIKE '%telehealth%' 
        OR LOWER(pc_catname) LIKE '%video%' 
        OR LOWER(pc_catname) LIKE '%tele%health%'
     ORDER BY pc_catid DESC LIMIT 1" 2>/dev/null)

echo "Query result: $TELEHEALTH_QUERY"

# Parse the result
CATEGORY_FOUND="false"
CAT_ID=""
CAT_NAME=""
CAT_DURATION=""
CAT_COLOR=""
CAT_DESC=""
CAT_ACTIVE=""

if [ -n "$TELEHEALTH_QUERY" ]; then
    CATEGORY_FOUND="true"
    CAT_ID=$(echo "$TELEHEALTH_QUERY" | cut -f1)
    CAT_NAME=$(echo "$TELEHEALTH_QUERY" | cut -f2)
    CAT_DURATION=$(echo "$TELEHEALTH_QUERY" | cut -f3)
    CAT_COLOR=$(echo "$TELEHEALTH_QUERY" | cut -f4)
    CAT_DESC=$(echo "$TELEHEALTH_QUERY" | cut -f5)
    CAT_ACTIVE=$(echo "$TELEHEALTH_QUERY" | cut -f6)
    
    echo ""
    echo "Category found:"
    echo "  ID: $CAT_ID"
    echo "  Name: $CAT_NAME"
    echo "  Duration: $CAT_DURATION seconds"
    echo "  Color: $CAT_COLOR"
    echo "  Description: $CAT_DESC"
    echo "  Active: $CAT_ACTIVE"
else
    echo "No Telehealth category found"
    
    # Show newest categories to help debug
    echo ""
    echo "=== Most recent categories (for debugging) ==="
    docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
        "SELECT pc_catid, pc_catname, pc_duration FROM openemr_postcalendar_categories ORDER BY pc_catid DESC LIMIT 5" 2>/dev/null || true
fi

# Check if category was newly created (ID > baseline)
NEWLY_CREATED="false"
if [ -n "$CAT_ID" ] && [ "$CAT_ID" -gt "$BASELINE_MAX_ID" ]; then
    NEWLY_CREATED="true"
    echo "Category was newly created (ID $CAT_ID > baseline $BASELINE_MAX_ID)"
else
    echo "Category may have existed before task or not found"
fi

# Calculate duration in minutes (stored in seconds in DB)
DURATION_MINUTES=""
if [ -n "$CAT_DURATION" ] && [ "$CAT_DURATION" -gt 0 ]; then
    DURATION_MINUTES=$((CAT_DURATION / 60))
    echo "Duration in minutes: $DURATION_MINUTES"
fi

# Check if name contains "telehealth" (case-insensitive)
NAME_VALID="false"
if echo "$CAT_NAME" | grep -qi "telehealth"; then
    NAME_VALID="true"
fi

# Check if duration is approximately 20 minutes (15-25 min = 900-1500 sec)
DURATION_VALID="false"
if [ -n "$CAT_DURATION" ] && [ "$CAT_DURATION" -ge 900 ] && [ "$CAT_DURATION" -le 1500 ]; then
    DURATION_VALID="true"
fi

# Check if color is set (non-empty)
COLOR_VALID="false"
if [ -n "$CAT_COLOR" ] && [ "$CAT_COLOR" != "NULL" ] && [ "$CAT_COLOR" != "" ]; then
    COLOR_VALID="true"
fi

# Check if description is set
DESC_VALID="false"
if [ -n "$CAT_DESC" ] && [ "$CAT_DESC" != "NULL" ] && [ "$CAT_DESC" != "" ]; then
    DESC_VALID="true"
fi

# Check if category is active
ACTIVE_VALID="false"
if [ "$CAT_ACTIVE" = "1" ] || [ -z "$CAT_ACTIVE" ]; then
    # Default is usually active
    ACTIVE_VALID="true"
fi

# Escape special characters for JSON
CAT_NAME_ESCAPED=$(echo "$CAT_NAME" | sed 's/"/\\"/g' | tr -d '\n\r')
CAT_DESC_ESCAPED=$(echo "$CAT_DESC" | sed 's/"/\\"/g' | tr -d '\n\r')
CAT_COLOR_ESCAPED=$(echo "$CAT_COLOR" | sed 's/"/\\"/g' | tr -d '\n\r')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/category_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "baseline_max_id": $BASELINE_MAX_ID,
    "baseline_count": $BASELINE_COUNT,
    "current_count": $CURRENT_COUNT,
    "new_categories_added": $NEW_CATEGORIES_ADDED,
    "category_found": $CATEGORY_FOUND,
    "category": {
        "id": "${CAT_ID:-}",
        "name": "${CAT_NAME_ESCAPED:-}",
        "duration_seconds": ${CAT_DURATION:-0},
        "duration_minutes": ${DURATION_MINUTES:-0},
        "color": "${CAT_COLOR_ESCAPED:-}",
        "description": "${CAT_DESC_ESCAPED:-}",
        "active": "${CAT_ACTIVE:-1}"
    },
    "validation": {
        "newly_created": $NEWLY_CREATED,
        "name_contains_telehealth": $NAME_VALID,
        "duration_in_range": $DURATION_VALID,
        "color_assigned": $COLOR_VALID,
        "description_present": $DESC_VALID,
        "category_active": $ACTIVE_VALID
    },
    "screenshot_final": "/tmp/task_final.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result JSON
rm -f /tmp/create_category_result.json 2>/dev/null || sudo rm -f /tmp/create_category_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/create_category_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/create_category_result.json
chmod 666 /tmp/create_category_result.json 2>/dev/null || sudo chmod 666 /tmp/create_category_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/create_category_result.json"
cat /tmp/create_category_result.json
echo ""
echo "=== Export Complete ==="