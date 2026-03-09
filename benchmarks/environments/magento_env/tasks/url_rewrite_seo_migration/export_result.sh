#!/bin/bash
# Export script for URL Rewrite SEO Migration task

echo "=== Exporting URL Rewrite Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get verification data
INITIAL_COUNT=$(cat /tmp/initial_rewrite_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(magento_query "SELECT COUNT(*) FROM url_rewrite WHERE entity_type='custom'" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Rewrite Counts: Initial=$INITIAL_COUNT, Current=$CURRENT_COUNT"

# 3. Query for each specific expected rewrite
# We query by request_path and extract target_path and redirect_type

# Helper function to get rewrite details
get_rewrite_details() {
    local req_path="$1"
    # Returns: target_path|redirect_type (pipe separated)
    magento_query "SELECT CONCAT(target_path, '|', redirect_type) FROM url_rewrite WHERE entity_type='custom' AND LOWER(request_path)=LOWER('$req_path') LIMIT 1" 2>/dev/null | tail -1
}

# Query 1: summer-sale-electronics
R1_DATA=$(get_rewrite_details "summer-sale-electronics")
R1_TARGET=$(echo "$R1_DATA" | cut -d'|' -f1)
R1_TYPE=$(echo "$R1_DATA" | cut -d'|' -f2)

# Query 2: old-clothing-catalog
R2_DATA=$(get_rewrite_details "old-clothing-catalog")
R2_TARGET=$(echo "$R2_DATA" | cut -d'|' -f1)
R2_TYPE=$(echo "$R2_DATA" | cut -d'|' -f2)

# Query 3: featured-yoga-gear
R3_DATA=$(get_rewrite_details "featured-yoga-gear")
R3_TARGET=$(echo "$R3_DATA" | cut -d'|' -f1)
R3_TYPE=$(echo "$R3_DATA" | cut -d'|' -f2)

# Query 4: flash-deals
R4_DATA=$(get_rewrite_details "flash-deals")
R4_TARGET=$(echo "$R4_DATA" | cut -d'|' -f1)
R4_TYPE=$(echo "$R4_DATA" | cut -d'|' -f2)

# Query 5: legacy/home-decor
R5_DATA=$(get_rewrite_details "legacy/home-decor")
R5_TARGET=$(echo "$R5_DATA" | cut -d'|' -f1)
R5_TYPE=$(echo "$R5_DATA" | cut -d'|' -f2)

# 4. Check if app was running
APP_RUNNING="false"
if pgrep -f firefox > /dev/null; then APP_RUNNING="true"; fi

# 5. Build JSON Result
TEMP_JSON=$(mktemp /tmp/url_rewrite_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "app_running": $APP_RUNNING,
    "rewrites": {
        "summer-sale-electronics": {
            "exists": $([ -n "$R1_DATA" ] && echo "true" || echo "false"),
            "target_path": "${R1_TARGET}",
            "redirect_type": "${R1_TYPE}"
        },
        "old-clothing-catalog": {
            "exists": $([ -n "$R2_DATA" ] && echo "true" || echo "false"),
            "target_path": "${R2_TARGET}",
            "redirect_type": "${R2_TYPE}"
        },
        "featured-yoga-gear": {
            "exists": $([ -n "$R3_DATA" ] && echo "true" || echo "false"),
            "target_path": "${R3_TARGET}",
            "redirect_type": "${R3_TYPE}"
        },
        "flash-deals": {
            "exists": $([ -n "$R4_DATA" ] && echo "true" || echo "false"),
            "target_path": "${R4_TARGET}",
            "redirect_type": "${R4_TYPE}"
        },
        "legacy/home-decor": {
            "exists": $([ -n "$R5_DATA" ] && echo "true" || echo "false"),
            "target_path": "${R5_TARGET}",
            "redirect_type": "${R5_TYPE}"
        }
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json