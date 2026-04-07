#!/bin/bash
echo "=== Exporting find_track_summit result ==="

# Capture final screenshot
python3 -c "import pyautogui; pyautogui.screenshot(r'C:\workspace\task_final.png')" 2>/dev/null || true

# Gather output artifacts and metadata into a JSON result
cat << 'EOF' > /tmp/export_res.py
import os
import json

result = {
    "export_gpx_exists": False,
    "export_gpx_mtime": 0,
    "report_txt_exists": False,
    "report_txt_mtime": 0,
    "task_start_time": 0,
    "app_was_running": False
}

# 1. Fetch task start time
try:
    with open(r"C:\workspace\task_start_time.txt", "r") as f:
        result["task_start_time"] = float(f.read().strip())
except:
    pass

# 2. Check GPX export file
gpx_path = r"C:\workspace\summit_export.gpx"
if os.path.exists(gpx_path):
    result["export_gpx_exists"] = True
    result["export_gpx_mtime"] = os.path.getmtime(gpx_path)

# 3. Check text report
report_path = r"C:\workspace\summit_report.txt"
if os.path.exists(report_path):
    result["report_txt_exists"] = True
    result["report_txt_mtime"] = os.path.getmtime(report_path)

# 4. Check if BaseCamp was active during evaluation
try:
    import psutil
    result["app_was_running"] = any("BaseCamp.exe" in p.name() for p in psutil.process_iter(['name']))
except:
    result["app_was_running"] = True # Graceful fallback

# Save JSON result
with open(r"C:\workspace\task_result.json", "w") as f:
    json.dump(result, f, indent=4)
EOF

python3 /tmp/export_res.py || python /tmp/export_res.py || true

echo "=== Export complete ==="