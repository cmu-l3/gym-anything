#!/bin/bash
echo "=== Exporting water_cycle_html_browse task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Capture final state screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/water_cycle_end.png" 2>/dev/null || true

# Execute a Python script to robustly parse the created files and check process/log state
python3 << 'PYEOF'
import json
import os
import re
import subprocess
import time

try:
    with open('/tmp/water_cycle_start_ts', 'r') as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

html_file = "/home/ga/Documents/water_cycle.html"
summary_file = "/home/ga/Documents/water_cycle_summary.txt"

res = {
    "html_exists": False,
    "html_size": 0,
    "html_modified": False,
    "has_html_tags": False,
    "has_table": False,
    "html_stages": [],
    "has_temp_50": False,
    "has_temp_minus40": False,
    "has_all_temps": False,
    "summary_exists": False,
    "summary_size": 0,
    "summary_modified": False,
    "summary_stages": [],
    "summary_has_total": False,
    "browse_evidence": False,
    "error": None
}

# 1. Parse HTML File
if os.path.exists(html_file):
    res["html_exists"] = True
    res["html_size"] = os.path.getsize(html_file)
    if os.path.getmtime(html_file) > task_start:
        res["html_modified"] = True

    try:
        with open(html_file, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read().lower()

        res["has_html_tags"] = '<html' in content and '<body' in content
        res["has_table"] = '<table' in content

        stages = ["evaporation", "condensation", "precipitation", "collection"]
        res["html_stages"] = [s for s in stages if s in content]

        res["has_temp_50"] = bool(re.search(r'\b50\b', content))
        res["has_temp_minus40"] = '-40' in content

        temps = ['50', '100', '0', '30', '-40', '15', '25']
        res["has_all_temps"] = all(t in content for t in temps)
    except Exception as e:
        res["error"] = str(e)

# 2. Parse Summary Text File
if os.path.exists(summary_file):
    res["summary_exists"] = True
    res["summary_size"] = os.path.getsize(summary_file)
    if os.path.getmtime(summary_file) > task_start:
        res["summary_modified"] = True

    try:
        with open(summary_file, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read().lower()

        stages = ["evaporation", "condensation", "precipitation", "collection"]
        res["summary_stages"] = [s for s in stages if s in content]

        res["summary_has_total"] = bool(re.search(r'total stages\s*:\s*4', content))
    except Exception as e:
        if not res["error"]:
            res["error"] = str(e)

# 3. Check for Browse Activity Evidence
# Method A: Check if it's currently running
try:
    pgrep = subprocess.run(['pgrep', '-f', 'sugar-activity-web|Browse'], capture_output=True, text=True)
    if pgrep.returncode == 0 and pgrep.stdout.strip():
        res["browse_evidence"] = True
except:
    pass

# Method B: Check Sugar logs for Browse launch during the task window
log_dir = "/home/ga/.sugar/default/logs"
if not res["browse_evidence"] and os.path.exists(log_dir):
    try:
        for f in os.listdir(log_dir):
            if 'WebActivity' in f or 'Browse' in f:
                log_path = os.path.join(log_dir, f)
                if os.path.getmtime(log_path) > task_start:
                    res["browse_evidence"] = True
                    break
    except:
        pass

# Output to JSON
with open('/tmp/water_cycle_result.json', 'w') as f:
    json.dump(res, f)

PYEOF

chmod 666 /tmp/water_cycle_result.json 2>/dev/null || true
echo "Result saved to /tmp/water_cycle_result.json"
cat /tmp/water_cycle_result.json
echo ""
echo "=== Export complete ==="