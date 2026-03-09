#!/bin/bash
echo "=== Exporting cointegration_income_consumption result ==="

source /workspace/scripts/task_utils.sh

take_screenshot "/tmp/cointegration_final.png"

OUTPUT_FILE="/home/ga/Documents/gretl_output/cointegration_results.txt"

FILE_EXISTS="false"
FILE_SIZE=0
FILE_MTIME=0
FILE_CREATED_AFTER_START="false"

HAS_ADF="false"
HAS_UNIT_ROOT="false"
HAS_COINT_REG="false"
HAS_ENGLE_GRANGER="false"
HAS_RESIDUAL_TEST="false"
HAS_LOG_TRANSFORM="false"

PCEC96_OK=$(cut -d' ' -f1 /tmp/cointegration_data_state 2>/dev/null || echo "false")
DSPIC96_OK=$(cut -d' ' -f2 /tmp/cointegration_data_state 2>/dev/null || echo "false")

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(wc -c < "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")

    START_TIME=$(head -1 /tmp/cointegration_start 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$START_TIME" ] 2>/dev/null; then
        FILE_CREATED_AFTER_START="true"
    fi

    if grep -qiE "ADF|Augmented Dickey.Fuller|Dickey.Fuller" "$OUTPUT_FILE" 2>/dev/null; then
        HAS_ADF="true"
    fi
    if grep -qiE "unit.root|I\(1\)|integrated|stationary" "$OUTPUT_FILE" 2>/dev/null; then
        HAS_UNIT_ROOT="true"
    fi
    if grep -qiE "OLS|least squares|cointegrat.*regress|long.run" "$OUTPUT_FILE" 2>/dev/null; then
        HAS_COINT_REG="true"
    fi
    if grep -qiE "engle.granger|EG.test|cointegration test|ADF.*resid|resid.*ADF|resid.*unit.root|unit.root.*resid" "$OUTPUT_FILE" 2>/dev/null; then
        HAS_ENGLE_GRANGER="true"
    fi
    if grep -qiE "residual|error.correct|ECM|uhat" "$OUTPUT_FILE" 2>/dev/null; then
        HAS_RESIDUAL_TEST="true"
    fi
    if grep -qiE "lcons|linc|log.*cons|log.*inc|lPCEC|lDSPIC" "$OUTPUT_FILE" 2>/dev/null; then
        HAS_LOG_TRANSFORM="true"
    fi
fi

BASELINE_EXISTS=$(cut -d' ' -f1 /tmp/cointegration_baseline_state 2>/dev/null || echo "false")
BASELINE_SIZE=$(cut -d' ' -f2 /tmp/cointegration_baseline_state 2>/dev/null || echo "0")

cat > /tmp/cointegration_result.json << ENDJSON
{
  "task": "cointegration_income_consumption",
  "output_file": "$OUTPUT_FILE",
  "file_exists": $FILE_EXISTS,
  "file_size": $FILE_SIZE,
  "file_mtime": $FILE_MTIME,
  "file_created_after_start": $FILE_CREATED_AFTER_START,
  "baseline_existed": $BASELINE_EXISTS,
  "baseline_size": $BASELINE_SIZE,
  "pcec96_downloaded": $PCEC96_OK,
  "dspic96_downloaded": $DSPIC96_OK,
  "has_adf": $HAS_ADF,
  "has_unit_root": $HAS_UNIT_ROOT,
  "has_coint_reg": $HAS_COINT_REG,
  "has_engle_granger": $HAS_ENGLE_GRANGER,
  "has_residual_test": $HAS_RESIDUAL_TEST,
  "has_log_transform": $HAS_LOG_TRANSFORM
}
ENDJSON

echo "Result JSON written to /tmp/cointegration_result.json"
echo "ADF: $HAS_ADF | Unit root: $HAS_UNIT_ROOT | Coint reg: $HAS_COINT_REG"
echo "Engle-Granger: $HAS_ENGLE_GRANGER | Residual test: $HAS_RESIDUAL_TEST"
echo "=== Export Complete ==="
