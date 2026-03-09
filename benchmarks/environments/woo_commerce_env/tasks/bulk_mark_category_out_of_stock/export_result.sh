#!/bin/bash
# Export script for Bulk Mark Category Out of Stock task

echo "=== Exporting Bulk Mark Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Read saved IDs
TARGET_IDS=$(cat /tmp/target_ids.txt 2>/dev/null)
CONTROL_IDS=$(cat /tmp/control_ids.txt 2>/dev/null)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# --- Verify Target Products (Accessories) ---
echo "Checking Accessories status..."
TARGET_RESULTS="[]"
TARGET_SUCCESS_COUNT=0
TARGET_TOTAL_COUNT=0

if [ -n "$TARGET_IDS" ]; then
    # We need to check each ID. 
    # Query: Get ID and stock_status for these IDs
    # Note: IN clause requires comma separated list, which TARGET_IDS is.
    RAW_TARGETS=$(wc_query "SELECT post_id, meta_value FROM wp_postmeta WHERE meta_key='_stock_status' AND post_id IN ($TARGET_IDS)")
    
    # Process results into JSON array
    # Format: ID \t status
    TARGET_RESULTS="["
    FIRST=true
    while IFS=$'\t' read -r pid status; do
        if [ "$FIRST" = true ]; then FIRST=false; else TARGET_RESULTS="$TARGET_RESULTS,"; fi
        TARGET_RESULTS="$TARGET_RESULTS {\"id\": $pid, \"status\": \"$status\"}"
        
        ((TARGET_TOTAL_COUNT++))
        if [ "$status" == "outofstock" ]; then
            ((TARGET_SUCCESS_COUNT++))
        fi
    done <<< "$RAW_TARGETS"
    TARGET_RESULTS="$TARGET_RESULTS]"
fi

# --- Verify Control Products (Clothing) ---
echo "Checking Clothing status (Collateral Damage Check)..."
CONTROL_RESULTS="[]"
CONTROL_SAFE_COUNT=0
CONTROL_TOTAL_COUNT=0

if [ -n "$CONTROL_IDS" ]; then
    RAW_CONTROLS=$(wc_query "SELECT post_id, meta_value FROM wp_postmeta WHERE meta_key='_stock_status' AND post_id IN ($CONTROL_IDS)")
    
    CONTROL_RESULTS="["
    FIRST=true
    while IFS=$'\t' read -r pid status; do
        if [ "$FIRST" = true ]; then FIRST=false; else CONTROL_RESULTS="$CONTROL_RESULTS,"; fi
        CONTROL_RESULTS="$CONTROL_RESULTS {\"id\": $pid, \"status\": \"$status\"}"
        
        ((CONTROL_TOTAL_COUNT++))
        if [ "$status" == "instock" ]; then
            ((CONTROL_SAFE_COUNT++))
        fi
    done <<< "$RAW_CONTROLS"
    CONTROL_RESULTS="$CONTROL_RESULTS]"
fi

# --- Check Modification Times ---
# We check if *any* product in the target list was modified after start time
# This helps confirm the agent actually did the work
MODIFIED_DURING_TASK="false"
if [ -n "$TARGET_IDS" ]; then
    LAST_MODIFIED=$(wc_query "SELECT MAX(UNIX_TIMESTAMP(post_modified_gmt)) FROM wp_posts WHERE ID IN ($TARGET_IDS)")
    if [ "$LAST_MODIFIED" -gt "$TASK_START" ]; then
        MODIFIED_DURING_TASK="true"
    fi
fi

# Construct JSON result
TEMP_JSON=$(mktemp /tmp/bulk_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_stats": {
        "total": $TARGET_TOTAL_COUNT,
        "success_count": $TARGET_SUCCESS_COUNT,
        "details": $TARGET_RESULTS
    },
    "control_stats": {
        "total": $CONTROL_TOTAL_COUNT,
        "safe_count": $CONTROL_SAFE_COUNT,
        "details": $CONTROL_RESULTS
    },
    "modified_during_task": $MODIFIED_DURING_TASK,
    "task_start_timestamp": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/bulk_mark_result.json

echo ""
cat /tmp/bulk_mark_result.json
echo ""
echo "=== Export Complete ==="