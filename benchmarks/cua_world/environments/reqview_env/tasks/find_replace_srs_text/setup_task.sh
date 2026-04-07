#!/bin/bash
echo "=== Setting up find_replace_srs_text task ==="

source /workspace/scripts/task_utils.sh

# 1. Kill any running ReqView instances
pkill -f "reqview" 2>/dev/null || true
sleep 2

# 2. Setup project
# We use a specific project folder for this task to ensure isolation
PROJECT_PATH=$(setup_task_project "find_replace")
SRS_JSON="$PROJECT_PATH/documents/SRS.json"

echo "Task project path: $PROJECT_PATH"

# 3. Data Integrity Check & Injection
# Ensure there are "sensor" occurrences to replace.
# If the example project changes in the future, this ensures the task remains valid.
python3 << PYEOF
import json
import sys
import random

srs_path = "$SRS_JSON"
target_term = "sensor"

try:
    with open(srs_path, 'r') as f:
        data = json.load(f)

    # Helper to traverse and count
    def count_occurrences(items, term):
        count = 0
        for item in items:
            text = item.get('text', '') or item.get('description', '')
            if term.lower() in text.lower():
                count += 1
            if 'children' in item:
                count += count_occurrences(item['children'], term)
        return count

    initial_count = count_occurrences(data.get('data', []), target_term)
    print(f"Initial '{target_term}' count: {initial_count}")

    # If count is low (< 3), inject some requirements to make the task meaningful
    if initial_count < 3:
        print("Injecting additional requirements with 'sensor'...")
        new_reqs = [
            {
                "id": f"INJ-{i}",
                "text": f"The {target_term} shall operate within -20 to 50 degrees Celsius.",
                "status": "Draft",
                "type": "NFR"
            }
            for i in range(1, 6)
        ]
        # Inject into the first section found
        if data.get('data') and 'children' in data['data'][0]:
             data['data'][0]['children'].extend(new_reqs)
             with open(srs_path, 'w') as f:
                 json.dump(data, f, indent=2)
             print(f"Injected {len(new_reqs)} requirements.")
    
except Exception as e:
    print(f"Error checking/injecting data: {e}", file=sys.stderr)
PYEOF

# 4. Record Initial State (Anti-Gaming)
# We count exact occurrences of "sensor" and "detector" before the agent starts
python3 << PYEOF
import json
import sys

srs_path = "$SRS_JSON"
state = {
    "sensor_count": 0,
    "detector_count": 0
}

try:
    with open(srs_path, 'r') as f:
        data = json.load(f)
    
    def count_terms(items):
        s_count = 0
        d_count = 0
        for item in items:
            text = (item.get('text', '') or item.get('description', '')).lower()
            s_count += text.count("sensor")
            d_count += text.count("detector")
            if 'children' in item:
                sc, dc = count_terms(item['children'])
                s_count += sc
                d_count += dc
        return s_count, d_count

    state["sensor_count"], state["detector_count"] = count_terms(data.get('data', []))
    
    with open("/tmp/initial_state.json", "w") as f:
        json.dump(state, f)
    print("Initial state recorded:", state)

except Exception as e:
    print(f"Error recording state: {e}", file=sys.stderr)
PYEOF

# 5. Launch ReqView
# Note: We do NOT use open_srs_document here because the task requires the agent 
# to open it from the project tree (as per task description actions).
launch_reqview_with_project "$PROJECT_PATH"

# 6. Final UI Setup
dismiss_dialogs
maximize_window

# Record start time for timestamp verification
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== find_replace_srs_text setup complete ==="