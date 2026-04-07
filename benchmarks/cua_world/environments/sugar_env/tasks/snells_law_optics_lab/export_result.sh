#!/bin/bash
# Do NOT use set -e
echo "=== Exporting snells_law_optics_lab task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/optics_task_end.png" 2>/dev/null || true

SCRIPT_FILE="/home/ga/Documents/calculate_n.py"
REPORT_FILE="/home/ga/Documents/optics_report.odt"
TASK_START=$(cat /tmp/snells_law_start_ts 2>/dev/null || echo "0")

# Run Python analysis on the outputs
python3 << 'PYEOF' > /tmp/optics_analysis.json 2>/dev/null || echo '{"error":"parse_failed"}' > /tmp/optics_analysis.json
import json
import zipfile
import re
import os

result = {
    "script_exists": False,
    "script_size": 0,
    "script_modified": False,
    "has_sin": False,
    "has_csv": False,
    
    "report_exists": False,
    "report_size": 0,
    "report_modified": False,
    "has_1_52": False,
    "has_1_51_or_53": False,
    "has_glass": False,
    
    "error": None
}

task_start = int(open('/tmp/snells_law_start_ts').read().strip()) if os.path.exists('/tmp/snells_law_start_ts') else 0

# Check Script
script_path = "/home/ga/Documents/calculate_n.py"
if os.path.exists(script_path):
    result["script_exists"] = True
    result["script_size"] = os.path.getsize(script_path)
    if os.path.getmtime(script_path) > task_start:
        result["script_modified"] = True
        
    try:
        with open(script_path, 'r', errors='ignore') as f:
            content = f.read()
            # Look for evidence of math functions and file operations
            result["has_sin"] = 'sin(' in content or 'sin ' in content
            result["has_csv"] = 'open(' in content or 'csv' in content or 'read' in content
    except Exception as e:
        result["error"] = f"Script error: {str(e)}"

# Check Report
report_path = "/home/ga/Documents/optics_report.odt"
if os.path.exists(report_path):
    result["report_exists"] = True
    result["report_size"] = os.path.getsize(report_path)
    if os.path.getmtime(report_path) > task_start:
        result["report_modified"] = True
        
    try:
        with zipfile.ZipFile(report_path, 'r') as z:
            with z.open('content.xml') as f:
                content = f.read().decode('utf-8')
                
        # Strip XML tags to get plain text
        plain_text = re.sub(r'<[^>]+>', ' ', content).lower()
        
        # Check for numerical value
        result["has_1_52"] = '1.52' in plain_text
        result["has_1_51_or_53"] = '1.51' in plain_text or '1.53' in plain_text
        
        # Check for material identification
        result["has_glass"] = 'glass' in plain_text
        
    except Exception as e:
        # Might not be a valid zip/ODT file if agent just renamed a .txt
        result["error"] = f"Report error: {str(e)}"

print(json.dumps(result))
PYEOF

chmod 666 /tmp/optics_analysis.json
echo "Result saved to /tmp/optics_analysis.json"
cat /tmp/optics_analysis.json
echo "=== Export complete ==="