#!/bin/bash
echo "=== Exporting promote_local_layout result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot for VLM
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Refresh token for API query
refresh_nx_token > /dev/null 2>&1 || true

LAYOUT_NAME="Investigation_Board_Alpha"

echo "Querying layout status for '$LAYOUT_NAME'..."

# Fetch the layout details
LAYOUT_JSON=$(get_layout_by_name "$LAYOUT_NAME")

# Extract details using python
# We need to know:
# 1. Does it exist?
# 2. What is the parentId? (Should be null UUID for shared)
# 3. How many items?

PYTHON_SCRIPT=$(cat <<EOF
import sys, json

try:
    data = json.load(sys.stdin)
    if not data:
        print(json.dumps({"exists": False}))
        sys.exit(0)
        
    layout = data
    parent_id = layout.get("parentId", "")
    items = layout.get("items", [])
    
    result = {
        "exists": True,
        "parentId": parent_id,
        "item_count": len(items),
        "id": layout.get("id")
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"exists": False, "error": str(e)}))
EOF
)

LAYOUT_INFO=$(echo "$LAYOUT_JSON" | python3 -c "$PYTHON_SCRIPT")

# Prepare result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "layout_info": $LAYOUT_INFO,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export complete ==="