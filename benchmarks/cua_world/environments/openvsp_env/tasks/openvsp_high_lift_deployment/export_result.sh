#!/bin/bash
echo "=== Exporting result for openvsp_high_lift_deployment ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Record end time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Kill OpenVSP to release file locks
kill_openvsp

# Python script to extract results
python3 << PYEOF
import json
import os
import xml.etree.ElementTree as ET

result = {
    "task_start": int($TASK_START),
    "task_end": int($TASK_END),
    "vsp3_exists": False,
    "vsp3_mtime": 0,
    "stl_exists": False,
    "stl_size": 0,
    "stl_mtime": 0,
    "stl_valid": False,
    "deflections": {}
}

vsp3_path = "/home/ga/Documents/OpenVSP/transport_takeoff.vsp3"
stl_path = "/home/ga/Documents/OpenVSP/exports/takeoff_mesh.stl"

def get_deflect_val(ss_node):
    # Try <Deflect Value="20.0">
    d = ss_node.find(".//Deflect")
    if d is not None and d.get("Value"):
        return float(d.get("Value"))
    
    # Try <Parm Name="Deflect" Value="20.0">
    for p in ss_node.findall(".//Parm"):
        if p.get("Name") == "Deflect" and p.get("Value"):
            return float(p.get("Value"))
            
    # Try <Parm><Name>Deflect</Name><Value>20.0</Value></Parm>
    for p in ss_node.findall(".//Parm"):
        name = p.find("Name")
        if name is not None and name.text == "Deflect":
            val = p.find("Value")
            if val is not None and val.text:
                return float(val.text)
    return None

if os.path.exists(vsp3_path):
    result["vsp3_exists"] = True
    result["vsp3_mtime"] = int(os.path.getmtime(vsp3_path))
    try:
        tree = ET.parse(vsp3_path)
        root = tree.getroot()
        for ss in root.findall(".//SubSurface"):
            name_node = ss.find("Name")
            if name_node is not None and name_node.text:
                ss_name = name_node.text.strip().lower()
                val = get_deflect_val(ss)
                if val is not None:
                    result["deflections"][ss_name] = val
    except Exception as e:
        result["vsp3_error"] = str(e)

if os.path.exists(stl_path):
    result["stl_exists"] = True
    result["stl_size"] = os.path.getsize(stl_path)
    result["stl_mtime"] = int(os.path.getmtime(stl_path))
    try:
        with open(stl_path, "rb") as f:
            header = f.read(80)
            if b"solid" in header.lower() or result["stl_size"] > 200:
                result["stl_valid"] = True
    except:
        pass

with open("/tmp/high_lift_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/high_lift_result.json 2>/dev/null || true
echo "Result exported to /tmp/high_lift_result.json"
cat /tmp/high_lift_result.json

echo "=== Export complete ==="