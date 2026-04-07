#!/bin/bash
# Export script for Create Campaign Annotations task

echo "=== Exporting Create Campaign Annotations Result ==="
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# 2. Get Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Get Initial Count
INITIAL_COUNT=$(cat /tmp/initial_annotation_count 2>/dev/null || echo "0")

# 4. Query Current Annotations for Site 1
# We select all annotations for Site 1 to verify against the expected list
echo "Querying annotations..."
ANNOTATIONS_JSON=$(docker exec matomo-db mysql -u matomo -pmatomo123 matomo -N -e "
    SELECT JSON_OBJECT(
        'id', idannotation,
        'date', date,
        'note', note,
        'starred', starred,
        'login', login
    )
    FROM matomo_annotation
    WHERE idsite=1
    ORDER BY date ASC;
" 2>/dev/null | jq -s '.' || echo "[]")

CURRENT_COUNT=$(echo "$ANNOTATIONS_JSON" | jq 'length')

echo "Annotations found: $CURRENT_COUNT (Initial: $INITIAL_COUNT)"

# 5. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/annotations_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "annotations": $ANNOTATIONS_JSON,
    "screenshot_path": "/tmp/task_final_screenshot.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# 6. Save and Permissions
rm -f /tmp/create_campaign_annotations_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/create_campaign_annotations_result.json
chmod 666 /tmp/create_campaign_annotations_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/create_campaign_annotations_result.json"
cat /tmp/create_campaign_annotations_result.json
echo "=== Export Complete ==="