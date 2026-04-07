#!/bin/bash
echo "=== Exporting Hydrology Task Results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
METRICS_CSV="/home/ga/RProjects/output/catchment_metrics.csv"
PLOT_PNG="/home/ga/RProjects/output/validation_hydrograph.png"
SCRIPT_PATH="/home/ga/RProjects/catchment_analysis.R"

# --- 1. Check Metrics CSV ---
METRICS_EXISTS="false"
METRICS_CREATED_DURING="false"
CALIB_NSE="0"
VALID_NSE="0"

if [ -f "$METRICS_CSV" ]; then
    METRICS_EXISTS="true"
    MTIME=$(stat -c %Y "$METRICS_CSV" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        METRICS_CREATED_DURING="true"
    fi

    # Parse CSV using embedded Python for robustness
    # Expecting columns like: Calibration_NSE, Validation_NSE
    # Handling cases where names might differ slightly (case insensitive)
    PARSED_METRICS=$(python3 -c "
import csv, sys
try:
    with open('$METRICS_CSV', 'r') as f:
        reader = csv.DictReader(f)
        row = next(reader)
        # Find columns
        calib_key = next((k for k in row.keys() if 'calib' in k.lower() and 'nse' in k.lower()), None)
        valid_key = next((k for k in row.keys() if 'valid' in k.lower() and 'nse' in k.lower()), None)
        
        c_val = float(row[calib_key]) if calib_key else 0.0
        v_val = float(row[valid_key]) if valid_key else 0.0
        print(f'{c_val}|{v_val}')
except Exception:
    print('0|0')
")
    CALIB_NSE=$(echo "$PARSED_METRICS" | cut -d'|' -f1)
    VALID_NSE=$(echo "$PARSED_METRICS" | cut -d'|' -f2)
fi

# --- 2. Check Plot ---
PLOT_EXISTS="false"
PLOT_CREATED_DURING="false"
PLOT_SIZE_BYTES=0

if [ -f "$PLOT_PNG" ]; then
    PLOT_EXISTS="true"
    MTIME=$(stat -c %Y "$PLOT_PNG" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        PLOT_CREATED_DURING="true"
    fi
    PLOT_SIZE_BYTES=$(stat -c %s "$PLOT_PNG" 2>/dev/null || echo "0")
fi

# --- 3. Check Script and Package ---
SCRIPT_MODIFIED="false"
HAS_AIRGR="false"
HAS_CALIB_FUNC="false"

if [ -f "$SCRIPT_PATH" ]; then
    MTIME=$(stat -c %Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
    
    CONTENT=$(cat "$SCRIPT_PATH")
    if echo "$CONTENT" | grep -qi "Calibration_Michel"; then
        HAS_CALIB_FUNC="true"
    fi
fi

# Check if airGR is actually installed
HAS_AIRGR_INSTALLED=$(R --slave -e "cat(requireNamespace('airGR', quietly=TRUE))" 2>/dev/null)
if [ "$HAS_AIRGR_INSTALLED" == "TRUE" ]; then
    HAS_AIRGR="true"
fi

# --- 4. Generate JSON ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "metrics_csv_exists": $METRICS_EXISTS,
    "metrics_created_during_task": $METRICS_CREATED_DURING,
    "calibration_nse": $CALIB_NSE,
    "validation_nse": $VALID_NSE,
    "plot_exists": $PLOT_EXISTS,
    "plot_created_during_task": $PLOT_CREATED_DURING,
    "plot_size_bytes": $PLOT_SIZE_BYTES,
    "script_modified": $SCRIPT_MODIFIED,
    "script_has_calib_func": $HAS_CALIB_FUNC,
    "package_installed": $HAS_AIRGR
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="