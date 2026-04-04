#!/bin/bash
echo "=== Exporting difficulty_accommodation_config result ==="

source /workspace/scripts/task_utils.sh

REPORT_FILE="/home/ga/Desktop/accommodation_plan.txt"
CONFIG_FILE="/home/ga/.config/gcompris-qt/gcompris-qt.conf"
TASK_START=$(cat /tmp/task_start_ts_difficulty_config 2>/dev/null || echo "0")

# Kill GCompris gracefully first so it flushes its config to disk
kill_gcompris
sleep 2

take_screenshot /tmp/difficulty_config_end.png

# Check report file
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_MTIME=0

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(wc -c < "$REPORT_FILE")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE")
fi

# Check GCompris config for difficulty filter change
CONFIG_FILTER_MAX=6
CONFIG_FILTER_MIN=1
CONFIG_EXISTS="false"

if [ -f "$CONFIG_FILE" ]; then
    CONFIG_EXISTS="true"
    # Read filterLevelMax value
    RAW_MAX=$(grep -i "filterlevelmax" "$CONFIG_FILE" 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1)
    if [ -n "$RAW_MAX" ]; then
        CONFIG_FILTER_MAX=$RAW_MAX
    fi
    RAW_MIN=$(grep -i "filterlevelmin" "$CONFIG_FILE" 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1)
    if [ -n "$RAW_MIN" ]; then
        CONFIG_FILTER_MIN=$RAW_MIN
    fi
fi

# Check report keywords
HAS_DIFFICULTY_KW=0
HAS_MATH_LIST=0
HAS_LANGUAGE_LIST=0
HAS_SCHEDULE=0
HAS_LEVEL_KW=0
HAS_ACCESSIBLE_KW=0

if [ "$REPORT_EXISTS" = "true" ]; then
    grep -qiE "difficulty|level|filter|setting" "$REPORT_FILE" 2>/dev/null && HAS_DIFFICULTY_KW=1
    grep -qiE "math|arithmetic|addition|number|numeration|count" "$REPORT_FILE" 2>/dev/null && HAS_MATH_LIST=1
    grep -qiE "language|letter|alphabet|word|reading|literacy|keyboard" "$REPORT_FILE" 2>/dev/null && HAS_LANGUAGE_LIST=1
    grep -qiE "schedule|daily|weekly|monday|tuesday|day|session|plan" "$REPORT_FILE" 2>/dev/null && HAS_SCHEDULE=1
    grep -qiE "\blevel [0-9]\|difficulty [0-9]\|level:[[:space:]]*[0-9]\|max.*[0-9]\|[0-9].*max" "$REPORT_FILE" 2>/dev/null && HAS_LEVEL_KW=1
    grep -qiE "accessible|accomodation\|accommodation\|special\|individual\|marcus\|student" "$REPORT_FILE" 2>/dev/null && HAS_ACCESSIBLE_KW=1
fi

python3 << PYEOF
import json

task_start = int("$TASK_START")
report_mtime = int("$REPORT_MTIME")
config_filter_max = int("$CONFIG_FILTER_MAX")

result = {
    "task_start": task_start,
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_size": int("$REPORT_SIZE"),
    "report_modified_after_start": int(report_mtime) > task_start,
    "has_difficulty_keyword": $HAS_DIFFICULTY_KW == 1,
    "has_math_list": $HAS_MATH_LIST == 1,
    "has_language_list": $HAS_LANGUAGE_LIST == 1,
    "has_schedule": $HAS_SCHEDULE == 1,
    "has_level_keyword": $HAS_LEVEL_KW == 1,
    "has_accessible_keyword": $HAS_ACCESSIBLE_KW == 1,
    "config_exists": "$CONFIG_EXISTS" == "true",
    "config_filter_max": config_filter_max,
    "config_filter_min": int("$CONFIG_FILTER_MIN"),
    "config_max_reduced": config_filter_max < 6,
    "config_max_at_target": config_filter_max <= 3,
}

with open("/tmp/difficulty_accommodation_config_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Config filterLevelMax={config_filter_max} (default was 6)")
print("Result JSON written to /tmp/difficulty_accommodation_config_result.json")
PYEOF

echo "=== Export complete ==="
