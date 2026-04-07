#!/bin/bash
echo "=== Exporting Meuse Kriging Results ==="

# Define paths
OUTPUT_DIR="/home/ga/RProjects/output"
TASK_START_FILE="/tmp/task_start_time.txt"
RESULT_JSON="/tmp/task_result.json"
TASK_START=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")

# Helper function to get file size
get_size() {
    stat -c %s "$1" 2>/dev/null || echo "0"
}

# Helper function to check if file modified after start
is_new() {
    local f="$1"
    if [ ! -f "$f" ]; then echo "false"; return; fi
    local mtime=$(stat -c %Y "$f")
    if [ "$mtime" -gt "$TASK_START" ]; then echo "true"; else echo "false"; fi
}

# 1. Inspect Variogram CSV
VARIO_CSV="$OUTPUT_DIR/meuse_variogram_model.csv"
VARIO_EXISTS=$( [ -f "$VARIO_CSV" ] && echo "true" || echo "false" )
VARIO_NEW=$(is_new "$VARIO_CSV")
VARIO_INFO=$(python3 -c "
import pandas as pd, json, sys
try:
    df = pd.read_csv('$VARIO_CSV')
    # Check for required columns
    cols = [c.lower() for c in df.columns]
    req = ['model', 'range', 'nugget']
    has_cols = all(any(r in c for c in cols) for r in req)
    rows = len(df)
    # Get best model parameters (assuming first row or valid row)
    nugget = float(df['nugget'].iloc[0]) if 'nugget' in df.columns else 0
    rng = float(df['range'].iloc[0]) if 'range' in df.columns else 0
    print(json.dumps({'valid': True, 'rows': rows, 'has_cols': has_cols, 'nugget': nugget, 'range': rng}))
except:
    print(json.dumps({'valid': False, 'rows': 0, 'has_cols': False}))
")

# 2. Inspect Kriging Predictions CSV
PRED_CSV="$OUTPUT_DIR/meuse_kriging_predictions.csv"
PRED_EXISTS=$( [ -f "$PRED_CSV" ] && echo "true" || echo "false" )
PRED_NEW=$(is_new "$PRED_CSV")
PRED_INFO=$(python3 -c "
import pandas as pd, json
try:
    df = pd.read_csv('$PRED_CSV')
    rows = len(df)
    cols = [c.lower() for c in df.columns]
    has_pred = any('pred' in c for c in cols)
    has_var = any('var' in c for c in cols)
    print(json.dumps({'rows': rows, 'has_pred': has_pred, 'has_var': has_var}))
except:
    print(json.dumps({'rows': 0, 'has_pred': False, 'has_var': False}))
")

# 3. Inspect CV Results CSV
CV_CSV="$OUTPUT_DIR/meuse_cv_results.csv"
CV_EXISTS=$( [ -f "$CV_CSV" ] && echo "true" || echo "false" )
CV_NEW=$(is_new "$CV_CSV")
CV_INFO=$(python3 -c "
import pandas as pd, json, numpy as np
try:
    df = pd.read_csv('$CV_CSV')
    rows = len(df)
    # Calculate simple residual stats
    cols = [c.lower() for c in df.columns]
    resid_col = next((c for c in cols if 'residual' in c), None)
    mean_resid = 999
    if resid_col:
        mean_resid = df[resid_col].mean()
    print(json.dumps({'rows': rows, 'mean_residual': mean_resid}))
except:
    print(json.dumps({'rows': 0, 'mean_residual': 999}))
")

# 4. Inspect Map Image
MAP_PNG="$OUTPUT_DIR/meuse_kriging_maps.png"
MAP_EXISTS=$( [ -f "$MAP_PNG" ] && echo "true" || echo "false" )
MAP_NEW=$(is_new "$MAP_PNG")
MAP_SIZE=$(get_size "$MAP_PNG")

# 5. Inspect R Script
SCRIPT_R="/home/ga/RProjects/meuse_kriging_analysis.R"
SCRIPT_EXISTS=$( [ -f "$SCRIPT_R" ] && echo "true" || echo "false" )
SCRIPT_NEW=$(is_new "$SCRIPT_R")
SCRIPT_CONTENT_CHECK=$(grep -E "variogram|krige|fit\.variogram" "$SCRIPT_R" > /dev/null && echo "true" || echo "false")

# 6. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 7. Compile JSON result
cat > "$RESULT_JSON" << EOF
{
  "variogram": {
    "exists": $VARIO_EXISTS,
    "is_new": $VARIO_NEW,
    "info": $VARIO_INFO
  },
  "predictions": {
    "exists": $PRED_EXISTS,
    "is_new": $PRED_NEW,
    "info": $PRED_INFO
  },
  "cv": {
    "exists": $CV_EXISTS,
    "is_new": $CV_NEW,
    "info": $CV_INFO
  },
  "map": {
    "exists": $MAP_EXISTS,
    "is_new": $MAP_NEW,
    "size": $MAP_SIZE
  },
  "script": {
    "exists": $SCRIPT_EXISTS,
    "is_new": $SCRIPT_NEW,
    "has_keywords": $SCRIPT_CONTENT_CHECK
  },
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions for the JSON so verifier can read it
chmod 666 "$RESULT_JSON"

echo "Export complete. Result JSON:"
cat "$RESULT_JSON"