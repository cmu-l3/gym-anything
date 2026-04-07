#!/bin/bash
echo "=== Exporting ozone_gam_environmental result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
take_screenshot /tmp/task_end.png

# Paths
SCRIPT_PATH="/home/ga/RProjects/ozone_analysis.R"
CSV_PATH="/home/ga/RProjects/output/model_comparison.csv"
PNG_PATH="/home/ga/RProjects/output/gam_smooths.png"
TXT_PATH="/home/ga/RProjects/output/high_risk_prediction.txt"

# 1. Check Script
SCRIPT_EXISTS=false
SCRIPT_MODIFIED=false
HAS_MGCV=false
HAS_GAM=false
HAS_S=false

if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS=true
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    [ "$SCRIPT_MTIME" -gt "$TASK_START" ] && SCRIPT_MODIFIED=true
    
    # Analyze code skipping comments
    CODE=$(grep -v '^\s*#' "$SCRIPT_PATH")
    echo "$CODE" | grep -qiE "library\s*\(\s*mgcv|require\s*\(\s*mgcv|mgcv::" && HAS_MGCV=true
    echo "$CODE" | grep -qi "gam\s*\(" && HAS_GAM=true
    echo "$CODE" | grep -qi "s\s*\(" && HAS_S=true
fi

# 2. Check CSV Model Comparison
CSV_EXISTS=false
CSV_IS_NEW=false
LM_AIC="inf"
GAM_AIC="inf"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    [ "$CSV_MTIME" -gt "$TASK_START" ] && CSV_IS_NEW=true
    
    # Extract AIC values gracefully using python3
    PYTHON_OUTPUT=$(python3 -c '
import csv
try:
    lm_aic = float("inf")
    gam_aic = float("inf")
    with open("'$CSV_PATH'", newline="") as f:
        reader = csv.DictReader(f)
        headers = [h.lower().strip() for h in (reader.fieldnames or [])]
        model_col = next((h for h in headers if "model" in h), None)
        aic_col = next((h for h in headers if "aic" in h), None)
        if model_col and aic_col:
            for row in reader:
                m = row[model_col].lower()
                try:
                    a = float(row[aic_col])
                    if "gam" in m: gam_aic = a
                    elif "lm" in m or "linear" in m: lm_aic = a
                except:
                    pass
    print(f"{lm_aic} {gam_aic}")
except:
    print("inf inf")
' 2>/dev/null)
    LM_AIC=$(echo "$PYTHON_OUTPUT" | awk '{print $1}')
    GAM_AIC=$(echo "$PYTHON_OUTPUT" | awk '{print $2}')
fi

# 3. Check PNG Plot
PNG_EXISTS=false
PNG_IS_NEW=false
PNG_SIZE_KB=0

if [ -f "$PNG_PATH" ]; then
    PNG_EXISTS=true
    PNG_MTIME=$(stat -c %Y "$PNG_PATH" 2>/dev/null || echo "0")
    [ "$PNG_MTIME" -gt "$TASK_START" ] && PNG_IS_NEW=true
    PNG_SIZE_KB=$(du -k "$PNG_PATH" 2>/dev/null | cut -f1)
fi

# 4. Check Prediction TXT
TXT_EXISTS=false
TXT_IS_NEW=false
PREDICTION=""

if [ -f "$TXT_PATH" ]; then
    TXT_EXISTS=true
    TXT_MTIME=$(stat -c %Y "$TXT_PATH" 2>/dev/null || echo "0")
    [ "$TXT_MTIME" -gt "$TASK_START" ] && TXT_IS_NEW=true
    # Extract the first valid float/integer pattern
    PREDICTION=$(grep -oE "[0-9]+(\.[0-9]+)?" "$TXT_PATH" | head -1 || echo "")
fi

# Build Output JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "script_exists": $SCRIPT_EXISTS,
    "script_modified": $SCRIPT_MODIFIED,
    "has_mgcv": $HAS_MGCV,
    "has_gam": $HAS_GAM,
    "has_s": $HAS_S,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "lm_aic": "$LM_AIC",
    "gam_aic": "$GAM_AIC",
    "png_exists": $PNG_EXISTS,
    "png_is_new": $PNG_IS_NEW,
    "png_size_kb": $PNG_SIZE_KB,
    "txt_exists": $TXT_EXISTS,
    "txt_is_new": $TXT_IS_NEW,
    "prediction": "$PREDICTION"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="