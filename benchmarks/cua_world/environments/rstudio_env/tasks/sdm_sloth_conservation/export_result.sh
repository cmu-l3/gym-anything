#!/bin/bash
echo "=== Exporting SDM Sloth Conservation Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
take_screenshot /tmp/task_end.png

OUTPUT_DIR="/home/ga/RProjects/output"
SCRIPT_PATH="/home/ga/RProjects/sdm_analysis.R"

# --- 1. Check Map Image ---
MAP_FILE="$OUTPUT_DIR/sloth_suitability_map.png"
MAP_EXISTS=false
MAP_IS_NEW=false
MAP_SIZE_KB=0

if [ -f "$MAP_FILE" ]; then
    MAP_EXISTS=true
    MAP_MTIME=$(stat -c %Y "$MAP_FILE" 2>/dev/null || echo "0")
    [ "$MAP_MTIME" -gt "$TASK_START" ] && MAP_IS_NEW=true
    MAP_SIZE_KB=$(du -k "$MAP_FILE" 2>/dev/null | cut -f1)
fi

# --- 2. Check Metrics CSV ---
METRICS_FILE="$OUTPUT_DIR/sdm_metrics.csv"
METRICS_EXISTS=false
AUC_VALUE=0

if [ -f "$METRICS_FILE" ]; then
    METRICS_EXISTS=true
    # Extract AUC value using python (handles various CSV formats robustly)
    AUC_VALUE=$(python3 -c "
import pandas as pd
try:
    df = pd.read_csv('$METRICS_FILE')
    # Find column containing 'auc' (case insensitive)
    auc_col = [c for c in df.columns if 'auc' in c.lower()]
    if auc_col:
        print(df[auc_col[0]].iloc[0])
    else:
        print(0)
except:
    print(0)
" 2>/dev/null)
fi

# --- 3. Check Variable Importance CSV ---
VAR_IMP_FILE="$OUTPUT_DIR/var_importance.csv"
VAR_IMP_EXISTS=false
VAR_IMP_ROWS=0

if [ -f "$VAR_IMP_FILE" ]; then
    VAR_IMP_EXISTS=true
    VAR_IMP_ROWS=$(wc -l < "$VAR_IMP_FILE" 2>/dev/null || echo "0")
fi

# --- 4. Check Script & Packages ---
SCRIPT_MODIFIED=false
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    [ "$SCRIPT_MTIME" -gt "$TASK_START" ] && SCRIPT_MODIFIED=true
fi

# Check if required packages are installed in the user library
PACKAGES_INSTALLED=false
# We check user library explicitly
if [ -d "/home/ga/R/library/dismo" ] && [ -d "/home/ga/R/library/randomForest" ]; then
    PACKAGES_INSTALLED=true
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "map_exists": $MAP_EXISTS,
    "map_is_new": $MAP_IS_NEW,
    "map_size_kb": $MAP_SIZE_KB,
    "metrics_exists": $METRICS_EXISTS,
    "auc_value": $AUC_VALUE,
    "var_imp_exists": $VAR_IMP_EXISTS,
    "var_imp_rows": $VAR_IMP_ROWS,
    "script_modified": $SCRIPT_MODIFIED,
    "packages_installed": $PACKAGES_INSTALLED,
    "screenshot_path": "/tmp/task_end.png",
    "timestamp": "$(date -Iseconds)"
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