#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Extract HTTP Objects results ==="

# 1. basic setup
OUTPUT_DIR="/home/ga/Documents/extracted_objects"
REPORT_FILE="/home/ga/Documents/http_extraction_report.txt"
GT_FILE="/var/lib/wireshark_ground_truth/ground_truth.json"
HOSTS_FILE="/var/lib/wireshark_ground_truth/expected_hosts.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Take final screenshot
take_screenshot /tmp/task_final.png

# 3. Analyze Agent's Output Files
# We will create a JSON object describing the agent's extracted files
# Format: { "filename": { "md5": "...", "timestamp": 123456 }, ... }

TEMP_AGENT_FILES_JSON=$(mktemp)
python3 -c "
import os
import json
import hashlib

output_dir = '$OUTPUT_DIR'
result = {}

if os.path.exists(output_dir):
    for fname in os.listdir(output_dir):
        full_path = os.path.join(output_dir, fname)
        if os.path.isfile(full_path):
            try:
                # Get stats
                mtime = int(os.path.getmtime(full_path))
                size = os.path.getsize(full_path)
                
                # Get hash
                with open(full_path, 'rb') as f:
                    md5 = hashlib.md5(f.read()).hexdigest()
                
                result[fname] = {
                    'md5': md5,
                    'mtime': mtime,
                    'size': size
                }
            except Exception:
                pass

print(json.dumps(result))
" > "$TEMP_AGENT_FILES_JSON"

# 4. Read Agent's Report
REPORT_CONTENT=""
REPORT_EXISTS=false
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS=true
    # Read content, escape for JSON
    REPORT_CONTENT=$(cat "$REPORT_FILE" | python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))')
else
    REPORT_CONTENT="\"\""
fi

# 5. Read Ground Truth Data
GT_JSON_CONTENT=$(cat "$GT_FILE" 2>/dev/null || echo "{}")
EXPECTED_HOSTS=$(cat "$HOSTS_FILE" 2>/dev/null | tr '\n' ',' || echo "")

# 6. Check if Wireshark is running
APP_RUNNING=$(pgrep -f "wireshark" > /dev/null && echo "true" || echo "false")

# 7. Compile Final Result JSON
# We combine everything into one JSON for the verifier
TEMP_RESULT=$(mktemp)
cat > "$TEMP_RESULT" << EOF
{
    "task_start_time": $TASK_START,
    "app_running": $APP_RUNNING,
    "report_exists": $REPORT_EXISTS,
    "report_content": $REPORT_CONTENT,
    "agent_files": $(cat "$TEMP_AGENT_FILES_JSON"),
    "ground_truth_hashes": $GT_JSON_CONTENT,
    "expected_hosts": "$EXPECTED_HOSTS"
}
EOF

# Move to final location safely
safe_json_write "$(cat "$TEMP_RESULT")" "/tmp/task_result.json"

# Cleanup
rm -f "$TEMP_AGENT_FILES_JSON" "$TEMP_RESULT"

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="