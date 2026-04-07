#!/bin/bash
set -e

echo "=== Exporting Web App Breach Investigation Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# ── Gather timing data ───────────────────────────────────────────────────────
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# ── Read report file ─────────────────────────────────────────────────────────
REPORT_PATH="/home/ga/Documents/incident_report.txt"
REPORT_EXISTS="false"
REPORT_MTIME="0"
REPORT_CONTENT_B64=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    # Base64-encode content (safe for JSON embedding, limit to 16KB)
    REPORT_CONTENT_B64=$(head -c 16384 "$REPORT_PATH" | base64 -w 0)
fi

# Check if Wireshark is still running
APP_RUNNING=$(pgrep -f wireshark > /dev/null 2>&1 && echo "true" || echo "false")

# ── Read ground truth ────────────────────────────────────────────────────────
GT_DIR="/var/lib/wireshark_ground_truth"
GT_ATTACKER_IP=$(cat "$GT_DIR/attacker_ip.txt" 2>/dev/null || echo "")
GT_WEBSERVER_IP=$(cat "$GT_DIR/webserver_ip.txt" 2>/dev/null || echo "")
GT_EXFIL_SERVER_IP=$(cat "$GT_DIR/exfil_server_ip.txt" 2>/dev/null || echo "")
GT_FAILED_LOGINS=$(cat "$GT_DIR/failed_logins.txt" 2>/dev/null || echo "0")
GT_VALID_CREDENTIALS=$(cat "$GT_DIR/valid_credentials.txt" 2>/dev/null || echo "")
GT_WEBSHELL_FILENAME=$(cat "$GT_DIR/webshell_filename.txt" 2>/dev/null || echo "")
GT_COMMANDS_EXECUTED=$(cat "$GT_DIR/commands_executed.txt" 2>/dev/null || echo "")
GT_EXFIL_BYTES=$(cat "$GT_DIR/exfil_bytes.txt" 2>/dev/null || echo "0")

# ── Construct result JSON using Python for safe escaping ─────────────────────
python3 -c "
import json, base64, sys

report_b64 = '$REPORT_CONTENT_B64'
report_text = ''
if report_b64:
    try:
        report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore')
    except:
        pass

result = {
    'task_start': int('$TASK_START' or '0'),
    'task_end': int('$TASK_END' or '0'),
    'report_exists': '$REPORT_EXISTS' == 'true',
    'report_mtime': int('$REPORT_MTIME' or '0'),
    'report_content_b64': report_b64,
    'report_content': report_text,
    'app_running': '$APP_RUNNING' == 'true',
    'ground_truth': {
        'attacker_ip': '$GT_ATTACKER_IP',
        'webserver_ip': '$GT_WEBSERVER_IP',
        'exfil_server_ip': '$GT_EXFIL_SERVER_IP',
        'failed_logins': int('$GT_FAILED_LOGINS' or '0'),
        'valid_credentials': '$GT_VALID_CREDENTIALS',
        'webshell_filename': '$GT_WEBSHELL_FILENAME',
        'commands_executed': '$GT_COMMANDS_EXECUTED',
        'exfil_bytes': int('$GT_EXFIL_BYTES' or '0')
    },
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print('Result JSON written successfully')
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="
