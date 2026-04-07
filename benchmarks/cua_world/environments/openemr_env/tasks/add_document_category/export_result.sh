#!/bin/bash
# Export script for Add Document Category task
echo "=== Exporting Add Document Category Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

if [ -f /tmp/task_final_state.png ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
else
    SCREENSHOT_EXISTS="false"
    echo "WARNING: Could not capture final screenshot"
fi

# Get initial counts
INITIAL_COUNT=$(cat /tmp/initial_category_count.txt 2>/dev/null || echo "0")
INITIAL_MAX_ID=$(cat /tmp/initial_max_category_id.txt 2>/dev/null || echo "0")

# Get current category count
CURRENT_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM categories" 2>/dev/null || echo "0")

echo "Category count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Query for categories matching "Prior Authorization" (case-insensitive)
echo ""
echo "=== Searching for Prior Authorization category ==="
MATCHING_CATEGORIES=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT id, name, parent FROM categories WHERE LOWER(name) LIKE '%prior%' AND LOWER(name) LIKE '%auth%'" 2>/dev/null)

CATEGORY_FOUND="false"
CATEGORY_ID=""
CATEGORY_NAME=""
CATEGORY_PARENT=""
NEWLY_CREATED="false"

if [ -n "$MATCHING_CATEGORIES" ]; then
    CATEGORY_FOUND="true"
    # Parse the first matching category
    CATEGORY_ID=$(echo "$MATCHING_CATEGORIES" | head -1 | cut -f1)
    CATEGORY_NAME=$(echo "$MATCHING_CATEGORIES" | head -1 | cut -f2)
    CATEGORY_PARENT=$(echo "$MATCHING_CATEGORIES" | head -1 | cut -f3)
    
    echo "Found matching category:"
    echo "  ID: $CATEGORY_ID"
    echo "  Name: $CATEGORY_NAME"
    echo "  Parent: $CATEGORY_PARENT"
    
    # Check if this category was newly created (ID > initial max ID)
    if [ -n "$CATEGORY_ID" ] && [ "$CATEGORY_ID" -gt "$INITIAL_MAX_ID" ]; then
        NEWLY_CREATED="true"
        echo "  Status: NEWLY CREATED during task"
    else
        echo "  Status: May have existed before task"
    fi
else
    echo "No category matching 'Prior Authorization' found"
fi

# Also check for any new categories (by ID)
echo ""
echo "=== Categories created during task (id > $INITIAL_MAX_ID) ==="
NEW_CATEGORIES=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
    "SELECT id, name, parent FROM categories WHERE id > $INITIAL_MAX_ID" 2>/dev/null)
echo "$NEW_CATEGORIES"

# List all categories for debugging
echo ""
echo "=== All categories (current state) ==="
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
    "SELECT id, name, parent FROM categories ORDER BY id" 2>/dev/null | head -30

# Check if category has valid parent (should be > 0 for proper hierarchy)
PARENT_VALID="false"
if [ -n "$CATEGORY_PARENT" ] && [ "$CATEGORY_PARENT" -ge 0 ]; then
    PARENT_VALID="true"
fi

# Escape special characters for JSON
CATEGORY_NAME_ESCAPED=$(echo "$CATEGORY_NAME" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/doc_category_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "initial_category_count": ${INITIAL_COUNT:-0},
    "current_category_count": ${CURRENT_COUNT:-0},
    "initial_max_category_id": ${INITIAL_MAX_ID:-0},
    "category_found": $CATEGORY_FOUND,
    "category": {
        "id": "$CATEGORY_ID",
        "name": "$CATEGORY_NAME_ESCAPED",
        "parent": "$CATEGORY_PARENT"
    },
    "newly_created": $NEWLY_CREATED,
    "parent_valid": $PARENT_VALID,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/add_document_category_result.json 2>/dev/null || sudo rm -f /tmp/add_document_category_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/add_document_category_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/add_document_category_result.json
chmod 666 /tmp/add_document_category_result.json 2>/dev/null || sudo chmod 666 /tmp/add_document_category_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Result JSON ==="
cat /tmp/add_document_category_result.json
echo ""
echo "=== Export Complete ==="