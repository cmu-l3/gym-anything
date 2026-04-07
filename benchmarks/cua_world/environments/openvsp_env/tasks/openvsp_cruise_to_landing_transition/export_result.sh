#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final state..."
take_screenshot /tmp/task_final.png

# Kill OpenVSP to ensure file buffers are flushed
kill_openvsp

OUTPUT_PATH="/home/ga/Documents/OpenVSP/eCRM001_landing.vsp3"

# Extract file info using python to ensure safe JSON encoding
python3 << PYEOF
import json
import os

output_path = '$OUTPUT_PATH'
task_start = $TASK_START
task_end = $TASK_END

result = {
    "task_start": task_start,
    "task_end": task_end,
    "output_exists": False,
    "file_created_during_task": False,
    "output_size_bytes": 0,
    "file_content": ""
}

if os.path.exists(output_path):
    result["output_exists"] = True
    mtime = int(os.path.getmtime(output_path))
    result["file_created_during_task"] = (mtime > task_start)
    result["output_size_bytes"] = os.path.getsize(output_path)
    
    # Read the XML content (OpenVSP models are XML)
    try:
        with open(output_path, 'r', errors='replace') as f:
            result["file_content"] = f.read()
    except Exception as e:
        result["file_content"] = f"Error reading file: {e}"

# Write to temp file safely
import tempfile
import shutil

fd, temp_path = tempfile.mkstemp(suffix='.json', prefix='result_')
with os.fdopen(fd, 'w') as f:
    json.dump(result, f)

# Move to final location
final_dest = '/tmp/task_result.json'
try:
    if os.path.exists(final_dest):
        os.remove(final_dest)
    shutil.move(temp_path, final_dest)
    os.chmod(final_dest, 0o666)
except Exception as e:
    os.system(f"sudo cp {temp_path} {final_dest}")
    os.system(f"sudo chmod 666 {final_dest}")
PYEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json | grep -v "file_content" # Print without dumping the whole XML
echo "=== Export complete ==="