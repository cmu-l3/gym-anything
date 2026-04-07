#!/bin/bash
# Export script for openvsp_parasite_drag_buildup task

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_parasite_drag_result.json"

echo "=== Exporting result for openvsp_parasite_drag_buildup ==="

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Kill OpenVSP to release any file handles
kill_openvsp

python3 << 'PYEOF'
import json, os, glob

exports_dir = '/home/ga/Documents/OpenVSP/exports'
desktop = '/home/ga/Desktop'
models_dir = '/home/ga/Documents/OpenVSP'

csv_path = os.path.join(exports_dir, 'eCRM001_parasite_drag.csv')
report_path = os.path.join(desktop, 'drag_report.txt')

# Helper to read file info
def get_file_info(path):
    exists = os.path.isfile(path)
    if not exists:
        return {"exists": False, "size": 0, "mtime": 0, "content": ""}
    
    size = os.path.getsize(path)
    mtime = int(os.path.getmtime(path))
    try:
        with open(path, 'r', errors='replace') as f:
            content = f.read()
    except Exception:
        content = ""
        
    return {
        "exists": exists,
        "size": size,
        "mtime": mtime,
        # Truncate content to avoid massive JSON if agent exported something huge
        "content": content[:10000]
    }

# Check exact paths first
csv_info = get_file_info(csv_path)
report_info = get_file_info(report_path)

# If CSV is not at exact path, agent might have saved it elsewhere in OpenVSP dir
if not csv_info["exists"]:
    alt_csv_paths = []
    for root, dirs, files in os.walk(models_dir):
        for fname in files:
            if 'drag' in fname.lower() and fname.endswith('.csv'):
                alt_csv_paths.append(os.path.join(root, fname))
    
    if alt_csv_paths:
        alt_csv_paths.sort(key=lambda p: os.path.getmtime(p), reverse=True)
        csv_info = get_file_info(alt_csv_paths[0])
        csv_info["actual_path"] = alt_csv_paths[0]
else:
    csv_info["actual_path"] = csv_path

try:
    with open('/tmp/task_start_timestamp', 'r') as f:
        task_start = int(f.read().strip())
except Exception:
    task_start = 0

result = {
    'task_start_timestamp': task_start,
    'csv': csv_info,
    'report': report_info
}

with open('/tmp/openvsp_parasite_drag_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"CSV: exists={csv_info['exists']}, size={csv_info['size']}")
print(f"Report: exists={report_info['exists']}, size={report_info['size']}")
PYEOF

echo "=== Export complete ==="