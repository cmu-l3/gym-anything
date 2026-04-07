#!/bin/bash
echo "=== Exporting analyze_transit_stop_utilization result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final state..."
take_screenshot /tmp/task_final.png ga

REPORT_PATH="/home/ga/SUMO_Output/utilization_report.txt"
XML_PATH="/home/ga/SUMO_Output/stopinfos.xml"

REPORT_EXISTS="false"
XML_EXISTS="false"
CREATED_DURING_TASK="false"

# Check if report exists and when it was created
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# Check if the agent generated the required XML
if [ -f "$XML_PATH" ]; then
    XML_EXISTS="true"
fi

echo "Generating independent ground truth..."
# Run simulation to independently get the correct XML stop outputs
su - ga -c "SUMO_HOME=/usr/share/sumo sumo -c /home/ga/SUMO_Scenarios/bologna_pasubio/run.sumocfg --stop-output /tmp/gt_stopinfos.xml > /tmp/gt_sumo.log 2>&1"

# Extract ground truth metrics and agent's text using Python
cat > /tmp/extract_metrics.py << 'EOF'
import xml.etree.ElementTree as ET
from collections import defaultdict
import json
import os
import traceback

result = {
    "gt_metrics": {},
    "agent_report_content": ""
}

try:
    tree = ET.parse('/tmp/gt_stopinfos.xml')
    root = tree.getroot()
    valid_stops = []
    for child in root:
        if child.tag == 'stopinfo':
            # Check for all required attributes
            if all(attr in child.attrib for attr in ('started', 'ended', 'busStop', 'id')):
                valid_stops.append(child.attrib)

    total_events = len(valid_stops)
    result['gt_metrics']['total_stop_events'] = total_events

    if total_events > 0:
        dwells = [float(s['ended']) - float(s['started']) for s in valid_stops]
        result['gt_metrics']['average_dwell_time'] = round(sum(dwells) / total_events, 2)
        result['gt_metrics']['max_single_dwell'] = round(max(dwells), 2)

        stop_counts = defaultdict(int)
        for s in valid_stops:
            stop_counts[s['busStop']] += 1
        
        # Sort by count descending, then ID ascending (lexicographical)
        busiest = sorted(stop_counts.items(), key=lambda x: (-x[1], x[0]))[0][0]
        result['gt_metrics']['busiest_bus_stop'] = busiest

        veh_dwells = defaultdict(float)
        for s, d in zip(valid_stops, dwells):
            veh_dwells[s['id']] += d
            
        longest_veh = sorted(veh_dwells.items(), key=lambda x: (-x[1], x[0]))[0][0]
        result['gt_metrics']['longest_total_dwell_vehicle'] = longest_veh

except Exception as e:
    result['error'] = str(e)
    result['traceback'] = traceback.format_exc()

# Load agent's report text
report_path = '/home/ga/SUMO_Output/utilization_report.txt'
if os.path.exists(report_path):
    with open(report_path, 'r', encoding='utf-8', errors='ignore') as f:
        result['agent_report_content'] = f.read()

with open('/tmp/metrics.json', 'w') as f:
    json.dump(result, f)
EOF

python3 /tmp/extract_metrics.py
METRICS_JSON=$(cat /tmp/metrics.json 2>/dev/null || echo '{"gt_metrics": {}, "agent_report_content": ""}')

# Generate final task result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "xml_exists": $XML_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png",
    "metrics_data": $METRICS_JSON
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="