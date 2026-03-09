#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting categorize_tickets result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Retrieve Ground Truth IDs
GT_ACME_1=$(cat /tmp/gt_acme_id_1 2>/dev/null || echo "0")
GT_ACME_2=$(cat /tmp/gt_acme_id_2 2>/dev/null || echo "0")
GT_URGENT=$(cat /tmp/gt_urgent_id 2>/dev/null || echo "0")

# 3. Query Tags
# Find 'Acme VIP' tag ID (case-insensitive)
TAG_ACME_ID=$(fs_query "SELECT id FROM tags WHERE LOWER(name) = 'acme vip' LIMIT 1" 2>/dev/null)
# Find 'Urgent' tag ID (case-insensitive)
TAG_URGENT_ID=$(fs_query "SELECT id FROM tags WHERE LOWER(name) = 'urgent' LIMIT 1" 2>/dev/null)

# 4. Check Tag Assignments
# Get all conversation IDs tagged with Acme VIP
TAGGED_ACME_CONVS="[]"
if [ -n "$TAG_ACME_ID" ]; then
    IDS=$(fs_query "SELECT conversation_id FROM conversation_tag WHERE tag_id = $TAG_ACME_ID" 2>/dev/null)
    # Convert newline separated IDs to JSON array
    if [ -n "$IDS" ]; then
        TAGGED_ACME_CONVS=$(echo "$IDS" | jq -R -s -c 'split("\n")[:-1] | map(tonumber)')
    fi
fi

# Get all conversation IDs tagged with Urgent
TAGGED_URGENT_CONVS="[]"
if [ -n "$TAG_URGENT_ID" ]; then
    IDS=$(fs_query "SELECT conversation_id FROM conversation_tag WHERE tag_id = $TAG_URGENT_ID" 2>/dev/null)
    if [ -n "$IDS" ]; then
        TAGGED_URGENT_CONVS=$(echo "$IDS" | jq -R -s -c 'split("\n")[:-1] | map(tonumber)')
    fi
fi

# 5. Prepare Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "tags": {
        "acme_vip_id": "${TAG_ACME_ID}",
        "urgent_id": "${TAG_URGENT_ID}"
    },
    "ground_truth": {
        "acme_ids": [${GT_ACME_1}, ${GT_ACME_2}],
        "urgent_id": ${GT_URGENT}
    },
    "actual_state": {
        "tagged_acme_ids": ${TAGGED_ACME_CONVS},
        "tagged_urgent_ids": ${TAGGED_URGENT_CONVS}
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location
safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="