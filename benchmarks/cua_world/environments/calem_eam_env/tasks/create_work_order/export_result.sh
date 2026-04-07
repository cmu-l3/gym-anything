#!/bin/bash
# Export result script for Create Work Order task (post_task hook)

source /workspace/scripts/task_utils.sh

echo "=== Exporting Create Work Order Results ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get initial count
INITIAL=$(cat /tmp/initial_wo_count 2>/dev/null || echo "0")

# Get current work order count
CURRENT=$(calemeam_query "SELECT COUNT(*) FROM workorder" 2>/dev/null || echo "0")

# Look for the expected work order
WO_DATA=$(calemeam_query "SELECT wo_no, description, priority_id, type_id FROM workorder ORDER BY created_time DESC LIMIT 1" 2>/dev/null || echo "")

# Parse the work order data
WO_NO=$(echo "$WO_DATA" | awk '{print $1}')
WO_DESC=$(echo "$WO_DATA" | cut -f2)
WO_PRIORITY=$(echo "$WO_DATA" | cut -f3)
WO_TYPE=$(echo "$WO_DATA" | cut -f4)

# Write result JSON
TEMP=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP" << EOF
{
  "initial_wo_count": $INITIAL,
  "current_wo_count": $CURRENT,
  "wo_found": $([ -n "$WO_NO" ] && echo "true" || echo "false"),
  "work_order": {
    "wo_no": "$WO_NO",
    "description": "$WO_DESC",
    "priority": "$WO_PRIORITY",
    "type": "$WO_TYPE"
  }
}
EOF

rm -f /tmp/create_wo_result.json 2>/dev/null || sudo rm -f /tmp/create_wo_result.json 2>/dev/null || true
cp "$TEMP" /tmp/create_wo_result.json 2>/dev/null || sudo cp "$TEMP" /tmp/create_wo_result.json
chmod 666 /tmp/create_wo_result.json 2>/dev/null || sudo chmod 666 /tmp/create_wo_result.json 2>/dev/null || true
rm -f "$TEMP"

echo "Result saved to /tmp/create_wo_result.json"
echo "Initial WO count: $INITIAL, Current: $CURRENT"
echo "=== Export Complete ==="
