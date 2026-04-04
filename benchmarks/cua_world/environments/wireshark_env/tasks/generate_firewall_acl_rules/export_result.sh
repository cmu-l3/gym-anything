#!/bin/bash
echo "=== Exporting Firewall ACL Rules Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
GROUND_TRUTH_IP=$(cat /tmp/ground_truth_ip.txt 2>/dev/null || echo "")

# Define expected paths
CISCO_PATH="/home/ga/Documents/cisco_block_rule.txt"
IPTABLES_PATH="/home/ga/Documents/iptables_block_rule.txt"

# --- Function to check file status ---
check_file() {
    local fpath="$1"
    local exists="false"
    local created_during="false"
    local content=""
    
    if [ -f "$fpath" ]; then
        exists="true"
        # Read content (limit size to prevent issues)
        content=$(head -n 5 "$fpath")
        
        # Check timestamp
        local mtime=$(stat -c %Y "$fpath" 2>/dev/null || echo "0")
        if [ "$mtime" -ge "$TASK_START" ]; then
            created_during="true"
        fi
    fi
    
    # Return JSON-fragment compatible string (using python for safe escaping)
    python3 -c "import json, sys; print(json.dumps({'exists': sys.argv[1] == 'true', 'created_during_task': sys.argv[2] == 'true', 'content': sys.argv[3]}))" "$exists" "$created_during" "$content"
}

# Check both files
CISCO_RESULT=$(check_file "$CISCO_PATH")
IPTABLES_RESULT=$(check_file "$IPTABLES_PATH")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Construct final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
import sys

data = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'ground_truth_ip': '$GROUND_TRUTH_IP',
    'cisco_file': $CISCO_RESULT,
    'iptables_file': $IPTABLES_RESULT,
    'screenshot_path': '/tmp/task_final.png'
}

with open('$TEMP_JSON', 'w') as f:
    json.dump(data, f, indent=2)
"

# Save to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="