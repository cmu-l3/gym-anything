#!/bin/bash
echo "=== Exporting export_series_to_video_presentation result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Extract file details using Python to safely read magic bytes
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

python3 << PYEOF
import json
import os

task_start = int("$TASK_START")
export_dir = "/home/ga/DICOM/exports"
candidates = ["anatomy_scroll.avi", "anatomy_scroll.mp4"]

result = {
    "task_start": task_start,
    "task_end": int("$TASK_END"),
    "output_exists": False,
    "file_created_during_task": False,
    "output_size_bytes": 0,
    "header_hex": "",
    "filename_used": "",
    "app_was_running": False,
    "screenshot_path": "/tmp/task_final.png"
}

# Check if Weasis was running
app_running = os.system("pgrep -f weasis > /dev/null") == 0
result["app_was_running"] = app_running

# Search for the exported file
for filename in candidates:
    filepath = os.path.join(export_dir, filename)
    if os.path.exists(filepath):
        result["output_exists"] = True
        result["filename_used"] = filename
        
        stat = os.stat(filepath)
        result["output_size_bytes"] = stat.st_size
        
        # Check if modified/created after task start (with a 2 sec grace period for fast setup)
        result["file_created_during_task"] = stat.st_mtime >= (task_start - 2)
        
        # Read magic bytes
        try:
            with open(filepath, "rb") as f:
                header = f.read(16)
                result["header_hex"] = header.hex()
        except Exception:
            pass
            
        break

with open("$TEMP_JSON", "w") as f:
    json.dump(result, f, indent=4)
PYEOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="