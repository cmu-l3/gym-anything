#!/bin/bash
echo "=== Exporting hurricane_fiona_buoy_analysis task results ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
su - ga -c "$SUGAR_ENV scrot /tmp/task_final.png" 2>/dev/null || true

# Run Python script to evaluate agent results against dynamic ground truth
python3 << 'PYEOF' > /tmp/hurricane_fiona_result.json
import json
import re
import os

result = {
    "task_start": 0,
    "script_exists": False,
    "script_size": 0,
    "report_exists": False,
    "report_size": 0,
    "format_correct": False,
    "gt_max_wvht": None,
    "gt_min_pres": None,
    "agent_max_wvht": None,
    "agent_min_pres": None,
    "error": None
}

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        result["task_start"] = int(f.read().strip() or "0")
except:
    pass
    
# Check for agent script (accepts python or bash)
script_path = None
if os.path.exists('/home/ga/Documents/analyze_hurricane.py'):
    script_path = '/home/ga/Documents/analyze_hurricane.py'
elif os.path.exists('/home/ga/Documents/analyze_hurricane.sh'):
    script_path = '/home/ga/Documents/analyze_hurricane.sh'
    
if script_path:
    result["script_exists"] = True
    result["script_size"] = os.path.getsize(script_path)

# Calculate ground truth dynamically from the exact file the agent parsed
gt_max_wvht = -1.0
gt_min_pres = 99999.0

try:
    with open('/home/ga/Documents/buoy_41046_2022.txt', 'r') as f:
        for line in f:
            if line.startswith('#'): continue
            parts = line.split()
            # Ensure row has enough columns
            if len(parts) > 12:
                mm = parts[1]
                if mm == '09' or mm == '9':
                    try:
                        wvht = float(parts[8])
                        pres = float(parts[12])
                        
                        if wvht != 99.00 and wvht > gt_max_wvht:
                            gt_max_wvht = wvht
                        if pres != 9999.0 and pres < gt_min_pres:
                            gt_min_pres = pres
                    except ValueError:
                        pass
                        
    if gt_max_wvht > -1.0: result["gt_max_wvht"] = gt_max_wvht
    if gt_min_pres < 99999.0: result["gt_min_pres"] = gt_min_pres
except Exception as e:
    result["error"] = f"GT Calculation Error: {str(e)}"

# Check agent report content
report_path = '/home/ga/Documents/hurricane_summary.txt'
if os.path.exists(report_path):
    result["report_exists"] = True
    result["report_size"] = os.path.getsize(report_path)
    
    try:
        with open(report_path, 'r') as f:
            content = f.read()
            
        wvht_match = re.search(r'Maximum Wave Height:\s*([0-9.]+)\s*m', content, re.IGNORECASE)
        pres_match = re.search(r'Minimum Pressure:\s*([0-9.]+)\s*hPa', content, re.IGNORECASE)
        
        if wvht_match and pres_match:
            result["format_correct"] = True
            
        if wvht_match: result["agent_max_wvht"] = float(wvht_match.group(1))
        if pres_match: result["agent_min_pres"] = float(pres_match.group(1))
    except Exception as e:
        if not result["error"]: result["error"] = f"Report Parsing Error: {str(e)}"

print(json.dumps(result))
PYEOF

chmod 666 /tmp/hurricane_fiona_result.json
echo "Result saved to /tmp/hurricane_fiona_result.json"
cat /tmp/hurricane_fiona_result.json
echo "=== Export complete ==="