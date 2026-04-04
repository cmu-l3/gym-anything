#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting DHCP Forensics Result ==="

# 1. Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check Report File
REPORT_FILE="/home/ga/Documents/captures/dhcp_analysis_report.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
GT_DIR="/var/lib/wireshark_ground_truth"

REPORT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
REPORT_CONTENT=""
REPORT_SIZE="0"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content (base64 encode to safely pass JSON)
    REPORT_CONTENT=$(base64 -w 0 "$REPORT_FILE")
fi

# 3. Read Ground Truth Data
get_gt_content() {
    if [ -f "$GT_DIR/$1" ]; then
        cat "$GT_DIR/$1" | tr '\n' ',' | sed 's/,$//'
    else
        echo ""
    fi
}

GT_TOTAL_PACKETS=$(cat "$GT_DIR/total_packets.txt" 2>/dev/null || echo "0")
GT_TXN_IDS=$(get_gt_content "transaction_ids.txt")
GT_MACS=$(get_gt_content "client_macs.txt")
GT_IPS=$(get_gt_content "assigned_ips.txt")
GT_SERVERS=$(get_gt_content "server_ips.txt")
GT_SUBNETS=$(get_gt_content "subnet_masks.txt")
GT_ROUTERS=$(get_gt_content "routers.txt")
GT_DNS=$(get_gt_content "dns_servers.txt")

# 4. Check Wireshark status
APP_RUNNING=$(pgrep -f "wireshark" > /dev/null && echo "true" || echo "false")

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "report_exists": $REPORT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_size_bytes": $REPORT_SIZE,
    "app_was_running": $APP_RUNNING,
    "report_content_b64": "$REPORT_CONTENT",
    "ground_truth": {
        "total_packets": "$GT_TOTAL_PACKETS",
        "transaction_ids": "$GT_TXN_IDS",
        "client_macs": "$GT_MACS",
        "assigned_ips": "$GT_IPS",
        "server_ips": "$GT_SERVERS",
        "subnets": "$GT_SUBNETS",
        "routers": "$GT_ROUTERS",
        "dns_servers": "$GT_DNS"
    }
}
EOF

# Move to final location
safe_json_write "$(cat $TEMP_JSON)" "/tmp/task_result.json"
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="