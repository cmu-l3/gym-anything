#!/bin/bash
echo "=== Exporting panel_wage_hausman result ==="

source /workspace/scripts/task_utils.sh

take_screenshot "/tmp/panel_wage_hausman_final.png"

OUTPUT_FILE="/home/ga/Documents/gretl_output/panel_results.txt"

FILE_EXISTS="false"
FILE_SIZE=0
FILE_MTIME=0
FILE_CREATED_AFTER_START="false"

HAS_OLS="false"
HAS_FE="false"
HAS_RE="false"
HAS_HAUSMAN="false"
HAS_PANEL_KEYWORDS="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(wc -c < "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")

    START_TIME=$(head -1 /tmp/panel_wage_hausman_start 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$START_TIME" ] 2>/dev/null; then
        FILE_CREATED_AFTER_START="true"
    fi

    if grep -qiE "OLS|ordinary least squares|pooled" "$OUTPUT_FILE" 2>/dev/null; then
        HAS_OLS="true"
    fi
    if grep -qiE "fixed.effect|within estimator|FE model|between estimator" "$OUTPUT_FILE" 2>/dev/null; then
        HAS_FE="true"
    fi
    if grep -qiE "random.effect|GLS|EGLS|RE model|random effects" "$OUTPUT_FILE" 2>/dev/null; then
        HAS_RE="true"
    fi
    if grep -qiE "hausman|specification test|fe.*vs.*re|re.*vs.*fe" "$OUTPUT_FILE" 2>/dev/null; then
        HAS_HAUSMAN="true"
    fi
    if grep -qiE "panel|within|between" "$OUTPUT_FILE" 2>/dev/null; then
        HAS_PANEL_KEYWORDS="true"
    fi
fi

BASELINE_EXISTS=$(cut -d' ' -f1 /tmp/panel_baseline_state 2>/dev/null || echo "false")
BASELINE_SIZE=$(cut -d' ' -f2 /tmp/panel_baseline_state 2>/dev/null || echo "0")

cat > /tmp/panel_wage_hausman_result.json << ENDJSON
{
  "task": "panel_wage_hausman",
  "output_file": "$OUTPUT_FILE",
  "file_exists": $FILE_EXISTS,
  "file_size": $FILE_SIZE,
  "file_mtime": $FILE_MTIME,
  "file_created_after_start": $FILE_CREATED_AFTER_START,
  "baseline_existed": $BASELINE_EXISTS,
  "baseline_size": $BASELINE_SIZE,
  "has_ols": $HAS_OLS,
  "has_fe": $HAS_FE,
  "has_re": $HAS_RE,
  "has_hausman": $HAS_HAUSMAN,
  "has_panel_keywords": $HAS_PANEL_KEYWORDS
}
ENDJSON

echo "Result JSON written to /tmp/panel_wage_hausman_result.json"
echo "OLS: $HAS_OLS | FE: $HAS_FE | RE: $HAS_RE | Hausman: $HAS_HAUSMAN"
echo "=== Export Complete ==="
