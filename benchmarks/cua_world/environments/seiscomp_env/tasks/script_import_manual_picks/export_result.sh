#!/bin/bash
echo "=== Exporting Script Import Manual Picks Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Query the SeisComP database for picks from the ExternalSource
mysql -u sysop -psysop seiscomp -B -e "
SELECT 
    time_value, 
    waveformID_networkCode, 
    waveformID_stationCode, 
    waveformID_channelCode, 
    phaseHint, 
    evaluationMode, 
    creationInfo_agencyID 
FROM Pick 
WHERE creationInfo_agencyID='ExternalSource';
" > /tmp/raw_picks.tsv 2>/dev/null

# Find any Python scripts modified or created during the task
find /home/ga -name "*.py" -type f -newermt "@$TASK_START" > /tmp/py_scripts.txt 2>/dev/null || true

# Build the JSON result using Python
cat << 'EOF' > /tmp/build_json.py
import json
import os
import sys

picks = []
if os.path.exists('/tmp/raw_picks.tsv'):
    with open('/tmp/raw_picks.tsv', 'r') as f:
        lines = f.readlines()
        if len(lines) > 1:
            headers = lines[0].strip().split('\t')
            for line in lines[1:]:
                parts = line.strip('\n').split('\t')
                if len(parts) == len(headers):
                    picks.append(dict(zip(headers, parts)))

scripts = []
if os.path.exists('/tmp/py_scripts.txt'):
    with open('/tmp/py_scripts.txt', 'r') as f:
        scripts = [line.strip() for line in f.readlines() if line.strip()]

result = {
    'picks': picks,
    'scripts': scripts,
    'script_created': len(scripts) > 0
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
EOF

python3 /tmp/build_json.py

# Fix permissions
chmod 666 /tmp/task_result.json

echo "Exported results:"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="