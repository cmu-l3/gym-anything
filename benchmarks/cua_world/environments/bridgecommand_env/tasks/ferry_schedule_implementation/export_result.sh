#!/bin/bash
echo "=== Exporting Ferry Schedule Results ==="

BC_DATA="/opt/bridgecommand"
SCENARIO_NAME="f) Southampton Ferry Schedule"
SCENARIO_DIR="$BC_DATA/Scenarios/$SCENARIO_NAME"
RESULT_FILE="/tmp/task_result.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if Scenario Directory Exists
if [ -d "$SCENARIO_DIR" ]; then
    SCENARIO_EXISTS="true"
else
    SCENARIO_EXISTS="false"
fi

# 2. Capture File Contents (if they exist)
# We use python to safely JSON-encode the file contents to avoid shell escaping hell
python3 -c "
import json
import os

scenario_dir = '$SCENARIO_DIR'
result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'scenario_exists': False,
    'files': {}
}

if os.path.exists(scenario_dir):
    result['scenario_exists'] = True
    for filename in ['environment.ini', 'ownship.ini', 'othership.ini']:
        filepath = os.path.join(scenario_dir, filename)
        if os.path.exists(filepath):
            try:
                with open(filepath, 'r') as f:
                    result['files'][filename] = f.read()
            except Exception as e:
                result['files'][filename] = f'ERROR: {str(e)}'
        else:
            result['files'][filename] = None

# 3. Check timestamps (Anti-gaming)
# Check if othership.ini was modified AFTER task start
othership_path = os.path.join(scenario_dir, 'othership.ini')
if os.path.exists(othership_path):
    mtime = os.path.getmtime(othership_path)
    result['othership_created_during_task'] = (mtime > $TASK_START)
else:
    result['othership_created_during_task'] = False

# Save to JSON
with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f, indent=2)
"

# 4. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

echo "Result exported to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="