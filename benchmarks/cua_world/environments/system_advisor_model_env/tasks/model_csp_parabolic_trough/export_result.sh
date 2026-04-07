#!/bin/bash
echo "=== Exporting CSP Parabolic Trough task results ==="

RESULT_FILE="/tmp/task_result.json"
REPORT="/home/ga/Documents/SAM_Projects/csp_trough_report.json"
SCRIPT="/home/ga/Documents/SAM_Projects/csp_trough_simulation.py"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

# Get stats for report file
REPORT_EXISTS="false"
REPORT_SIZE="0"
REPORT_MTIME="0"
if [ -f "$REPORT" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c%s "$REPORT" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c%Y "$REPORT" 2>/dev/null || echo "0")
fi

# Get stats for script file
SCRIPT_EXISTS="false"
SCRIPT_SIZE="0"
SCRIPT_MTIME="0"
SCRIPT_HAS_TROUGH_IMPORT="false"
SCRIPT_HAS_WEATHER_REF="false"
if [ -f "$SCRIPT" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_SIZE=$(stat -c%s "$SCRIPT" 2>/dev/null || echo "0")
    SCRIPT_MTIME=$(stat -c%Y "$SCRIPT" 2>/dev/null || echo "0")
    
    # Check contents
    if grep -qi "troughphysical\|trough_physical\|TroughPhysical" "$SCRIPT" 2>/dev/null; then
        SCRIPT_HAS_TROUGH_IMPORT="true"
    fi
    if grep -qi "daggett\|\.csv\|solar_resource" "$SCRIPT" 2>/dev/null; then
        SCRIPT_HAS_WEATHER_REF="true"
    fi
fi

# Check if python ran
PYTHON_RAN="false"
if grep -qi "python" /home/ga/.bash_history 2>/dev/null; then
    PYTHON_RAN="true"
fi

# Python script to safely parse the JSON report and write the final output
python3 << PYEOF
import json
import os
import sys

report_file = "$REPORT"
result_file = "$RESULT_FILE"

# Prepare base result
result = {
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_valid_json": False,
    "script_exists": "$SCRIPT_EXISTS" == "true",
    "script_has_trough_import": "$SCRIPT_HAS_TROUGH_IMPORT" == "true",
    "script_has_weather_ref": "$SCRIPT_HAS_WEATHER_REF" == "true",
    "python_ran": "$PYTHON_RAN" == "true",
    "annual_energy_kwh": None,
    "capacity_factor_percent": None,
    "solar_multiple": None,
    "tes_hours": None,
    "location": None,
    "report_file_size": int("$REPORT_SIZE"),
    "script_file_size": int("$SCRIPT_SIZE"),
    "report_mtime": int("$REPORT_MTIME"),
    "script_mtime": int("$SCRIPT_MTIME"),
    "task_start_time": int("$START_TIME"),
    "files_created_during_task": False,
    "energy_cf_consistent": False
}

# Timestamps check
if result["report_mtime"] > result["task_start_time"] and result["script_mtime"] > result["task_start_time"]:
    result["files_created_during_task"] = True
elif result["report_mtime"] > result["task_start_time"]: # at least report created
    result["files_created_during_task"] = True

# Read Report JSON
if result["report_exists"]:
    try:
        with open(report_file, 'r') as f:
            data = json.load(f)
        
        result["report_valid_json"] = True
        
        # Extract fields robustly
        result["annual_energy_kwh"] = data.get("annual_energy_kwh")
        result["capacity_factor_percent"] = data.get("capacity_factor_percent")
        result["solar_multiple"] = data.get("solar_multiple")
        result["tes_hours"] = data.get("tes_hours")
        result["location"] = data.get("location")
        
        # Consistency Check
        ae = result["annual_energy_kwh"]
        cf = result["capacity_factor_percent"]
        if ae is not None and cf is not None:
            try:
                ae = float(ae)
                cf = float(cf)
                # 100 MW = 100,000 kW. Energy = 100000 * 8760 * (cf / 100)
                expected_ae = 100000 * 8760 * (cf / 100.0)
                if expected_ae > 0:
                    ratio = ae / expected_ae
                    if 0.8 <= ratio <= 1.2:
                        result["energy_cf_consistent"] = True
            except (ValueError, TypeError):
                pass
                
    except Exception as e:
        print(f"Error parsing JSON report: {e}")

# Write to file
try:
    with open(result_file, 'w') as f:
        json.dump(result, f, indent=2)
    os.chmod(result_file, 0o666)
except Exception as e:
    print(f"Failed to write result: {e}")

PYEOF

echo "=== Export complete ==="