#!/bin/bash
echo "=== Exporting cps_wage_diagnostics result ==="

source /workspace/scripts/task_utils.sh

take_screenshot "/tmp/cps_wage_diagnostics_final.png"

OUTPUT_FILE="/home/ga/Documents/gretl_output/wage_diagnostics.txt"

FILE_EXISTS="false"
FILE_SIZE=0
FILE_MTIME=0
FILE_CREATED_AFTER_START="false"

HAS_OLS="false"
HAS_RESET="false"
HAS_BP="false"
HAS_WHITE="false"
HAS_ROBUST="false"
HAS_LOG_WAGE="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(wc -c < "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")

    START_TIME=$(head -1 /tmp/cps_wage_diagnostics_start 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$START_TIME" ] 2>/dev/null; then
        FILE_CREATED_AFTER_START="true"
    fi

    if grep -qiE "OLS|ordinary least squares|least squares" "$OUTPUT_FILE" 2>/dev/null; then
        HAS_OLS="true"
    fi
    if grep -qiE "RESET|ramsey|specification error|auxiliary" "$OUTPUT_FILE" 2>/dev/null; then
        HAS_RESET="true"
    fi
    if grep -qiE "breusch.pagan|BP test|LM test.*hetero" "$OUTPUT_FILE" 2>/dev/null; then
        HAS_BP="true"
    fi
    if grep -qiE "white.*test|white.*hetero" "$OUTPUT_FILE" 2>/dev/null; then
        HAS_WHITE="true"
    fi
    if grep -qiE "robust|HC|heteroskedasticity.consistent|sandwich" "$OUTPUT_FILE" 2>/dev/null; then
        HAS_ROBUST="true"
    fi
    if grep -qiE "l_wage|lwage|log.*wage|ln.*wage|loge.*wage" "$OUTPUT_FILE" 2>/dev/null; then
        HAS_LOG_WAGE="true"
    fi
fi

BASELINE_EXISTS=$(cut -d' ' -f1 /tmp/cps_baseline_state 2>/dev/null || echo "false")
BASELINE_SIZE=$(cut -d' ' -f2 /tmp/cps_baseline_state 2>/dev/null || echo "0")

cat > /tmp/cps_wage_diagnostics_result.json << ENDJSON
{
  "task": "cps_wage_diagnostics",
  "output_file": "$OUTPUT_FILE",
  "file_exists": $FILE_EXISTS,
  "file_size": $FILE_SIZE,
  "file_mtime": $FILE_MTIME,
  "file_created_after_start": $FILE_CREATED_AFTER_START,
  "baseline_existed": $BASELINE_EXISTS,
  "baseline_size": $BASELINE_SIZE,
  "has_ols": $HAS_OLS,
  "has_reset": $HAS_RESET,
  "has_bp": $HAS_BP,
  "has_white": $HAS_WHITE,
  "has_robust": $HAS_ROBUST,
  "has_log_wage": $HAS_LOG_WAGE
}
ENDJSON

echo "Result JSON written to /tmp/cps_wage_diagnostics_result.json"
echo "OLS: $HAS_OLS | RESET: $HAS_RESET | BP: $HAS_BP | White: $HAS_WHITE | Robust: $HAS_ROBUST"
echo "=== Export Complete ==="
