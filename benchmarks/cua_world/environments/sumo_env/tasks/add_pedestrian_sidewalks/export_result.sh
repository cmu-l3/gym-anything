#!/bin/bash
echo "=== Exporting Pedestrian Sidewalks Task Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Path variables
OUTPUT_DIR="/home/ga/SUMO_Output"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
END_TIME=$(date +%s)

# Run a Python script to robustly parse the XML files and evaluate state
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

python3 - <<EOF > "$TEMP_JSON"
import os
import json
import xml.etree.ElementTree as ET

output_dir = "$OUTPUT_DIR"
start_time = int("$START_TIME")
end_time = int("$END_TIME")

result = {
    "task_start_time": start_time,
    "task_end_time": end_time,
    "files_created_after_start": True,
    "net_file": {"exists": False, "valid_xml": False, "has_sidewalks": False, "mtime_valid": False},
    "rou_file": {"exists": False, "valid_xml": False, "person_count": 0, "mtime_valid": False},
    "cfg_file": {"exists": False, "valid_xml": False, "refs_net": False, "refs_ped": False, "refs_veh": False, "mtime_valid": False},
    "tripinfo": {"exists": False, "valid_xml": False, "vehicle_count": 0, "pedestrian_count": 0, "mtime_valid": False}
}

def check_mtime(filepath):
    try:
        mtime = os.path.getmtime(filepath)
        return mtime >= start_time
    except:
        return False

# 1. Check Network File
net_path = os.path.join(output_dir, "pasubio_with_sidewalks.net.xml")
if os.path.exists(net_path):
    result["net_file"]["exists"] = True
    result["net_file"]["mtime_valid"] = check_mtime(net_path)
    if not result["net_file"]["mtime_valid"]: result["files_created_after_start"] = False
    try:
        tree = ET.parse(net_path)
        root = tree.getroot()
        if root.tag == "net":
            result["net_file"]["valid_xml"] = True
            # Look for sidewalks
            has_sidewalk = False
            for edge in root.findall('edge'):
                for lane in edge.findall('lane'):
                    allow = lane.get('allow', '')
                    disallow = lane.get('disallow', '')
                    lane_type = lane.get('type', '')
                    if 'pedestrian' in allow or 'sidewalk' in lane_type or (not allow and 'pedestrian' not in disallow):
                        # Simple heuristic: strictly checking if netconvert successfully guessed sidewalks
                        # netconvert --sidewalks.guess typically adds allow="pedestrian"
                        if 'pedestrian' in allow:
                            has_sidewalk = True
                            break
                if has_sidewalk:
                    break
            result["net_file"]["has_sidewalks"] = has_sidewalk
    except Exception as e:
        pass

# 2. Check Pedestrian Routes
rou_path = os.path.join(output_dir, "pedestrians.rou.xml")
if os.path.exists(rou_path):
    result["rou_file"]["exists"] = True
    result["rou_file"]["mtime_valid"] = check_mtime(rou_path)
    if not result["rou_file"]["mtime_valid"]: result["files_created_after_start"] = False
    try:
        tree = ET.parse(rou_path)
        root = tree.getroot()
        result["rou_file"]["valid_xml"] = True
        
        person_count = 0
        for person in root.findall('person'):
            # Must have a walk child
            if person.find('walk') is not None:
                person_count += 1
        result["rou_file"]["person_count"] = person_count
    except Exception as e:
        pass

# 3. Check SUMO Config
cfg_path = os.path.join(output_dir, "pedestrian_sim.sumocfg")
if os.path.exists(cfg_path):
    result["cfg_file"]["exists"] = True
    result["cfg_file"]["mtime_valid"] = check_mtime(cfg_path)
    if not result["cfg_file"]["mtime_valid"]: result["files_created_after_start"] = False
    try:
        tree = ET.parse(cfg_path)
        root = tree.getroot()
        if root.tag == "sumoConfiguration" or root.tag == "configuration":
            result["cfg_file"]["valid_xml"] = True
            
            # Extract references
            cfg_text = ET.tostring(root, encoding='utf8', method='xml').decode('utf8')
            if 'pasubio_with_sidewalks.net.xml' in cfg_text:
                result["cfg_file"]["refs_net"] = True
            if 'pedestrians.rou.xml' in cfg_text:
                result["cfg_file"]["refs_ped"] = True
            if 'pasubio.rou.xml' in cfg_text or 'pasubio_vtypes.add.xml' in cfg_text:
                result["cfg_file"]["refs_veh"] = True
    except Exception as e:
        pass

# 4. Check Tripinfo
trip_path = os.path.join(output_dir, "tripinfo_ped.xml")
if os.path.exists(trip_path):
    result["tripinfo"]["exists"] = True
    result["tripinfo"]["mtime_valid"] = check_mtime(trip_path)
    if not result["tripinfo"]["mtime_valid"]: result["files_created_after_start"] = False
    try:
        tree = ET.parse(trip_path)
        root = tree.getroot()
        if root.tag == "tripinfos":
            result["tripinfo"]["valid_xml"] = True
            result["tripinfo"]["vehicle_count"] = len(root.findall('tripinfo'))
            result["tripinfo"]["pedestrian_count"] = len(root.findall('personinfo'))
    except Exception as e:
        pass

print(json.dumps(result, indent=2))
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="