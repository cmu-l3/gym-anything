#!/bin/bash
echo "=== Exporting periodic_table_reference_pippy task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/pippy_task_end.png" 2>/dev/null || true

TASK_START=$(cat /tmp/periodic_pippy_start_ts 2>/dev/null || echo "0")

# Use Python to accurately check files and parse contents
python3 << 'PYEOF' > /tmp/periodic_table_reference_pippy_result.json
import json
import os
import re

result = {
    "script_exists": False,
    "script_size": 0,
    "script_modified": False,
    "has_csv_logic": False,
    "report_exists": False,
    "report_size": 0,
    "report_modified": False,
    "elements_found": [],
    "has_h2o_weight": False,
    "has_co2_weight": False,
    "has_au_num": False,
    "has_fe_mass": False,
    "error": None
}

try:
    task_start = int('${TASK_START}')
    script_path = '/home/ga/Documents/periodic_lookup.py'
    report_path = '/home/ga/Documents/element_report.txt'

    # Check Script
    if os.path.exists(script_path):
        result["script_exists"] = True
        result["script_size"] = os.path.getsize(script_path)
        if os.path.getmtime(script_path) > task_start:
            result["script_modified"] = True
            
        with open(script_path, 'r', errors='ignore') as f:
            content = f.read()
            # Detect basic file I/O or CSV parsing logic
            if 'csv' in content or 'open(' in content or '.split' in content:
                result["has_csv_logic"] = True

    # Check Report
    if os.path.exists(report_path):
        result["report_exists"] = True
        result["report_size"] = os.path.getsize(report_path)
        if os.path.getmtime(report_path) > task_start:
            result["report_modified"] = True

        with open(report_path, 'r', errors='ignore') as f:
            text = f.read().lower()

        # Check for target elements
        target_elements = ['hydrogen', 'oxygen', 'carbon', 'nitrogen', 'iron', 'copper', 'gold', 'silver']
        found_elements = []
        for el in target_elements:
            if el in text:
                found_elements.append(el)
        result["elements_found"] = found_elements

        # Check computed molecular weights
        # Water = 18.015 (accept 18.00 to 18.03)
        if re.search(r'\b18\.0[0-3]\d*\b', text):
            result["has_h2o_weight"] = True
        # CO2 = 44.009 (accept 44.00 to 44.02)
        if re.search(r'\b44\.0[0-2]\d*\b', text):
            result["has_co2_weight"] = True

        # Check data accuracy / extraction validation
        if re.search(r'\b79\b', text):
            result["has_au_num"] = True
        if re.search(r'\b55\.8[45]\d*\b', text):
            result["has_fe_mass"] = True

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/periodic_table_reference_pippy_result.json
echo "Result exported to /tmp/periodic_table_reference_pippy_result.json"
cat /tmp/periodic_table_reference_pippy_result.json
echo "=== Export complete ==="