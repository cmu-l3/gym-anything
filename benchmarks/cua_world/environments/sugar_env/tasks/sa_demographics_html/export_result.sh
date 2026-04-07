#!/bin/bash
echo "=== Exporting sa_demographics_html task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/task_final.png" 2>/dev/null || true

# Extract timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Run a Python script to parse files and evaluate exact contents
cat > /tmp/parse_outputs.py << EOF
import json
import os
import re

result = {
    "task_start": int($TASK_START),
    "py_exists": False,
    "py_size": 0,
    "py_created_during_task": False,
    "html_exists": False,
    "html_size": 0,
    "html_created_during_task": False,
    "has_table": False,
    "has_tr": False,
    "ecuador_idx": -1,
    "brazil_idx": -1,
    "guyana_idx": -1,
    "all_countries_present": False,
    "has_ecuador_density": False,
    "has_overall_pop": False,
    "has_overall_density": False
}

py_path = "/home/ga/Documents/demographics.py"
html_path = "/home/ga/Documents/density_report.html"

if os.path.exists(py_path):
    result["py_exists"] = True
    result["py_size"] = os.path.getsize(py_path)
    if os.path.getmtime(py_path) > result["task_start"]:
        result["py_created_during_task"] = True

if os.path.exists(html_path):
    result["html_exists"] = True
    result["html_size"] = os.path.getsize(html_path)
    if os.path.getmtime(html_path) > result["task_start"]:
        result["html_created_during_task"] = True

    try:
        with open(html_path, "r", encoding="utf-8", errors="ignore") as f:
            html_content = f.read().lower()

        # Structural checks
        result["has_table"] = "<table" in html_content
        result["has_tr"] = "<tr" in html_content

        # Content checks
        countries = [
            "argentina", "bolivia", "brazil", "chile", 
            "colombia", "ecuador", "guyana", "paraguay", 
            "peru", "suriname", "uruguay", "venezuela"
        ]
        result["all_countries_present"] = all(c in html_content for c in countries)

        # Sorting validation indices
        result["ecuador_idx"] = html_content.find("ecuador")
        result["brazil_idx"] = html_content.find("brazil")
        result["guyana_idx"] = html_content.find("guyana")

        # Mathematical accuracy checks (Regex allows slight variance in rounding)
        # Ecuador Density = 18190484 / 283561 ≈ 64.15
        result["has_ecuador_density"] = bool(re.search(r'64\.1[0-9]', html_content))
        
        # Overall Pop = 439,403,063
        result["has_overall_pop"] = bool(re.search(r'439,?403,?063', html_content))
        
        # Overall Density = 439403063 / 17735184 ≈ 24.77
        result["has_overall_density"] = bool(re.search(r'24\.7[0-9]', html_content))
        
    except Exception as e:
        pass

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
EOF

python3 /tmp/parse_outputs.py

chmod 666 /tmp/task_result.json
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="