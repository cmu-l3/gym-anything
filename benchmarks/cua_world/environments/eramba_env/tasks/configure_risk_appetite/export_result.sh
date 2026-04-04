#!/bin/bash
echo "=== Exporting configure_risk_appetite result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Helper functions for fetching DB values
get_appetite() {
    local model=$1
    eramba_db_query "SELECT risk_appetite FROM risk_appetites WHERE model='$model' LIMIT 1;" 2>/dev/null | tr -d '[:space:]'
}

get_method() {
    local model=$1
    eramba_db_query "SELECT method FROM risk_appetites WHERE model='$model' LIMIT 1;" 2>/dev/null | tr -d '[:space:]'
}

get_calc_method() {
    local model=$1
    eramba_db_query "SELECT method FROM risk_calculations WHERE model='$model' LIMIT 1;" 2>/dev/null | tr -d '[:space:]'
}

check_modified() {
    local model=$1
    local start_time=$2
    # Check if modified timestamp > start_time
    local mod_ts=$(eramba_db_query "SELECT UNIX_TIMESTAMP(modified) FROM risk_appetites WHERE model='$model' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
    if [ "$mod_ts" -gt "$start_time" ]; then echo "true"; else echo "false"; fi
}

# 1. Gather data for all three risk models
RISKS_VAL=$(get_appetite "Risks")
TPR_VAL=$(get_appetite "ThirdPartyRisks")
BC_VAL=$(get_appetite "BusinessContinuities")

RISKS_METHOD=$(get_method "Risks")
TPR_METHOD=$(get_method "ThirdPartyRisks")
BC_METHOD=$(get_method "BusinessContinuities")

RISKS_CALC=$(get_calc_method "Risks")
TPR_CALC=$(get_calc_method "ThirdPartyRisks")
BC_CALC=$(get_calc_method "BusinessContinuities")

RISKS_MOD=$(check_modified "Risks" "$TASK_START")
TPR_MOD=$(check_modified "ThirdPartyRisks" "$TASK_START")
BC_MOD=$(check_modified "BusinessContinuities" "$TASK_START")

# Check if Firefox was running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 2. Create JSON result file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "app_running": $APP_RUNNING,
    "risks": {
        "appetite": "$RISKS_VAL",
        "method": "$RISKS_METHOD",
        "calc_method": "$RISKS_CALC",
        "modified_during_task": $RISKS_MOD
    },
    "third_party": {
        "appetite": "$TPR_VAL",
        "method": "$TPR_METHOD",
        "calc_method": "$TPR_CALC",
        "modified_during_task": $TPR_MOD
    },
    "business_continuity": {
        "appetite": "$BC_VAL",
        "method": "$BC_METHOD",
        "calc_method": "$BC_CALC",
        "modified_during_task": $BC_MOD
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 3. Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json