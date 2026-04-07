#!/bin/bash
echo "=== Exporting predictive_maintenance_rul result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/rul_task_start_ts 2>/dev/null || echo "0")
take_screenshot /tmp/rul_task_end.png

PREDICTIONS_CSV="/home/ga/RProjects/output/rul_predictions.csv"
METRICS_CSV="/home/ga/RProjects/output/model_metrics.csv"
PLOT_PNG="/home/ga/RProjects/output/rul_performance_plot.png"
SCRIPT="/home/ga/RProjects/rul_analysis.R"

# --- Evaluate Script Quality & Feature Engineering ---
SCRIPT_EXISTS=false
SCRIPT_IS_NEW=false
HAS_ROLLING_FEATURES=false

if [ -f "$SCRIPT" ]; then
    SCRIPT_EXISTS=true
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT" 2>/dev/null || echo "0")
    [ "$SCRIPT_MTIME" -gt "$TASK_START" ] && SCRIPT_IS_NEW=true
    
    # Check for rolling functions
    CODE=$(grep -v '^\s*#' "$SCRIPT")
    echo "$CODE" | grep -qiE "rollmean|rollapply|slide|lag|zoo|frollmean" && HAS_ROLLING_FEATURES=true
fi

# --- Evaluate Output Artifacts ---
PREDS_EXIST=false
PREDS_IS_NEW=false
PREDS_ROW_COUNT=0
TRUE_RMSE=-1

if [ -f "$PREDICTIONS_CSV" ]; then
    PREDS_EXIST=true
    PREDS_MTIME=$(stat -c %Y "$PREDICTIONS_CSV" 2>/dev/null || echo "0")
    [ "$PREDS_MTIME" -gt "$TASK_START" ] && PREDS_IS_NEW=true
    PREDS_ROW_COUNT=$(awk 'END {print NR}' "$PREDICTIONS_CSV")

    # Use Python to accurately calculate TRUE RMSE (anti-gaming: verifies agent didn't just hardcode a fake metric)
    TRUE_RMSE=$(python3 << 'PYEOF'
import csv
import math
import os

preds_file = "/home/ga/RProjects/output/rul_predictions.csv"
true_rul_file = "/home/ga/RProjects/datasets/CMAPSS/RUL_FD001.txt"

if not os.path.exists(preds_file) or not os.path.exists(true_rul_file):
    print("-1")
    exit(0)

try:
    with open(true_rul_file, 'r') as f:
        true_rul = [float(line.strip()) for line in f if line.strip()]

    with open(preds_file, 'r') as f:
        reader = csv.DictReader(f)
        preds = []
        for row in reader:
            # Find Engine ID and Prediction columns dynamically
            eid_col = next((k for k in row.keys() if k and ('engine' in k.lower() or 'id' in k.lower())), None)
            pred_col = next((k for k in row.keys() if k and ('pred' in k.lower() or 'rul' in k.lower() and 'actual' not in k.lower())), None)
            
            if eid_col and pred_col and row[eid_col].strip() and row[pred_col].strip():
                try:
                    preds.append((int(float(row[eid_col])), float(row[pred_col])))
                except ValueError:
                    continue

    if not preds:
        print("-1")
        exit(0)

    # Sort by Engine ID
    preds.sort(key=lambda x: x[0])

    if len(preds) == len(true_rul):
        se = sum((p[1] - t)**2 for p, t in zip(preds, true_rul))
        rmse = math.sqrt(se / len(preds))
        print(f"{rmse:.4f}")
    else:
        print("-1")

except Exception as e:
    print("-1")
PYEOF
)
fi

METRICS_EXIST=false
METRICS_IS_NEW=false
if [ -f "$METRICS_CSV" ]; then
    METRICS_EXIST=true
    METRICS_MTIME=$(stat -c %Y "$METRICS_CSV" 2>/dev/null || echo "0")
    [ "$METRICS_MTIME" -gt "$TASK_START" ] && METRICS_IS_NEW=true
fi

PLOT_EXISTS=false
PLOT_IS_NEW=false
PLOT_SIZE_KB=0
if [ -f "$PLOT_PNG" ]; then
    PLOT_EXISTS=true
    PLOT_MTIME=$(stat -c %Y "$PLOT_PNG" 2>/dev/null || echo "0")
    [ "$PLOT_MTIME" -gt "$TASK_START" ] && PLOT_IS_NEW=true
    PLOT_SIZE_KB=$(du -k "$PLOT_PNG" 2>/dev/null | cut -f1)
fi

# Build result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "script_exists": $SCRIPT_EXISTS,
    "script_is_new": $SCRIPT_IS_NEW,
    "has_rolling_features": $HAS_ROLLING_FEATURES,
    "predictions_csv_exists": $PREDS_EXIST,
    "predictions_csv_is_new": $PREDS_IS_NEW,
    "predictions_row_count": $PREDS_ROW_COUNT,
    "true_rmse": $TRUE_RMSE,
    "metrics_csv_exists": $METRICS_EXIST,
    "metrics_csv_is_new": $METRICS_IS_NEW,
    "plot_png_exists": $PLOT_EXISTS,
    "plot_png_is_new": $PLOT_IS_NEW,
    "plot_size_kb": $PLOT_SIZE_KB,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/rul_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/rul_task_result.json
chmod 666 /tmp/rul_task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON written:"
cat /tmp/rul_task_result.json
echo "=== Export Complete ==="