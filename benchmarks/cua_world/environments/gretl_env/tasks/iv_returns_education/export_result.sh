#!/bin/bash
echo "=== Exporting iv_returns_education result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot "/tmp/iv_returns_education_final.png"

OUTPUT_FILE="/home/ga/Documents/gretl_output/iv_wage_results.txt"

# Check file existence and get metadata
FILE_EXISTS="false"
FILE_SIZE=0
FILE_MTIME=0
FILE_CREATED_AFTER_START="false"
FILE_CONTENT=""

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(wc -c < "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")

    # Check if created after task start
    START_TIME=$(head -1 /tmp/iv_returns_education_start 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$START_TIME" ] 2>/dev/null; then
        FILE_CREATED_AFTER_START="true"
    fi

    # Read file content (cap at 8KB to avoid huge JSON)
    FILE_CONTENT=$(head -c 8192 "$OUTPUT_FILE" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr '\n' '|' | tr '\r' ' ')
fi

# Check for key econometric keywords in output
HAS_OLS="false"
HAS_2SLS="false"
HAS_HAUSMAN="false"
HAS_EDUC_COEFF="false"

if [ "$FILE_EXISTS" = "true" ]; then
    if grep -qiE "OLS|ordinary least squares|least squares" "$OUTPUT_FILE" 2>/dev/null; then
        HAS_OLS="true"
    fi
    if grep -qiE "2SLS|TSLS|two.stage|instrumental|tsls|IV estimation|tsls" "$OUTPUT_FILE" 2>/dev/null; then
        HAS_2SLS="true"
    fi
    if grep -qiE "hausman|endogeneity|wu.hausman|endogenous" "$OUTPUT_FILE" 2>/dev/null; then
        HAS_HAUSMAN="true"
    fi
    if grep -qiE "educ" "$OUTPUT_FILE" 2>/dev/null; then
        HAS_EDUC_COEFF="true"
    fi
fi

# Read baseline state
BASELINE_EXISTS=$(cut -d' ' -f1 /tmp/iv_baseline_state 2>/dev/null || echo "false")
BASELINE_SIZE=$(cut -d' ' -f2 /tmp/iv_baseline_state 2>/dev/null || echo "0")

# Create result JSON
cat > /tmp/iv_returns_education_result.json << ENDJSON
{
  "task": "iv_returns_education",
  "output_file": "$OUTPUT_FILE",
  "file_exists": $FILE_EXISTS,
  "file_size": $FILE_SIZE,
  "file_mtime": $FILE_MTIME,
  "file_created_after_start": $FILE_CREATED_AFTER_START,
  "baseline_existed": $BASELINE_EXISTS,
  "baseline_size": $BASELINE_SIZE,
  "has_ols": $HAS_OLS,
  "has_2sls": $HAS_2SLS,
  "has_hausman": $HAS_HAUSMAN,
  "has_educ_coeff": $HAS_EDUC_COEFF,
  "file_content_preview": "$FILE_CONTENT"
}
ENDJSON

echo "Result JSON written to /tmp/iv_returns_education_result.json"
echo "File exists: $FILE_EXISTS"
echo "File size: $FILE_SIZE bytes"
echo "Has OLS: $HAS_OLS"
echo "Has 2SLS: $HAS_2SLS"
echo "Has Hausman: $HAS_HAUSMAN"
echo "=== Export Complete ==="
