#!/bin/bash
echo "=== Exporting configure_beb_charging result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Python script to safely parse XMLs and collect all data
cat << 'EOF' > /tmp/parse_results.py
import xml.etree.ElementTree as ET
import json
import os
import time

TASK_START = int(os.environ.get('TASK_START', 0))
SCENARIO_DIR = "/home/ga/SUMO_Scenarios/bologna_pasubio"
OUTPUT_DIR = "/home/ga/SUMO_Output"

result = {
    "charger_file_exists": False,
    "charger_valid": False,
    "charger_data": {},
    "vtype_modified": False,
    "vtype_params": {},
    "config_updated": False,
    "config_has_battery_out": False,
    "battery_out_exists": False,
    "battery_out_created_during_task": False,
    "vehicles_charged_count": 0,
    "summary_exists": False,
    "summary_content": "",
    "target_bus_stop": {}
}

# 1. Load ground truth target bus stop
try:
    with open('/tmp/target_bus_stop.json', 'r') as f:
        result["target_bus_stop"] = json.load(f)
except:
    pass

# 2. Parse pasubio_charging.add.xml
charger_path = os.path.join(SCENARIO_DIR, "pasubio_charging.add.xml")
if os.path.exists(charger_path):
    result["charger_file_exists"] = True
    try:
        tree = ET.parse(charger_path)
        charger = tree.getroot().find('.//chargingStation')
        if charger is not None:
            result["charger_valid"] = True
            result["charger_data"] = {
                "id": charger.get("id", ""),
                "lane": charger.get("lane", ""),
                "startPos": charger.get("startPos", ""),
                "endPos": charger.get("endPos", ""),
                "power": charger.get("power", ""),
                "efficiency": charger.get("efficiency", "")
            }
    except:
        pass

# 3. Parse pasubio_vtypes.add.xml
vtype_path = os.path.join(SCENARIO_DIR, "pasubio_vtypes.add.xml")
if os.path.exists(vtype_path):
    try:
        tree = ET.parse(vtype_path)
        for vtype in tree.getroot().findall('.//vType'):
            # Looking for the bus vtype which typically has id containing 'bus' or vClass='bus'
            if 'bus' in vtype.get('id', '').lower() or vtype.get('vClass') == 'bus':
                params = {}
                for param in vtype.findall('param'):
                    params[param.get('key')] = param.get('value')
                
                if params:
                    result["vtype_modified"] = True
                    result["vtype_params"] = params
                break
    except:
        pass

# 4. Parse run.sumocfg
config_path = os.path.join(SCENARIO_DIR, "run.sumocfg")
if os.path.exists(config_path):
    try:
        tree = ET.parse(config_path)
        # Check additional files
        add_files = tree.getroot().find('.//additional-files')
        if add_files is not None and "pasubio_charging.add.xml" in add_files.get("value", ""):
            result["config_updated"] = True
            
        # Check battery output
        batt_out = tree.getroot().find('.//battery-output')
        if batt_out is not None:
            result["config_has_battery_out"] = True
    except:
        pass

# 5. Check battery.xml execution results
battery_path = os.path.join(OUTPUT_DIR, "battery.xml")
if os.path.exists(battery_path):
    result["battery_out_exists"] = True
    mtime = os.path.getmtime(battery_path)
    if mtime > TASK_START:
        result["battery_out_created_during_task"] = True
        
    # Count vehicles that actually charged
    try:
        charged_vehicles = set()
        tree = ET.parse(battery_path)
        for step in tree.getroot().findall('timestep'):
            for veh in step.findall('vehicle'):
                energy_charged = float(veh.get('energyCharged', '0'))
                if energy_charged > 0:
                    charged_vehicles.add(veh.get('id'))
        result["vehicles_charged_count"] = len(charged_vehicles)
    except:
        pass

# 6. Check summary txt
summary_path = os.path.join(OUTPUT_DIR, "charging_summary.txt")
if os.path.exists(summary_path):
    result["summary_exists"] = True
    try:
        with open(summary_path, 'r') as f:
            result["summary_content"] = f.read().strip()
    except:
        pass

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

export TASK_START
python3 /tmp/parse_results.py

# Ensure correct permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="