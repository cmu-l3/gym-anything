#!/bin/bash
echo "=== Exporting task result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 1. Anti-bypass: Check if Python was used and artifact exists
PYTHON_RAN="false"
if [ -f /home/ga/.bash_history ] && grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
    PYTHON_RAN="true"
fi

PY_FILES=$(find /home/ga -name "*.py" -newer /home/ga/.task_start_time 2>/dev/null)
SCRIPT_ARTIFACT_EXISTS="false"
if [ -n "$PY_FILES" ]; then
    for pyf in $PY_FILES; do
        if grep -ql "import PySAM\|from PySAM\|csv\|pandas" "$pyf" 2>/dev/null; then
            SCRIPT_ARTIFACT_EXISTS="true"
            PYTHON_RAN="true"
            break
        fi
    done
fi

# 2. Extract Agent's Result File
EXPECTED_FILE="/home/ga/Documents/SAM_Projects/weather_comparison_results.json"
FILE_EXISTS="false"
FILE_MODIFIED="false"
AGENT_TMY="0"
AGENT_LOG="0"
AGENT_DIFF="0"

if [ -f "$EXPECTED_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c%Y "$EXPECTED_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Safely extract values using jq
    if command -v jq &> /dev/null && jq empty "$EXPECTED_FILE" 2>/dev/null; then
        AGENT_TMY=$(jq -r '.tmy_annual_energy_kwh // 0' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        AGENT_LOG=$(jq -r '.logger_2023_annual_energy_kwh // 0' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        AGENT_DIFF=$(jq -r '.yield_difference_percent // 0' "$EXPECTED_FILE" 2>/dev/null || echo "0")
    fi
fi

# 3. Compute Ground Truth Internally via PySAM
# We run exactly the task's parameters against the generated datalogger CSV and the original TMY.
TMY_FILE=$(cat /tmp/tmy_file_used.txt 2>/dev/null)
LOGGER_FILE="/home/ga/Documents/SAM_Projects/raw_logger_data_2023.csv"

cat << 'EOF' > /tmp/compute_ground_truth.py
import sys, csv, json
try:
    import PySAM.Pvwattsv8 as pv
except ImportError:
    print(json.dumps({'gt_tmy_kwh': -1, 'gt_log_kwh': -1, 'error': 'PySAM not installed'}))
    sys.exit(0)

tmy_file = sys.argv[1]
logger_file = sys.argv[2]

tmy_kwh = -1
log_kwh = -1

# TMY Baseline
try:
    m_tmy = pv.default("Photovoltaic")
    m_tmy.SolarResource.solar_resource_file = tmy_file
    m_tmy.SystemDesign.system_capacity = 10000
    m_tmy.SystemDesign.dc_ac_ratio = 1.2
    m_tmy.SystemDesign.array_type = 0
    m_tmy.SystemDesign.tilt = 25
    m_tmy.SystemDesign.azimuth = 180
    m_tmy.SystemDesign.losses = 14.08
    m_tmy.execute()
    tmy_kwh = m_tmy.Outputs.annual_energy
except Exception as e:
    pass

# Logger Data Custom
try:
    sr_dict = {
        'lat': 33.45, 'lon': -112.05, 'tz': -7, 'elev': 330,
        'year': [], 'month': [], 'day': [], 'hour': [], 'minute': [],
        'ghi': [], 'dni': [], 'dhi': [], 'tdry': [], 'wspd': []
    }
    with open(logger_file, 'r') as f:
        reader = csv.reader(f)
        next(reader)
        for row in reader:
            if not row or len(row) < 6: continue
            ts = row[0]
            date_part, time_part = ts.split()
            y, m, d = date_part.split('-')
            hr, mnt, _ = time_part.split(':')
            sr_dict['year'].append(int(y))
            sr_dict['month'].append(int(m))
            sr_dict['day'].append(int(d))
            sr_dict['hour'].append(int(hr))
            sr_dict['minute'].append(int(mnt))
            sr_dict['ghi'].append(float(row[1]))
            sr_dict['dni'].append(float(row[2]))
            sr_dict['dhi'].append(float(row[3]))
            sr_dict['tdry'].append(float(row[4]))
            sr_dict['wspd'].append(float(row[5]))
            
    m_log = pv.default("Photovoltaic")
    m_log.SolarResource.solar_resource_data = sr_dict
    m_log.SystemDesign.system_capacity = 10000
    m_log.SystemDesign.dc_ac_ratio = 1.2
    m_log.SystemDesign.array_type = 0
    m_log.SystemDesign.tilt = 25
    m_log.SystemDesign.azimuth = 180
    m_log.SystemDesign.losses = 14.08
    m_log.execute()
    log_kwh = m_log.Outputs.annual_energy
except Exception as e:
    pass

print(json.dumps({'gt_tmy_kwh': tmy_kwh, 'gt_log_kwh': log_kwh}))
EOF

# Execute ground truth calculation
GT_JSON=$(python3 /tmp/compute_ground_truth.py "$TMY_FILE" "$LOGGER_FILE" 2>/dev/null || echo '{"gt_tmy_kwh":-1, "gt_log_kwh":-1}')
GT_TMY=$(echo "$GT_JSON" | jq -r '.gt_tmy_kwh // -1' 2>/dev/null || echo "-1")
GT_LOG=$(echo "$GT_JSON" | jq -r '.gt_log_kwh // -1' 2>/dev/null || echo "-1")

# Create Final JSON result safely
jq -n \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_modified "$FILE_MODIFIED" \
    --argjson script_artifact_exists "$SCRIPT_ARTIFACT_EXISTS" \
    --argjson python_ran "$PYTHON_RAN" \
    --arg agent_tmy "$AGENT_TMY" \
    --arg agent_log "$AGENT_LOG" \
    --arg agent_diff "$AGENT_DIFF" \
    --arg gt_tmy "$GT_TMY" \
    --arg gt_log "$GT_LOG" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: $file_exists,
        file_modified: $file_modified,
        script_artifact_exists: $script_artifact_exists,
        python_ran: $python_ran,
        agent_tmy: ($agent_tmy | tonumber?),
        agent_log: ($agent_log | tonumber?),
        agent_diff: ($agent_diff | tonumber?),
        gt_tmy: ($gt_tmy | tonumber?),
        gt_log: ($gt_log | tonumber?),
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="