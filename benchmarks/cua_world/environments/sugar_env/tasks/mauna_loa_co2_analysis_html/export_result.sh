#!/bin/bash
echo "=== Exporting Mauna Loa CO2 Analysis task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Capture final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/co2_task_final.png" 2>/dev/null || true

# Use python to extract file metadata, parse HTML, and scan the Sugar Journal
python3 << 'PYEOF' > /tmp/co2_task_result.json
import json
import os
import re
import subprocess

result = {
    "script_exists": False,
    "script_mtime": 0,
    "script_content": "",
    "html_exists": False,
    "html_mtime": 0,
    "html_text": "",
    "journal_found": False,
    "task_start": 0
}

# 1. Read task start time
try:
    with open("/tmp/co2_task_start_ts", "r") as f:
        result["task_start"] = float(f.read().strip())
except Exception:
    pass

# 2. Check Python script
script_path = "/home/ga/Documents/analyze_co2.py"
if os.path.exists(script_path):
    result["script_exists"] = True
    result["script_mtime"] = os.path.getmtime(script_path)
    try:
        with open(script_path, "r", errors="ignore") as f:
            result["script_content"] = f.read()
    except Exception:
        pass

# 3. Check HTML output
html_path = "/home/ga/Documents/co2_report.html"
if os.path.exists(html_path):
    result["html_exists"] = True
    result["html_mtime"] = os.path.getmtime(html_path)
    try:
        with open(html_path, "r", errors="ignore") as f:
            html = f.read()
            # Strip HTML tags to get plain text for easy regex matching
            text = re.sub(r'<[^>]+>', ' ', html)
            # Normalize whitespace
            text = re.sub(r'\s+', ' ', text).strip()
            result["html_text"] = text.lower()
    except Exception:
        pass

# 4. Check Sugar Journal for "Mauna Loa CO2 Report"
try:
    proc = subprocess.run(
        ["find", "/home/ga/.sugar/default/datastore", "-name", "title"],
        capture_output=True, text=True
    )
    for line in proc.stdout.split('\n'):
        line = line.strip()
        if line:
            try:
                with open(line, "r", errors="ignore") as f:
                    if "Mauna Loa CO2 Report" in f.read():
                        result["journal_found"] = True
                        break
            except Exception:
                pass
except Exception:
    pass

print(json.dumps(result))
PYEOF

chmod 666 /tmp/co2_task_result.json
echo "Result exported to /tmp/co2_task_result.json"
cat /tmp/co2_task_result.json
echo ""
echo "=== Export complete ==="