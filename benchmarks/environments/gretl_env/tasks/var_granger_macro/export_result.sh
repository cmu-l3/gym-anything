#!/bin/bash
echo "=== Exporting var_granger_macro result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot "/tmp/var_granger_macro_final.png"

OUTPUT_FILE="/home/ga/Documents/gretl_output/var_macro_results.txt"

FILE_EXISTS="false"
FILE_SIZE=0
FILE_MTIME=0
FILE_CREATED_AFTER_START="false"

HAS_VAR="false"
HAS_LAG_SELECTION="false"
HAS_GRANGER="false"
HAS_IRF="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(wc -c < "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")

    START_TIME=$(head -1 /tmp/var_granger_macro_start 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$START_TIME" ] 2>/dev/null; then
        FILE_CREATED_AFTER_START="true"
    fi

    # Check keyword presence
    if grep -qiE "VAR|vector autoregression|vector auto-regression" "$OUTPUT_FILE" 2>/dev/null; then
        HAS_VAR="true"
    fi
    if grep -qiE "AIC|BIC|HQC|Hannan|Schwarz|lag order|lag selection|information criterion" "$OUTPUT_FILE" 2>/dev/null; then
        HAS_LAG_SELECTION="true"
    fi
    if grep -qiE "granger|causality|wald|chi.square|F-stat" "$OUTPUT_FILE" 2>/dev/null; then
        HAS_GRANGER="true"
    fi
    if grep -qiE "impulse|IRF|orthogonalized|response|shock" "$OUTPUT_FILE" 2>/dev/null; then
        HAS_IRF="true"
    fi
fi

BASELINE_EXISTS=$(cut -d' ' -f1 /tmp/var_baseline_state 2>/dev/null || echo "false")
BASELINE_SIZE=$(cut -d' ' -f2 /tmp/var_baseline_state 2>/dev/null || echo "0")

cat > /tmp/var_granger_macro_result.json << ENDJSON
{
  "task": "var_granger_macro",
  "output_file": "$OUTPUT_FILE",
  "file_exists": $FILE_EXISTS,
  "file_size": $FILE_SIZE,
  "file_mtime": $FILE_MTIME,
  "file_created_after_start": $FILE_CREATED_AFTER_START,
  "baseline_existed": $BASELINE_EXISTS,
  "baseline_size": $BASELINE_SIZE,
  "has_var": $HAS_VAR,
  "has_lag_selection": $HAS_LAG_SELECTION,
  "has_granger": $HAS_GRANGER,
  "has_irf": $HAS_IRF
}
ENDJSON

echo "Result JSON written to /tmp/var_granger_macro_result.json"
echo "File exists: $FILE_EXISTS | Size: $FILE_SIZE"
echo "VAR: $HAS_VAR | Lag selection: $HAS_LAG_SELECTION | Granger: $HAS_GRANGER | IRF: $HAS_IRF"
echo "=== Export Complete ==="
