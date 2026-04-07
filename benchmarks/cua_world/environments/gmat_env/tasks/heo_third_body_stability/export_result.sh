#!/bin/bash
set -euo pipefail

echo "=== Exporting heo_third_body_stability results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
TRUTH_DAYS=$(cat /tmp/baseline_truth.txt 2>/dev/null || echo "0")

SCRIPT_PATH="/home/ga/GMAT_output/stable_heo_mission.script"
REPORT_PATH="/home/ga/GMAT_output/heo_stability_report.txt"

# Capture final screenshot
take_screenshot /tmp/task_final.png

check_file() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath")
        local size=$(stat -c %s "$fpath")
        local created_during=$([ "$mtime" -ge "$TASK_START" ] && echo "true" || echo "false")
        echo "{\"exists\": true, \"size\": $size, \"created_during_task\": $created_during}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

SCRIPT_STATS=$(check_file "$SCRIPT_PATH")
REPORT_STATS=$(check_file "$REPORT_PATH")

# Extract values from report
AGENT_BASELINE="0"
AGENT_RAAN=""

if [ -f "$REPORT_PATH" ]; then
    AGENT_BASELINE=$(grep -oP 'Baseline_Lifetime_Days:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    AGENT_RAAN=$(grep -oP 'Stable_RAAN_deg:\s*\K\-?[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "")
fi

# Verify Agent's RAAN using ground-truth integration
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
AGENT_RAAN_SURVIVED="false"
VERIFY_FINAL_DAYS="0"
VERIFY_FINAL_ALT="0"

if [ -n "$AGENT_RAAN" ] && [ -n "$CONSOLE" ] && [ -f /tmp/baseline_heo.script ]; then
    echo "Verifying Agent's RAAN: $AGENT_RAAN"
    
    # Substitute the RAAN in the baseline ground truth script and change report output
    sed "s/GMAT EXHEA.RAAN = 0.0;/GMAT EXHEA.RAAN = $AGENT_RAAN;/g" /tmp/baseline_heo.script | \
    sed "s|/tmp/baseline_report.txt|/tmp/verify_report.txt|g" > /tmp/verify_raan.script
    
    timeout 120 "$CONSOLE" --run /tmp/verify_raan.script > /tmp/gmat_verify.log 2>&1 || true
    
    if [ -f /tmp/verify_report.txt ]; then
        LAST_LINE=$(tail -n 1 /tmp/verify_report.txt | tr -s ' ' | sed 's/^ *//' || echo "")
        if [ -n "$LAST_LINE" ]; then
            VERIFY_FINAL_DAYS=$(echo "$LAST_LINE" | cut -d' ' -f1 || echo "0")
            VERIFY_FINAL_ALT=$(echo "$LAST_LINE" | cut -d' ' -f2 || echo "0")
            
            # Check if it survived (at least 1824.9 days and altitude > 120)
            if python3 -c "import sys; sys.exit(0 if float('$VERIFY_FINAL_DAYS') >= 1824.0 and float('$VERIFY_FINAL_ALT') >= 120.0 else 1)"; then
                AGENT_RAAN_SURVIVED="true"
                echo "SUCCESS: Agent's RAAN $AGENT_RAAN survived $VERIFY_FINAL_DAYS days, final alt $VERIFY_FINAL_ALT km!"
            else
                AGENT_RAAN_SURVIVED="false"
                echo "FAILED: Agent's RAAN $AGENT_RAAN crashed after $VERIFY_FINAL_DAYS days at alt $VERIFY_FINAL_ALT km."
            fi
        fi
    fi
fi

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "report_file": $REPORT_STATS,
    "truth_baseline_days": "$TRUTH_DAYS",
    "agent_baseline_days": "$AGENT_BASELINE",
    "agent_stable_raan": "$AGENT_RAAN",
    "agent_raan_survived": $AGENT_RAAN_SURVIVED,
    "verify_final_days": "$VERIFY_FINAL_DAYS",
    "verify_final_alt_km": "$VERIFY_FINAL_ALT",
    "script_path": "$SCRIPT_PATH",
    "report_path": "$REPORT_PATH"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete."
cat /tmp/task_result.json
echo "=== Export Done ==="