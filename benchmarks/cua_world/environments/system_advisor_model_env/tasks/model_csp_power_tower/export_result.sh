#!/bin/bash
echo "=== Exporting CSP Power Tower task results ==="

# Record task end
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_JSON="/home/ga/Documents/SAM_Projects/csp_power_tower_results.json"
SCRIPT_FILE="/home/ga/Documents/SAM_Projects/csp_power_tower_model.py"
OUTPUT="/tmp/task_result.json"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true
if [ ! -f /tmp/task_final_state.png ]; then
    DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true
fi

# Safely extract and format results using Python
python3 << PYEOF
import json
import os
import stat

task_start = int("$TASK_START")
result_json_path = "$RESULT_JSON"
script_file_path = "$SCRIPT_FILE"

result = {
    "results_json_exists": os.path.isfile(result_json_path),
    "results_json_modified_after_start": False,
    "script_exists": os.path.isfile(script_file_path),
    "script_modified_after_start": False,
    "script_imports_tcsmoltensalt": False,
    "script_calls_execute": False,
    "script_sets_P_ref": False,
    "P_ref_mw": None,
    "tshours": None,
    "solar_multiple": None,
    "annual_energy_kwh": None,
    "annual_energy_gwh": None,
    "capacity_factor_pct": None,
    "lcoe_real_cents_per_kwh": None,
    "weather_file": None,
    "project_name": None
}

# Check Result JSON
if result["results_json_exists"]:
    try:
        mtime = os.stat(result_json_path).st_mtime
        if mtime > task_start:
            result["results_json_modified_after_start"] = True
            
        with open(result_json_path, "r") as f:
            data = json.load(f)
            
        result["project_name"] = data.get("project_name")
        result["weather_file"] = data.get("weather_file")
        
        config = data.get("configuration", {})
        result["P_ref_mw"] = config.get("P_ref_mw")
        result["tshours"] = config.get("tshours")
        result["solar_multiple"] = config.get("solar_multiple")
        
        results = data.get("results", {})
        result["annual_energy_kwh"] = results.get("annual_energy_kwh")
        result["annual_energy_gwh"] = results.get("annual_energy_gwh")
        result["capacity_factor_pct"] = results.get("capacity_factor_pct")
        result["lcoe_real_cents_per_kwh"] = results.get("lcoe_real_cents_per_kwh")
    except Exception as e:
        print(f"Error parsing results JSON: {e}")

# Check Script File
if result["script_exists"]:
    try:
        mtime = os.stat(script_file_path).st_mtime
        if mtime > task_start:
            result["script_modified_after_start"] = True
            
        with open(script_file_path, "r") as f:
            content = f.read()
            
        if "TcsmoltenSalt" in content or "Tcsmolten" in content.lower():
            result["script_imports_tcsmoltensalt"] = True
        if ".execute(" in content or "execute()" in content:
            result["script_calls_execute"] = True
        if "P_ref" in content:
            result["script_sets_P_ref"] = True
    except Exception as e:
        print(f"Error parsing script file: {e}")

# Write to output safely
with open("$OUTPUT", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 "$OUTPUT" 2>/dev/null || true
echo "Exported results:"
cat "$OUTPUT"
echo "=== Export complete ==="