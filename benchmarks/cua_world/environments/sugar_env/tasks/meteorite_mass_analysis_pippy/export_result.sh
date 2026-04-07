#!/bin/bash
echo "=== Exporting meteorite_mass_analysis_pippy task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/task_final.png" 2>/dev/null || true

# Run a Python script to gather and package results safely
python3 << 'PYEOF'
import json
import os
import re

result = {
    "script_exists": False,
    "script_size": 0,
    "script_modified_during_task": False,
    "script_has_io": False,
    "script_has_sort": False,
    "html_exists": False,
    "html_size": 0,
    "html_modified_during_task": False,
    "html_has_table": False,
    "html_has_tr": False,
    "hoba_present": False,
    "hoba_mass_60000": False,
    "cape_york_present": False,
    "cape_york_mass_58200": False,
    "other_meteorites_found": []
}

try:
    with open("/tmp/task_start_time.txt", "r") as f:
        task_start = int(f.read().strip())
except Exception:
    task_start = 0

# Check Python Script
script_path = "/home/ga/Documents/meteorite_analysis.py"
if os.path.exists(script_path):
    result["script_exists"] = True
    result["script_size"] = os.path.getsize(script_path)
    result["script_modified_during_task"] = os.path.getmtime(script_path) > task_start
    
    try:
        with open(script_path, "r", encoding="utf-8") as f:
            script_content = f.read()
            
        if 'open(' in script_content or 'csv' in script_content:
            result["script_has_io"] = True
        if 'sort' in script_content or 'sorted' in script_content:
            result["script_has_sort"] = True
    except Exception:
        pass

# Check HTML Report
html_path = "/home/ga/Documents/top_meteorites.html"
if os.path.exists(html_path):
    result["html_exists"] = True
    result["html_size"] = os.path.getsize(html_path)
    result["html_modified_during_task"] = os.path.getmtime(html_path) > task_start
    
    try:
        with open(html_path, "r", encoding="utf-8") as f:
            html_content = f.read()
            
        html_lower = html_content.lower()
        
        if '<table' in html_lower:
            result["html_has_table"] = True
        # Check if multiple rows exist (header + 10 rows)
        if html_lower.count('<tr') >= 5:
            result["html_has_tr"] = True
            
        if 'hoba' in html_lower:
            result["hoba_present"] = True
        # Check for 60000 or 60000.0/60000.00
        if re.search(r'\b60000(?:\.0+)?\b', html_content):
            result["hoba_mass_60000"] = True
            
        if 'cape york' in html_lower:
            result["cape_york_present"] = True
        if re.search(r'\b58200(?:\.0+)?\b', html_content):
            result["cape_york_mass_58200"] = True
            
        # Check for other heavy meteorites
        others_to_check = ["campo del cielo", "canyon diablo", "armanty", "gibeon", "chupaderos", "mundrabilla", "sikhote-alin", "bacubirito"]
        found = []
        for meteor in others_to_check:
            if meteor in html_lower:
                found.append(meteor)
        result["other_meteorites_found"] = found
        
    except Exception:
        pass

# Write result to JSON safely
temp_json = "/tmp/meteorite_analysis_result.json"
with open(temp_json, "w") as f:
    json.dump(result, f, indent=2)

PYEOF

chmod 666 /tmp/meteorite_analysis_result.json 2>/dev/null || true

echo "Result saved to /tmp/meteorite_analysis_result.json"
cat /tmp/meteorite_analysis_result.json
echo "=== Export complete ==="