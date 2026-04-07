#!/bin/bash
# Export script for openvsp_parametric_resizing
# Captures both the baseline and resized models for verifier comparison

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_parametric_resizing_result.json"
BASELINE_PATH="$MODELS_DIR/conceptual_jet_baseline.vsp3"
RESIZED_PATH="$MODELS_DIR/conceptual_jet_resized.vsp3"

echo "=== Exporting result for openvsp_parametric_resizing ==="

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to release file locks
kill_openvsp

# Extract data using Python and save to JSON
python3 << PYEOF
import json
import os

baseline_path = '$BASELINE_PATH'
resized_path = '$RESIZED_PATH'

result = {
    'baseline_exists': os.path.isfile(baseline_path),
    'resized_exists': os.path.isfile(resized_path),
    'baseline_content': '',
    'resized_content': '',
    'resized_mtime': 0,
    'task_start': 0
}

try:
    with open('/tmp/task_start_timestamp', 'r') as f:
        result['task_start'] = int(f.read().strip())
except Exception:
    pass

if result['baseline_exists']:
    with open(baseline_path, 'r', errors='replace') as f:
        result['baseline_content'] = f.read()

if result['resized_exists']:
    result['resized_mtime'] = int(os.path.getmtime(resized_path))
    with open(resized_path, 'r', errors='replace') as f:
        result['resized_content'] = f.read()

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)

print(f"Export successful. Resized file exists: {result['resized_exists']}")
PYEOF

echo "=== Export complete ==="