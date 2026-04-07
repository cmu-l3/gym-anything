#!/bin/bash
echo "=== Exporting Hypoxic Event Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Paths
TARGET_FILE="/home/ga/Desktop/hypoxia_test_data.csv"
LOG_FILE="/home/ga/openice/logs/openice.log"

# --- CHECK 1: File Existence & Timestamp ---
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# --- CHECK 2: Data Content Analysis (Python) ---
# We use python to parse the CSV and look for the specific physiological states
# OpenICE Data Recorder CSVs usually have headers like "Time", "Device", "Metric", "Value"
# Or a wide format. We'll attempt to parse robustly.

DATA_ANALYSIS_JSON="{}"

if [ "$FILE_EXISTS" = "true" ] && [ "$FILE_SIZE" -gt 50 ]; then
    DATA_ANALYSIS_JSON=$(python3 -c "
import csv
import json
import sys

filename = '$TARGET_FILE'
result = {
    'baseline_found': False,
    'distress_found': False,
    'transition_valid': False,
    'max_hr': 0,
    'min_spo2': 100,
    'row_count': 0
}

try:
    with open(filename, 'r') as f:
        # Read a sample to deduce structure or just read all lines
        lines = f.readlines()
        result['row_count'] = len(lines)
        
        # Simple heuristic parsing: look for lines containing Heart Rate or SpO2 values
        # This handles different recorder formats (CSV vs text log)
        
        baseline_timestamps = []
        distress_timestamps = []
        
        for i, line in enumerate(lines):
            # Normalization
            line_lower = line.lower()
            parts = line.split(',')
            
            # Try to extract numbers
            # Assuming standard OpenICE CSV format often has: Time, MetricID, InstanceID, Value
            # Or Wide: Time, HR, SpO2...
            
            # Identify values based on magnitude heuristics if columns aren't clear
            # HR: 40-200, SpO2: 50-100
            
            hr_val = None
            spo2_val = None
            timestamp = i # Use line number as proxy for time if timestamp parsing fails
            
            # Heuristic: Find values in the line
            import re
            numbers = re.findall(r'-?\d+\.?\d*', line)
            numbers = [float(n) for n in numbers]
            
            # Filter standard timestamp-looking large numbers if possible, but simple logic:
            
            for n in numbers:
                # SpO2 Check
                if 50 <= n <= 100:
                    # If explicitly labelled in line
                    if 'spo2' in line_lower or 'sat' in line_lower:
                        spo2_val = n
                        if n < result['min_spo2']: result['min_spo2'] = n
                    # Or just purely value based if we have typical ranges
                    elif n > 95: # High SpO2
                        pass 
                        
                # HR Check
                if 40 <= n <= 200:
                    if 'rate' in line_lower or 'hr' in line_lower or 'bpm' in line_lower or 'puls' in line_lower:
                        hr_val = n
                        if n > result['max_hr']: result['max_hr'] = n
            
            # Check Baseline State (HR 60-85, SpO2 95-100)
            # We need ONE valid baseline point
            is_baseline = False
            if hr_val and 60 <= hr_val <= 85: is_baseline = True
            if spo2_val and 95 <= spo2_val <= 100: is_baseline = True
            # Stronger check: need both or explicit label? 
            # Let's be lenient: if we see a row with EITHER valid baseline HR or SpO2, count it
            if is_baseline:
                baseline_timestamps.append(timestamp)
                result['baseline_found'] = True
                
            # Check Distress State (HR > 115, SpO2 < 92)
            is_distress = False
            if hr_val and hr_val > 115: is_distress = True
            if spo2_val and spo2_val < 92: is_distress = True
            
            if is_distress:
                distress_timestamps.append(timestamp)
                result['distress_found'] = True

        # Check transition: Distress should appear AFTER Baseline
        if baseline_timestamps and distress_timestamps:
            first_distress = min(distress_timestamps)
            first_baseline = min(baseline_timestamps)
            # We want some baseline BEFORE distress
            if first_distress > first_baseline:
                result['transition_valid'] = True
                
except Exception as e:
    result['error'] = str(e)

print(json.dumps(result))
")
fi

# --- CHECK 3: App Usage (Logs & Windows) ---
# Check new log lines
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")
NEW_LOG=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")

RECORDER_LAUNCHED="false"
SIM_CONTROL_LAUNCHED="false"
MONITOR_CREATED="false"

# Check logs for keywords
if echo "$NEW_LOG" | grep -qiE "recorder|recording|persistence"; then
    RECORDER_LAUNCHED="true"
fi
if echo "$NEW_LOG" | grep -qiE "simulation|control|generator"; then
    SIM_CONTROL_LAUNCHED="true"
fi
if echo "$NEW_LOG" | grep -qiE "multiparameter|monitor|device.*created"; then
    MONITOR_CREATED="true"
fi

# Check Windows (fallback)
CURRENT_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null)
if echo "$CURRENT_WINDOWS" | grep -qiE "recorder"; then RECORDER_LAUNCHED="true"; fi
if echo "$CURRENT_WINDOWS" | grep -qiE "simulation|control"; then SIM_CONTROL_LAUNCHED="true"; fi

# Create Result JSON
create_result_json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "recorder_launched": $RECORDER_LAUNCHED,
    "sim_control_launched": $SIM_CONTROL_LAUNCHED,
    "monitor_created": $MONITOR_CREATED,
    "data_analysis": $DATA_ANALYSIS_JSON,
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

echo "=== Export Complete ==="
cat /tmp/task_result.json