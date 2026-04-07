#!/bin/bash
echo "=== Exporting PBS Drug Forecasting Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/RProjects/output"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize results
DECOMP_EXISTS="false"
ACCURACY_EXISTS="false"
FORECAST_EXISTS="false"
PLOT_EXISTS="false"
FORECAST_ROWS=0
FORECAST_MEAN_VAL=0
ACCURACY_MODELS_COUNT=0

# Check Decomposition Plot
if [ -f "$OUTPUT_DIR/l01_decomposition.png" ]; then
    MTIME=$(stat -c %Y "$OUTPUT_DIR/l01_decomposition.png")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        DECOMP_EXISTS="true"
    fi
fi

# Check Forecast Plot
if [ -f "$OUTPUT_DIR/l01_forecast_plot.png" ]; then
    MTIME=$(stat -c %Y "$OUTPUT_DIR/l01_forecast_plot.png")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        PLOT_EXISTS="true"
    fi
fi

# Check Accuracy CSV
if [ -f "$OUTPUT_DIR/l01_model_accuracy.csv" ]; then
    MTIME=$(stat -c %Y "$OUTPUT_DIR/l01_model_accuracy.csv")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        ACCURACY_EXISTS="true"
        # Count non-header rows
        ACCURACY_MODELS_COUNT=$(awk 'NR>1 {count++} END {print count}' "$OUTPUT_DIR/l01_model_accuracy.csv")
    fi
fi

# Check Forecast Values CSV
if [ -f "$OUTPUT_DIR/l01_forecast_values.csv" ]; then
    MTIME=$(stat -c %Y "$OUTPUT_DIR/l01_forecast_values.csv")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FORECAST_EXISTS="true"
        
        # Analyze CSV content using Python
        # We check:
        # 1. Number of rows (should be around 36)
        # 2. Mean value of the forecast (should be > 100,000 if aggregated correctly, much smaller if not)
        
        PYTHON_ANALYSIS=$(python3 -c "
import pandas as pd
import sys
try:
    df = pd.read_csv('$OUTPUT_DIR/l01_forecast_values.csv')
    rows = len(df)
    
    # Identify forecast column: usually '.mean', 'Scripts', or 'value'
    # Fable outputs '.mean' by default for point forecasts
    target_col = None
    for col in ['.mean', 'Scripts', 'value', 'mean']:
        if col in df.columns:
            target_col = col
            break
            
    if target_col:
        avg_val = df[target_col].mean()
    else:
        # Fallback: try last numeric column
        num_cols = df.select_dtypes(include=['number']).columns
        if len(num_cols) > 0:
            avg_val = df[num_cols[-1]].mean()
        else:
            avg_val = 0
            
    print(f'{rows} {avg_val}')
except Exception as e:
    print('0 0')
")
        FORECAST_ROWS=$(echo "$PYTHON_ANALYSIS" | awk '{print $1}')
        FORECAST_MEAN_VAL=$(echo "$PYTHON_ANALYSIS" | awk '{print $2}')
    fi
fi

# Check if script was modified
SCRIPT_MODIFIED="false"
if [ -f "/home/ga/RProjects/forecast_analysis.R" ]; then
    MTIME=$(stat -c %Y "/home/ga/RProjects/forecast_analysis.R")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "decomp_plot_exists": $DECOMP_EXISTS,
    "forecast_plot_exists": $PLOT_EXISTS,
    "accuracy_csv_exists": $ACCURACY_EXISTS,
    "accuracy_models_count": $ACCURACY_MODELS_COUNT,
    "forecast_csv_exists": $FORECAST_EXISTS,
    "forecast_rows": $FORECAST_ROWS,
    "forecast_mean_val": $FORECAST_MEAN_VAL,
    "script_modified": $SCRIPT_MODIFIED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="