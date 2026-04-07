#!/bin/bash
echo "=== Exporting convert_allway_stop result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
SCENARIO_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"

# Extract the TARGET_JUNCTION_ID from the briefing file
TARGET_ID=$(grep "TARGET_JUNCTION_ID=" "$SCENARIO_DIR/junction_briefing.txt" | cut -d'=' -f2 | tr -d '\n\r')

# Python script to analyze the XML files safely and output a JSON fragment
python3 - <<EOF > /tmp/xml_analysis.json
import os
import json
import xml.etree.ElementTree as ET

result = {
    "target_junction": "$TARGET_ID",
    "patch_exists": False,
    "patch_valid": False,
    "patch_has_node": False,
    "net_exists": False,
    "net_valid": False,
    "net_size": 0,
    "net_has_allway": False,
    "sumocfg_exists": False,
    "sumocfg_valid": False,
    "sumocfg_uses_new_net": False,
    "trips_exists": False,
    "trips_valid": False,
    "trips_count": 0
}

scenario_dir = "$SCENARIO_DIR"
patch_path = os.path.join(scenario_dir, "patch.nod.xml")
net_path = os.path.join(scenario_dir, "pasubio_allway.net.xml")
cfg_path = os.path.join(scenario_dir, "run_allway.sumocfg")
trips_path = os.path.join(scenario_dir, "tripinfos_allway.xml")

# 1. Check Patch File
if os.path.isfile(patch_path):
    result["patch_exists"] = True
    try:
        tree = ET.parse(patch_path)
        root = tree.getroot()
        result["patch_valid"] = True
        
        # Look for the node definition
        for node in root.findall('.//node'):
            if node.get('id') == "$TARGET_ID" and node.get('type') == 'allway_stop':
                result["patch_has_node"] = True
                break
    except:
        pass

# 2. Check Network File
if os.path.isfile(net_path):
    result["net_exists"] = True
    result["net_size"] = os.path.getsize(net_path)
    try:
        tree = ET.parse(net_path)
        root = tree.getroot()
        result["net_valid"] = True
        
        for j in root.findall('junction'):
            if j.get('id') == "$TARGET_ID" and j.get('type') == 'allway_stop':
                result["net_has_allway"] = True
                break
    except:
        pass

# 3. Check SUMOCFG File
if os.path.isfile(cfg_path):
    result["sumocfg_exists"] = True
    try:
        tree = ET.parse(cfg_path)
        root = tree.getroot()
        result["sumocfg_valid"] = True
        
        net_file_elem = root.find('.//net-file')
        if net_file_elem is not None and net_file_elem.get('value') == 'pasubio_allway.net.xml':
            result["sumocfg_uses_new_net"] = True
    except:
        pass

# 4. Check Tripinfos
if os.path.isfile(trips_path):
    result["trips_exists"] = True
    try:
        tree = ET.parse(trips_path)
        root = tree.getroot()
        result["trips_valid"] = True
        result["trips_count"] = len(root.findall('tripinfo'))
    except:
        pass

print(json.dumps(result))
EOF

# Read the analysis JSON
ANALYSIS_JSON=$(cat /tmp/xml_analysis.json)

# Check file timestamps for anti-gaming (were they created after the task started?)
PATCH_MTIME=$(stat -c %Y "$SCENARIO_DIR/patch.nod.xml" 2>/dev/null || echo "0")
NET_MTIME=$(stat -c %Y "$SCENARIO_DIR/pasubio_allway.net.xml" 2>/dev/null || echo "0")
CFG_MTIME=$(stat -c %Y "$SCENARIO_DIR/run_allway.sumocfg" 2>/dev/null || echo "0")
TRIPS_MTIME=$(stat -c %Y "$SCENARIO_DIR/tripinfos_allway.xml" 2>/dev/null || echo "0")

CREATED_DURING_TASK="false"
if [ "$PATCH_MTIME" -ge "$TASK_START" ] && [ "$NET_MTIME" -ge "$TASK_START" ]; then
    CREATED_DURING_TASK="true"
fi

# Create final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "created_during_task": $CREATED_DURING_TASK,
    "analysis": $ANALYSIS_JSON,
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false")
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json:"
cat /tmp/task_result.json