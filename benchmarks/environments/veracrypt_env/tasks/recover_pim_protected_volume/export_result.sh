#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting PIM Recovery Results ==="

# Paths
RECOVERED_FILE="/home/ga/Documents/recovered_specs.txt"
PIM_FILE="/home/ga/Documents/found_pim.txt"
TRUTH_FILE="/var/lib/veracrypt_task/truth.json"
EXPECTED_MOUNT_POINT="/home/ga/MountPoints/slot1"

# 1. Check if Volume is Mounted
IS_MOUNTED="false"
MOUNT_SOURCE=""
if mountpoint -q "$EXPECTED_MOUNT_POINT"; then
    IS_MOUNTED="true"
    # Try to identify source, though difficult with device mapper. 
    # Just checking mountpoint existence is usually sufficient if we check content.
fi

# 2. Read Agent's Recovered File
AGENT_SECRET_CONTENT=""
FILE_EXISTS="false"
if [ -f "$RECOVERED_FILE" ]; then
    FILE_EXISTS="true"
    AGENT_SECRET_CONTENT=$(cat "$RECOVERED_FILE")
fi

# 3. Read Agent's PIM Guess
AGENT_PIM_GUESS=""
PIM_FILE_EXISTS="false"
if [ -f "$PIM_FILE" ]; then
    PIM_FILE_EXISTS="true"
    AGENT_PIM_GUESS=$(cat "$PIM_FILE" | tr -cd '0-9')
fi

# 4. Get Ground Truth (Hidden from agent, accessible by root script)
REAL_SECRET=""
REAL_PIM=""
if [ -f "$TRUTH_FILE" ]; then
    REAL_SECRET=$(grep -o '"secret_string": "[^"]*"' "$TRUTH_FILE" | cut -d'"' -f4)
    REAL_PIM=$(grep -o '"pim": [0-9]*' "$TRUTH_FILE" | cut -d' ' -f2)
fi

# 5. Check Scripting Evidence (Did they create a script?)
SCRIPT_FOUND="false"
SCRIPT_PATH=""
for f in /home/ga/*.sh /home/ga/*.py /home/ga/Documents/*.sh /home/ga/Documents/*.py; do
    if [ -f "$f" ]; then
        if grep -q "veracrypt" "$f" && grep -q "pim" "$f"; then
            SCRIPT_FOUND="true"
            SCRIPT_PATH="$f"
            break
        fi
    fi
done

# 6. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 7. Create Result JSON
# Using python for safe JSON escaping
python3 -c "
import json
import os

result = {
    'is_mounted': '$IS_MOUNTED' == 'true',
    'file_exists': '$FILE_EXISTS' == 'true',
    'pim_file_exists': '$PIM_FILE_EXISTS' == 'true',
    'agent_secret_content': '''$AGENT_SECRET_CONTENT''',
    'agent_pim_guess': '$AGENT_PIM_GUESS',
    'real_secret': '''$REAL_SECRET''',
    'real_pim': '$REAL_PIM',
    'script_found': '$SCRIPT_FOUND' == 'true',
    'script_path': '$SCRIPT_PATH',
    'timestamp': '$(date -Iseconds)'
}

with open('/tmp/pim_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Move to standard location
mv /tmp/pim_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="