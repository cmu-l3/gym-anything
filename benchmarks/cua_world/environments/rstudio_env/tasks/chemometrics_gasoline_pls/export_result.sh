#!/bin/bash
echo "=== Exporting Chemometrics PLS Result ==="

source /workspace/scripts/task_utils.sh

# Capture final state screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/RProjects/output"
SCRIPT_PATH="/home/ga/RProjects/chemometrics_analysis.R"

# Initialize variables
CV_EXISTS="false"
PRED_EXISTS="false"
LOADINGS_EXISTS="false"
SCATTER_EXISTS="false"
SCRIPT_EXISTS="false"
SCRIPT_MODIFIED="false"
PLS_INSTALLED="false"

# Check CV Performance CSV
if [ -f "$OUTPUT_DIR/pls_cv_performance.csv" ]; then
    CV_MTIME=$(stat -c %Y "$OUTPUT_DIR/pls_cv_performance.csv" 2>/dev/null || echo "0")
    if [ "$CV_MTIME" -gt "$TASK_START" ]; then
        CV_EXISTS="true"
    fi
fi

# Check Predictions CSV
if [ -f "$OUTPUT_DIR/test_set_predictions.csv" ]; then
    PRED_MTIME=$(stat -c %Y "$OUTPUT_DIR/test_set_predictions.csv" 2>/dev/null || echo "0")
    if [ "$PRED_MTIME" -gt "$TASK_START" ]; then
        PRED_EXISTS="true"
    fi
fi

# Check Loadings Plot
if [ -f "$OUTPUT_DIR/spectral_loadings.png" ]; then
    IMG_MTIME=$(stat -c %Y "$OUTPUT_DIR/spectral_loadings.png" 2>/dev/null || echo "0")
    IMG_SIZE=$(stat -c %s "$OUTPUT_DIR/spectral_loadings.png" 2>/dev/null || echo "0")
    if [ "$IMG_MTIME" -gt "$TASK_START" ] && [ "$IMG_SIZE" -gt 1000 ]; then
        LOADINGS_EXISTS="true"
    fi
fi

# Check Scatter Plot
if [ -f "$OUTPUT_DIR/pred_vs_measured.png" ]; then
    IMG_MTIME=$(stat -c %Y "$OUTPUT_DIR/pred_vs_measured.png" 2>/dev/null || echo "0")
    IMG_SIZE=$(stat -c %s "$OUTPUT_DIR/pred_vs_measured.png" 2>/dev/null || echo "0")
    if [ "$IMG_MTIME" -gt "$TASK_START" ] && [ "$IMG_SIZE" -gt 1000 ]; then
        SCATTER_EXISTS="true"
    fi
fi

# Check Script
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
fi

# Check if 'pls' is installed
PLS_CHECK=$(R --vanilla --slave -e "cat(requireNamespace('pls', quietly=TRUE))" 2>/dev/null)
if [ "$PLS_CHECK" == "TRUE" ]; then
    PLS_INSTALLED="true"
fi

# Copy CSVs to temp for safe reading by python
cp "$OUTPUT_DIR/test_set_predictions.csv" /tmp/pred_data.csv 2>/dev/null || true
cp "$OUTPUT_DIR/pls_cv_performance.csv" /tmp/cv_data.csv 2>/dev/null || true
chmod 644 /tmp/pred_data.csv /tmp/cv_data.csv 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "cv_exists": $CV_EXISTS,
    "pred_exists": $PRED_EXISTS,
    "loadings_exists": $LOADINGS_EXISTS,
    "scatter_exists": $SCATTER_EXISTS,
    "script_exists": $SCRIPT_EXISTS,
    "script_modified": $SCRIPT_MODIFIED,
    "pls_installed": $PLS_INSTALLED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="