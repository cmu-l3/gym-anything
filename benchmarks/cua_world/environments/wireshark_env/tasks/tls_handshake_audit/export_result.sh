#!/bin/bash
set -e
echo "=== Exporting TLS Audit Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
GROUND_TRUTH_DIR="/var/lib/wireshark_ground_truth"

# Report file details
REPORT_PATH="/home/ga/Documents/tls_audit_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_MTIME="0"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH")
    # Read content safely (limit size to prevent massive JSON)
    REPORT_CONTENT=$(head -c 4096 "$REPORT_PATH" | base64 -w 0)
fi

# Check if Wireshark is running
APP_RUNNING=$(pgrep -f wireshark > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Gather Ground Truth for verification
GT_CLIENT_HELLOS=$(cat "$GROUND_TRUTH_DIR/client_hello_count.txt" 2>/dev/null || echo "0")
GT_SERVER_HELLOS=$(cat "$GROUND_TRUTH_DIR/server_hello_count.txt" 2>/dev/null || echo "0")
GT_SNIS=$(cat "$GROUND_TRUTH_DIR/sni_list.txt" 2>/dev/null | base64 -w 0)
GT_VERSIONS=$(cat "$GROUND_TRUTH_DIR/tls_versions.txt" 2>/dev/null | base64 -w 0)
GT_CIPHERS=$(cat "$GROUND_TRUTH_DIR/cipher_suites.txt" 2>/dev/null | base64 -w 0)
GT_WEAK=$(cat "$GROUND_TRUTH_DIR/weak_tls.txt" 2>/dev/null || echo "No")

# Construct JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_mtime": $REPORT_MTIME,
    "report_content_b64": "$REPORT_CONTENT",
    "app_running": $APP_RUNNING,
    "ground_truth": {
        "client_hellos": $GT_CLIENT_HELLOS,
        "server_hellos": $GT_SERVER_HELLOS,
        "snis_b64": "$GT_SNIS",
        "versions_b64": "$GT_VERSIONS",
        "ciphers_b64": "$GT_CIPHERS",
        "weak_tls": "$GT_WEAK"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"