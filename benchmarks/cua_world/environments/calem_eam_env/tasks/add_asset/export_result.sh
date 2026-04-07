#!/bin/bash
# Export result script for Add Asset task (post_task hook)

source /workspace/scripts/task_utils.sh

echo "=== Exporting Add Asset Results ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get initial count
INITIAL=$(cat /tmp/initial_asset_count 2>/dev/null || echo "0")

# Get current asset count
CURRENT=$(calemeam_query "SELECT COUNT(*) FROM asset" 2>/dev/null || echo "0")

# Look for the expected asset
ASSET_DATA=$(calemeam_query "SELECT asset_no, description, category_id, status_id, location_id FROM asset ORDER BY created_time DESC LIMIT 1" 2>/dev/null || echo "")

# Parse asset data
ASSET_NO=$(echo "$ASSET_DATA" | awk '{print $1}')
ASSET_DESC=$(echo "$ASSET_DATA" | cut -f2)
ASSET_CATEGORY=$(echo "$ASSET_DATA" | cut -f3)
ASSET_STATUS=$(echo "$ASSET_DATA" | cut -f4)
ASSET_LOCATION=$(echo "$ASSET_DATA" | cut -f5)

# Write result JSON
TEMP=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP" << EOF
{
  "initial_asset_count": $INITIAL,
  "current_asset_count": $CURRENT,
  "asset_found": $([ -n "$ASSET_NO" ] && echo "true" || echo "false"),
  "asset": {
    "asset_no": "$ASSET_NO",
    "description": "$ASSET_DESC",
    "category": "$ASSET_CATEGORY",
    "status": "$ASSET_STATUS",
    "location": "$ASSET_LOCATION"
  }
}
EOF

rm -f /tmp/add_asset_result.json 2>/dev/null || sudo rm -f /tmp/add_asset_result.json 2>/dev/null || true
cp "$TEMP" /tmp/add_asset_result.json 2>/dev/null || sudo cp "$TEMP" /tmp/add_asset_result.json
chmod 666 /tmp/add_asset_result.json 2>/dev/null || sudo chmod 666 /tmp/add_asset_result.json 2>/dev/null || true
rm -f "$TEMP"

echo "Result saved to /tmp/add_asset_result.json"
echo "Initial asset count: $INITIAL, Current: $CURRENT"
echo "=== Export Complete ==="
