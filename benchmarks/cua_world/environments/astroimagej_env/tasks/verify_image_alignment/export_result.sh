#!/bin/bash
# Export script for Multi-Filter Alignment Verification task

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Paths
REPORT_FILE="/home/ga/AstroImages/measurements/alignment_report.txt"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
END_TIME=$(date +%s)

# Initialize output variables
REPORT_EXISTS="false"
CREATED_DURING_TASK="false"
REPORT_CONTENT=""

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    
    # Check timestamp
    MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$START_TIME" ]; then
        CREATED_DURING_TASK="true"
    fi
    
    # Read content
    REPORT_CONTENT=$(cat "$REPORT_FILE" | head -n 50 | sed 's/"/\\"/g' | tr '\n' '|')
fi

# Python script to safely parse the agent's report and create result JSON
python3 << PYEOF
import json
import os
import re

report_exists = "${REPORT_EXISTS}" == "true"
created_during = "${CREATED_DURING_TASK}" == "true"
report_path = "${REPORT_FILE}"

result = {
    "report_exists": report_exists,
    "created_during_task": created_during,
    "reported_n_stars": None,
    "reported_mean_dx": None,
    "reported_mean_dy": None,
    "reported_rms": None,
    "reported_max": None,
    "reported_assessment": None,
    "raw_content": "",
    "timestamp": $END_TIME
}

if report_exists and os.path.exists(report_path):
    with open(report_path, "r") as f:
        content = f.read()
        result["raw_content"] = content[:1000] # Limit size

    # Parse using robust regex
    n_match = re.search(r'(?:Number of stars measured|Number of stars|Stars)[:\s]+([0-9]+)', content, re.IGNORECASE)
    dx_match = re.search(r'(?:Mean X offset|Mean X)[:\s=]+([+-]?[0-9]*\.?[0-9]+)', content, re.IGNORECASE)
    dy_match = re.search(r'(?:Mean Y offset|Mean Y)[:\s=]+([+-]?[0-9]*\.?[0-9]+)', content, re.IGNORECASE)
    rms_match = re.search(r'(?:RMS offset|RMS)[:\s=]+([+-]?[0-9]*\.?[0-9]+)', content, re.IGNORECASE)
    max_match = re.search(r'(?:Max offset|Max)[:\s=]+([+-]?[0-9]*\.?[0-9]+)', content, re.IGNORECASE)
    ass_match = re.search(r'(?:Assessment)[:\s=]+([a-zA-Z]+)', content, re.IGNORECASE)

    if n_match: result["reported_n_stars"] = int(n_match.group(1))
    if dx_match: result["reported_mean_dx"] = float(dx_match.group(1))
    if dy_match: result["reported_mean_dy"] = float(dy_match.group(1))
    if rms_match: result["reported_rms"] = float(rms_match.group(1))
    if max_match: result["reported_max"] = float(max_match.group(1))
    if ass_match: result["reported_assessment"] = ass_match.group(1).lower().strip()

# Check for running AIJ
aij_running = os.system("pgrep -f 'astroimagej\|aij\|AstroImageJ' > /dev/null") == 0
result["aij_running"] = aij_running

# Write to tmp file safely
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

chmod 644 /tmp/task_result.json

echo "=== Export Complete ==="
cat /tmp/task_result.json