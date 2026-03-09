#!/bin/bash
# export_result.sh — post_task hook for audit_fleet_compliance_script

echo "=== Exporting Audit Results ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Analyze results using Python
# This script inspects the agent's file content and compares with DB ground truth
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << PYEOF
import os
import sys
import django
import json
import re
import time

# Setup Django
sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
with open('/opt/aerobridge/.env') as f:
    for line in f:
        line = line.strip()
        if '=' in line and not line.startswith('#'):
            k, _, v = line.partition('=')
            os.environ.setdefault(k, v.strip("'").strip('"'))
django.setup()

from registry.models import Aircraft

# --- 1. Compute CURRENT Ground Truth (in case DB changed) ---
total_gt = 0
compliant_gt = 0
non_compliant_gt = 0
aircraft_list_gt = []

try:
    all_ac = Aircraft.objects.all()
    total_gt = all_ac.count()
    for ac in all_ac:
        is_comp = (ac.manufacturer is not None and 
                   ac.operator is not None and 
                   ac.type_certificate is not None)
        if is_comp:
            compliant_gt += 1
        else:
            non_compliant_gt += 1
        aircraft_list_gt.append({
            "id": ac.pk, 
            "compliant": is_comp
        })
except Exception as e:
    print(f"Error computing ground truth: {e}")

# --- 2. Check Agent's Script File ---
script_path = "/home/ga/fleet_compliance_audit.py"
script_exists = os.path.exists(script_path)
script_content_valid = False
script_mtime = 0

if script_exists:
    script_mtime = os.path.getmtime(script_path)
    try:
        with open(script_path, 'r') as f:
            content = f.read()
            # Check for basic ORM markers
            if "django" in content and "Aircraft" in content and ("import" in content or "from" in content):
                script_content_valid = True
    except:
        pass

# --- 3. Check Agent's Report File ---
report_path = "/home/ga/fleet_compliance_report.txt"
report_exists = os.path.exists(report_path)
report_mtime = 0
report_data = {
    "header_present": False,
    "total_found": None,
    "compliant_found": None,
    "non_compliant_found": None,
    "detail_lines_count": 0
}

if report_exists:
    report_mtime = os.path.getmtime(report_path)
    try:
        with open(report_path, 'r') as f:
            lines = f.readlines()
            
        full_text = "".join(lines).lower()
        
        # Check Header
        if "compliance" in full_text:
            report_data["header_present"] = True
            
        # Parse Summary Counts using regex
        # Look for patterns like "Total: 10", "Total Aircraft: 10", "Total: 10"
        total_match = re.search(r'total\D*(\d+)', full_text)
        if total_match:
            report_data["total_found"] = int(total_match.group(1))
            
        comp_match = re.search(r'compliant\D*(\d+)', full_text)
        # Note: 'non-compliant' also contains 'compliant', so we must be careful.
        # Often easier to regex for "Non-Compliant: X" first.
        
        non_comp_match = re.search(r'non[\s-]*compliant\D*(\d+)', full_text)
        if non_comp_match:
            report_data["non_compliant_found"] = int(non_comp_match.group(1))
            
        # Now find 'compliant' that ISN'T 'non-compliant'
        # A simple way is to find lines starting with "Compliant:"
        # Or just trust regex finding independent numbers if formatted distinctly
        
        # Let's try to parse line by line for safer numbers
        for line in lines:
            l = line.lower().strip()
            if "total" in l:
                nums = re.findall(r'\d+', l)
                if nums: report_data["total_found"] = int(nums[0])
            elif "non" in l and "compliant" in l:
                nums = re.findall(r'\d+', l)
                if nums: report_data["non_compliant_found"] = int(nums[0])
            elif "compliant" in l and "non" not in l:
                nums = re.findall(r'\d+', l)
                if nums: report_data["compliant_found"] = int(nums[0])
                
        # Count detail lines
        # Assuming detail lines mention manufacturer or status
        detail_lines = 0
        for line in lines:
            # Skip likely header/summary lines
            if any(x in line.lower() for x in ["total", "summary", "report", "compliance audit"]):
                continue
            # A detail line likely has "Compliant" or "Non-Compliant"
            if "compliant" in line.lower():
                detail_lines += 1
        
        # Adjust for the summary lines we might have counted
        # If we found summary counts, we likely counted 2 summary lines as details
        # Heuristic: subtract 2 or 3 if they seem to be summary lines
        # Better heuristic: Detail lines usually >= total aircraft count
        report_data["detail_lines_count"] = detail_lines

    except Exception as e:
        print(f"Error parsing report: {e}")

# --- 4. Package Result ---
result = {
    "task_start_ts": ${TASK_START},
    "script": {
        "exists": script_exists,
        "valid_content": script_content_valid,
        "mtime": script_mtime,
        "created_during_task": (script_mtime > float(${TASK_START}))
    },
    "report": {
        "exists": report_exists,
        "mtime": report_mtime,
        "created_during_task": (report_mtime > float(${TASK_START})),
        "data": report_data
    },
    "ground_truth": {
        "total": total_gt,
        "compliant": compliant_gt,
        "non_compliant": non_compliant_gt
    },
    "screenshot_path": "/tmp/task_final.png"
}

# Write to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete. Result:")
print(json.dumps(result, indent=2))
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="