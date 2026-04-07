#!/bin/bash
echo "=== Exporting model_traffic_incident result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png ga
sleep 1

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# File Paths
SCENARIO_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"
OUT_DIR="/home/ga/SUMO_Output"

INCIDENT_FILE="${SCENARIO_DIR}/incident.rou.xml"
CFG_FILE="${SCENARIO_DIR}/run_incident.sumocfg"
BASE_TRIPINFO="${OUT_DIR}/tripinfo_incident.xml"
REROUTE_TRIPINFO="${OUT_DIR}/tripinfo_rerouted.xml"
REPORT_FILE="${OUT_DIR}/impact_report.txt"

# Safely extract all file metadata and content into JSON via Python
python3 -c "
import os, json

def get_file_info(path):
    if os.path.exists(path):
        return {
            'exists': True,
            'size': os.path.getsize(path),
            'mtime': os.path.getmtime(path)
        }
    return {'exists': False, 'size': 0, 'mtime': 0}

report_content = ''
if os.path.exists('${REPORT_FILE}'):
    with open('${REPORT_FILE}', 'r', encoding='utf-8') as f:
        # Read up to first 1000 chars to avoid massive logs if agent makes a mistake
        report_content = f.read()[:1000]

result = {
    'task_start': int(${TASK_START}),
    'task_end': int(${TASK_END}),
    'incident_file': get_file_info('${INCIDENT_FILE}'),
    'cfg_file': get_file_info('${CFG_FILE}'),
    'base_tripinfo': get_file_info('${BASE_TRIPINFO}'),
    'reroute_tripinfo': get_file_info('${REROUTE_TRIPINFO}'),
    'report_file': get_file_info('${REPORT_FILE}'),
    'report_content': report_content,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions so verifier can easily read it
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="