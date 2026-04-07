#!/bin/bash
set -euo pipefail
echo "=== Exporting activate_mpr_export task results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot for evidence
take_screenshot /tmp/task_final.png

# Record bounds
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Analyze exported PNGs strictly via Python
python3 << PYEOF > /tmp/analyze_exports.log 2>&1
import os
import json
import hashlib
try:
    from PIL import Image, ImageStat
except ImportError:
    pass

exports_dir = "/home/ga/DICOM/exports"
task_start = $TASK_START
task_end = $TASK_END

results = {
    "task_start": task_start,
    "task_end": task_end,
    "coronal": {"exists": False},
    "sagittal": {"exists": False},
    "identical_files": False,
    "app_was_running": False
}

files_to_check = {
    "coronal": os.path.join(exports_dir, "mpr_coronal.png"),
    "sagittal": os.path.join(exports_dir, "mpr_sagittal.png")
}

hashes = []

for key, path in files_to_check.items():
    if os.path.exists(path):
        try:
            mtime = os.path.getmtime(path)
            size = os.path.getsize(path)
            
            with open(path, 'rb') as f:
                file_hash = hashlib.md5(f.read()).hexdigest()
                hashes.append(file_hash)
                
            img = Image.open(path)
            stat = ImageStat.Stat(img)
            stddev = sum(stat.stddev) / len(stat.stddev) if stat.stddev else 0
            
            results[key] = {
                "exists": True,
                "size_bytes": size,
                "created_during_task": mtime >= task_start,
                "width": img.width,
                "height": img.height,
                "stddev": stddev
            }
        except Exception as e:
            results[key] = {"exists": True, "error": str(e)}

if len(hashes) == 2 and hashes[0] == hashes[1]:
    results["identical_files"] = True

# Record Weasis state
app_running = os.system("pgrep -f weasis > /dev/null") == 0
results["app_was_running"] = app_running

with open('/tmp/task_result_final.json', 'w') as f:
    json.dump(results, f, indent=4)
PYEOF

# Move payload
if [ -f /tmp/task_result_final.json ]; then
    rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
    cp /tmp/task_result_final.json /tmp/task_result.json
    chmod 666 /tmp/task_result.json
fi

cat /tmp/task_result.json
echo "=== Export complete ==="