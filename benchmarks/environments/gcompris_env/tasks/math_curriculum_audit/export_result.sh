#!/bin/bash
echo "=== Exporting math_curriculum_audit result ==="

source /workspace/scripts/task_utils.sh

REPORT_FILE="/home/ga/Desktop/math_curriculum_audit.txt"
TASK_START=$(cat /tmp/task_start_ts_math_audit 2>/dev/null || echo "0")

take_screenshot /tmp/math_audit_end.png

# Check report file
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_MTIME=0

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(wc -c < "$REPORT_FILE")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE")
fi

# Check for section keywords (safe grep pattern — no grep -c || echo "0")
HAS_NUMERATION=0
HAS_ARITHMETIC=0
HAS_MEASURES=0
HAS_ADDITIONS=0
HAS_SUBTRACTION=0
HAS_COUNT=0
HAS_NUMBERS=0
HAS_ALGEBRA=0
HAS_WEIGHT=0

if [ "$REPORT_EXISTS" = "true" ]; then
    grep -qi "numeration" "$REPORT_FILE" 2>/dev/null && HAS_NUMERATION=1
    grep -qi "arithmetic" "$REPORT_FILE" 2>/dev/null && HAS_ARITHMETIC=1
    grep -qi "measures\|measure" "$REPORT_FILE" 2>/dev/null && HAS_MEASURES=1
    grep -qi "addition\|additions" "$REPORT_FILE" 2>/dev/null && HAS_ADDITIONS=1
    grep -qi "subtract\|subtraction\|substract" "$REPORT_FILE" 2>/dev/null && HAS_SUBTRACTION=1
    grep -qi "count\|counting" "$REPORT_FILE" 2>/dev/null && HAS_COUNT=1
    grep -qi "number\|numbers" "$REPORT_FILE" 2>/dev/null && HAS_NUMBERS=1
    grep -qi "algebra" "$REPORT_FILE" 2>/dev/null && HAS_ALGEBRA=1
    grep -qi "weight\|ruler\|length\|mass" "$REPORT_FILE" 2>/dev/null && HAS_WEIGHT=1
fi

python3 << PYEOF
import json

task_start = int("$TASK_START")
report_mtime = int("$REPORT_MTIME")

result = {
    "task_start": task_start,
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_size": int("$REPORT_SIZE"),
    "report_modified_after_start": int(report_mtime) > task_start,
    "has_numeration_section": $HAS_NUMERATION == 1,
    "has_arithmetic_section": $HAS_ARITHMETIC == 1,
    "has_measures_section": $HAS_MEASURES == 1,
    "has_additions_keyword": $HAS_ADDITIONS == 1,
    "has_subtraction_keyword": $HAS_SUBTRACTION == 1,
    "has_count_keyword": $HAS_COUNT == 1,
    "has_numbers_keyword": $HAS_NUMBERS == 1,
    "has_algebra_keyword": $HAS_ALGEBRA == 1,
    "has_weight_keyword": $HAS_WEIGHT == 1,
}

with open("/tmp/math_curriculum_audit_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result JSON written to /tmp/math_curriculum_audit_result.json")
PYEOF

echo "=== Export complete ==="
