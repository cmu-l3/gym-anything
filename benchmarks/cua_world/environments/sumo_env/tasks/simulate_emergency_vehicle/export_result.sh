#!/bin/bash
echo "=== Exporting task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Read generated files and extract metrics using python
python3 -c "
import json
import os
import xml.etree.ElementTree as ET

def read_file(path):
    if os.path.exists(path):
        with open(path, 'r') as f:
            return f.read()
    return ''

amb_xml = read_file('/home/ga/SUMO_Scenarios/bologna_pasubio/ambulance.rou.xml')
run_cfg = read_file('/home/ga/SUMO_Scenarios/bologna_pasubio/run_emergency.sumocfg')
agent_report = read_file('/home/ga/SUMO_Output/ambulance_report.json')

# Parse tripinfos to find amb_1
amb_trip = None
tripinfos_path = '/home/ga/SUMO_Output/tripinfos.xml'
tripinfo_exists = os.path.exists(tripinfos_path)
if tripinfo_exists:
    try:
        tree = ET.parse(tripinfos_path)
        for trip in tree.getroot().findall('tripinfo'):
            if trip.get('id') == 'amb_1':
                amb_trip = {
                    'duration': float(trip.get('duration', 0)),
                    'routeLength': float(trip.get('routeLength', 0)),
                    'timeLoss': float(trip.get('timeLoss', 0))
                }
                break
    except Exception as e:
        pass

result = {
    'task_start': ${TASK_START},
    'task_end': ${TASK_END},
    'amb_xml': amb_xml,
    'run_cfg': run_cfg,
    'agent_report': agent_report,
    'tripinfo_exists': tripinfo_exists,
    'amb_trip': amb_trip
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="