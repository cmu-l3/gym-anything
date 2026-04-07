#!/bin/bash
echo "=== Exporting identify_event_provenance task result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png
chmod 666 /tmp/task_final.png 2>/dev/null || true

# 2. Use a Python script to safely parse and merge agent output and ground truth
python3 << 'PYEOF'
import json
import os

gt_path = '/tmp/task_ground_truth.json'
agent_path = os.path.expanduser('/home/ga/Documents/magnitude_provenance.json')
start_time_path = '/tmp/task_start_time.txt'

result = {
    'agent_file_exists': False,
    'agent_file_valid_json': False,
    'agent_data': {},
    'ground_truth': {},
    'file_created_during_task': False
}

# Load Ground Truth
try:
    with open(gt_path, 'r') as f:
        result['ground_truth'] = json.load(f)
except Exception as e:
    print(f"Error loading ground truth: {e}")

# Check Agent Output
if os.path.exists(agent_path):
    result['agent_file_exists'] = True
    
    # Check timestamp
    try:
        with open(start_time_path, 'r') as f:
            start_time = float(f.read().strip())
        mtime = os.path.getmtime(agent_path)
        if mtime >= start_time:
            result['file_created_during_task'] = True
    except Exception as e:
        print(f"Error checking timestamps: {e}")

    # Load Agent JSON
    try:
        with open(agent_path, 'r') as f:
            result['agent_data'] = json.load(f)
        result['agent_file_valid_json'] = True
    except Exception as e:
        print(f"Agent file is not valid JSON: {e}")

# Save the combined result
try:
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
    os.chmod('/tmp/task_result.json', 0o666)
    print("Exported results to /tmp/task_result.json")
except Exception as e:
    print(f"Error saving task result: {e}")
PYEOF

echo "=== Export complete ==="