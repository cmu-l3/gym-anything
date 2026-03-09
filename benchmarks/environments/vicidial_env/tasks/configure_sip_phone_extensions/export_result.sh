#!/bin/bash
set -e
echo "=== Exporting configure_sip_phone_extensions results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get Task Start Info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_phone_count.txt 2>/dev/null || echo "0")

# 1. Get Actual Server IP (Ground Truth)
SERVER_IP=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
    "SELECT server_ip FROM servers LIMIT 1;" 2>/dev/null | tr -d '[:space:]' || echo "unknown")

# 2. Get Current Phone Count
FINAL_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
    "SELECT COUNT(*) FROM phones;" 2>/dev/null | tr -d '[:space:]' || echo "0")

# 3. Helper to dump a phone record to JSON object
# We select specific fields we care about
dump_phone_json() {
    local ext="$1"
    # Query MySQL for specific columns and format as simple JSON
    # Note: Using python to safely format JSON to avoid shell escaping issues
    docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
        "SELECT extension, dialplan_number, voicemail_id, login, pass, server_ip, protocol, local_gmt, phone_type, fullname, active FROM phones WHERE extension='${ext}' LIMIT 1;" 2>/dev/null | \
        python3 -c "
import sys, json
try:
    line = sys.stdin.read().strip()
    if not line:
        print('null')
    else:
        parts = line.split('\t')
        # Map fields based on query order
        data = {
            'extension': parts[0],
            'dialplan_number': parts[1],
            'voicemail_id': parts[2],
            'login': parts[3],
            'pass': parts[4],
            'server_ip': parts[5],
            'protocol': parts[6],
            'local_gmt': parts[7],
            'phone_type': parts[8],
            'fullname': parts[9],
            'active': parts[10]
        }
        print(json.dumps(data))
except Exception:
    print('null')
"
}

# Get phone data
PHONE_8501_JSON=$(dump_phone_json "8501")
PHONE_8502_JSON=$(dump_phone_json "8502")

# Construct Final JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "initial_phone_count": $INITIAL_COUNT,
    "final_phone_count": $FINAL_COUNT,
    "actual_server_ip": "$SERVER_IP",
    "phone_8501": $PHONE_8501_JSON,
    "phone_8502": $PHONE_8502_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json