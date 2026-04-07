#!/bin/bash
echo "=== Exporting simulate_electric_bus_charging result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if battery.xml was generated during the task
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
BATTERY_XML="/home/ga/SUMO_Output/battery.xml"
BATTERY_NEW="false"

if [ -f "$BATTERY_XML" ]; then
    BATTERY_XML_MTIME=$(stat -c %Y "$BATTERY_XML" 2>/dev/null || echo "0")
    if [ "$BATTERY_XML_MTIME" -gt "$TASK_START" ]; then
        BATTERY_NEW="true"
    fi
fi

# Create a Python script to parse the XML files safely inside the container
cat > /tmp/parse_ev_result.py << 'PYEOF'
import json
import os
import sys
import xml.etree.ElementTree as ET

battery_new = sys.argv[1].lower() == "true"

result = {
    "charging_file_exists": False,
    "spatial_match": False,
    "battery_xml_exists": False,
    "battery_xml_new": battery_new,
    "vtypes_modified": False,
    "report_exists": False,
    "report_lane": None,
    "report_min_battery": None,
    "battery_min_actual": None,
    "first_bus_stop": {},
    "agent_charging_station": {}
}

base_dir = "/home/ga/SUMO_Scenarios/bologna_pasubio"
out_dir = "/home/ga/SUMO_Output"

# 1. Parse original bus stop
try:
    tree = ET.parse(os.path.join(base_dir, "pasubio_bus_stops.add.xml"))
    first_stop = tree.getroot().find("busStop")
    if first_stop is not None:
        result["first_bus_stop"] = {
            "lane": first_stop.get("lane"),
            "startPos": first_stop.get("startPos"),
            "endPos": first_stop.get("endPos")
        }
except Exception as e:
    pass

# 2. Parse charging.add.xml
try:
    charge_path = os.path.join(base_dir, "charging.add.xml")
    if os.path.exists(charge_path):
        result["charging_file_exists"] = True
        tree = ET.parse(charge_path)
        station = tree.getroot().find(".//chargingStation")
        if station is None and tree.getroot().tag == "chargingStation":
            station = tree.getroot()
            
        if station is not None:
            result["agent_charging_station"] = {
                "lane": station.get("lane"),
                "startPos": station.get("startPos"),
                "endPos": station.get("endPos"),
                "power": station.get("power"),
                "efficiency": station.get("efficiency")
            }
            # Check spatial match
            fst = result["first_bus_stop"]
            agt = result["agent_charging_station"]
            if fst and agt:
                if (agt.get("lane") == fst.get("lane") and
                    agt.get("startPos") == fst.get("startPos") and
                    agt.get("endPos") == fst.get("endPos")):
                    result["spatial_match"] = True
except Exception as e:
    pass

# 3. Check vtypes modification
try:
    vtypes_path = os.path.join(base_dir, "pasubio_vtypes.add.xml")
    if os.path.exists(vtypes_path):
        tree = ET.parse(vtypes_path)
        for vtype in tree.getroot().findall(".//vType"):
            params = {p.get("key"): p.get("value") for p in vtype.findall("param")}
            if params.get("has.battery.device", "").lower() == "true":
                result["vtypes_modified"] = True
                break
except Exception as e:
    pass

# 4. Find min battery in battery.xml (ground truth)
try:
    bat_path = os.path.join(out_dir, "battery.xml")
    if os.path.exists(bat_path):
        result["battery_xml_exists"] = True
        tree = ET.parse(bat_path)
        min_bat = float('inf')
        for timestep in tree.getroot().findall(".//timestep"):
            for vehicle in timestep.findall("vehicle"):
                try:
                    actual = float(vehicle.get("actualBatteryCapacity", "inf"))
                    if actual < min_bat:
                        min_bat = actual
                except:
                    pass
        if min_bat != float('inf'):
            result["battery_min_actual"] = min_bat
except Exception as e:
    pass

# 5. Parse agent's report
try:
    report_path = os.path.join(out_dir, "ev_report.txt")
    if os.path.exists(report_path):
        result["report_exists"] = True
        with open(report_path, "r") as f:
            for line in f:
                line = line.strip()
                if line.startswith("charging_lane="):
                    result["report_lane"] = line.split("=")[1].strip()
                elif line.startswith("min_battery_wh="):
                    try:
                        result["report_min_battery"] = float(line.split("=")[1].strip())
                    except:
                        pass
except Exception as e:
    pass

# Write to tmp file
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Run the python script
python3 /tmp/parse_ev_result.py "$BATTERY_NEW"

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="