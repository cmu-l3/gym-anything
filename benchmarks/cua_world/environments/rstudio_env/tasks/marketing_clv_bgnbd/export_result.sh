#!/bin/bash
echo "=== Exporting Marketing CLV Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
take_screenshot /tmp/task_end.png

# Paths
CSV_PATH="/home/ga/RProjects/output/customer_predictions.csv"
PLOT_PATH="/home/ga/RProjects/output/frequency_plot.png"
PARAMS_PATH="/home/ga/RProjects/output/model_params.txt"
SCRIPT_PATH="/home/ga/RProjects/clv_analysis.R"

# 1. Check CSV
CSV_EXISTS="false"
CSV_IS_NEW="false"
CSV_ROW_COUNT=0
CSV_COLS=""
MAX_PREDICTION=0

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        CSV_IS_NEW="true"
    fi
    CSV_ROW_COUNT=$(wc -l < "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_COLS=$(head -1 "$CSV_PATH" 2>/dev/null)
    
    # Try to extract max prediction using python (robust csv parsing)
    MAX_PREDICTION=$(python3 -c "
import pandas as pd
try:
    df = pd.read_csv('$CSV_PATH')
    # Find column resembling expected transactions
    cols = [c for c in df.columns if 'expected' in c.lower() or 'pred' in c.lower()]
    if cols:
        print(df[cols[0]].max())
    else:
        print(0)
except:
    print(0)
" 2>/dev/null || echo "0")
fi

# 2. Check Plot
PLOT_EXISTS="false"
PLOT_IS_NEW="false"
PLOT_SIZE_KB=0

if [ -f "$PLOT_PATH" ]; then
    PLOT_EXISTS="true"
    MTIME=$(stat -c %Y "$PLOT_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        PLOT_IS_NEW="true"
    fi
    PLOT_SIZE_KB=$(du -k "$PLOT_PATH" 2>/dev/null | cut -f1)
fi

# 3. Check Params
PARAMS_EXISTS="false"
PARAMS_CONTENT=""

if [ -f "$PARAMS_PATH" ]; then
    PARAMS_EXISTS="true"
    PARAMS_CONTENT=$(cat "$PARAMS_PATH" | tr '\n' ' ')
fi

# 4. Check Script
SCRIPT_MODIFIED="false"
if [ -f "$SCRIPT_PATH" ]; then
    MTIME=$(stat -c %Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_cols": "$CSV_COLS",
    "max_prediction": $MAX_PREDICTION,
    "plot_exists": $PLOT_EXISTS,
    "plot_is_new": $PLOT_IS_NEW,
    "plot_size_kb": $PLOT_SIZE_KB,
    "params_exists": $PARAMS_EXISTS,
    "params_content": "$PARAMS_CONTENT",
    "script_modified": $SCRIPT_MODIFIED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="