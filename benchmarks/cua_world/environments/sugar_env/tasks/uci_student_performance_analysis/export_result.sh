#!/bin/bash
echo "=== Exporting uci_student_performance_analysis result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

su - ga -c "$SUGAR_ENV scrot /tmp/student_perf_task_end.png" 2>/dev/null || true

TASK_START=$(cat /tmp/uci_student_performance_start_ts 2>/dev/null || echo "0")

CSV_EXISTS="false"
SCRIPT_EXISTS="false"
OUTPUT_EXISTS="false"
OUTPUT_MODIFIED="false"

if [ -f /home/ga/Documents/student_data/student-por.csv ]; then
    CSV_EXISTS="true"
fi

if [ -f /home/ga/Documents/grade_analysis.py ]; then
    SCRIPT_EXISTS="true"
fi

if [ -f /home/ga/Documents/school_comparison.txt ]; then
    OUTPUT_EXISTS="true"
    FILE_MTIME=$(stat --format=%Y /home/ga/Documents/school_comparison.txt 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        OUTPUT_MODIFIED="true"
    fi
fi

# Calculate ground truth dynamically using python, making this resilient
# to the dataset being swapped out or the agent using different paths
python3 << PYEOF > /tmp/student_perf_analysis.log 2>&1
import json
import zipfile
import csv
import io
import re
import os

result = {
    "csv_exists": "$CSV_EXISTS" == "true",
    "script_exists": "$SCRIPT_EXISTS" == "true",
    "output_exists": "$OUTPUT_EXISTS" == "true",
    "output_modified": "$OUTPUT_MODIFIED" == "true",
    "gt_gp_avg": 12.5768,
    "gt_ms_avg": 10.6504,
    "extracted_numbers": [],
    "error": None
}

try:
    # Calculate exact ground truth from the zip archive directly
    zip_path = "/home/ga/Documents/student.zip"
    if os.path.exists(zip_path):
        with zipfile.ZipFile(zip_path, 'r') as z:
            if 'student-por.csv' in z.namelist():
                with z.open('student-por.csv') as f:
                    content = f.read().decode('utf-8')
                    reader = csv.DictReader(io.StringIO(content), delimiter=';')
                    gp_scores = []
                    ms_scores = []
                    for row in reader:
                        if row.get('school') == 'GP':
                            try: gp_scores.append(int(row.get('G3', 0)))
                            except: pass
                        elif row.get('school') == 'MS':
                            try: ms_scores.append(int(row.get('G3', 0)))
                            except: pass
                    
                    if gp_scores:
                        result['gt_gp_avg'] = sum(gp_scores) / len(gp_scores)
                    if ms_scores:
                        result['gt_ms_avg'] = sum(ms_scores) / len(ms_scores)
    
    # Extract numbers from agent's output text file
    output_path = "/home/ga/Documents/school_comparison.txt"
    if os.path.exists(output_path):
        with open(output_path, "r", encoding='utf-8', errors='ignore') as f:
            content = f.read()
            # Extract all floating-point numbers or integers written by the agent
            numbers = re.findall(r'\b\d+\.\d+\b|\b\d+\b', content)
            result["extracted_numbers"] = [float(n) for n in numbers]

except Exception as e:
    result["error"] = str(e)

with open("/tmp/uci_student_performance_result.json", "w") as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/uci_student_performance_result.json
echo "Result saved to /tmp/uci_student_performance_result.json"
cat /tmp/uci_student_performance_result.json
echo "=== Export complete ==="