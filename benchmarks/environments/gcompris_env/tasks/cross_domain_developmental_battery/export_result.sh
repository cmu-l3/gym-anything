#!/bin/bash
echo "=== Exporting cross_domain_developmental_battery result ==="

source /workspace/scripts/task_utils.sh

REPORT_FILE="/home/ga/Desktop/developmental_assessment_battery.txt"
TASK_START=$(cat /tmp/task_start_ts_dev_battery 2>/dev/null || echo "0")

take_screenshot /tmp/dev_battery_end.png

REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_MTIME=0

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(wc -c < "$REPORT_FILE")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE")
fi

# Math domain keywords
HAS_MATH_KW=0
# Language domain keywords
HAS_LANG_KW=0
# Science domain keywords
HAS_SCI_KW=0
# Games domain keywords
HAS_GAME_KW=0

# Specific activity name keywords
HAS_ADDITION=0
HAS_ALPHABET=0
HAS_EXPERIMENT=0
HAS_MAZE=0
HAS_MEMORY=0
HAS_COLOR=0
HAS_GRAVITY=0

if [ "$REPORT_EXISTS" = "true" ]; then
    # Math domain
    grep -qiE "math|arithmetic|addition|subtraction|number|numeration|count|multiply|algebra" "$REPORT_FILE" 2>/dev/null && HAS_MATH_KW=1
    # Language domain
    grep -qiE "language|letter|alphabet|word|reading|literacy|vocabulary|keyboard|uppercase|lowercase" "$REPORT_FILE" 2>/dev/null && HAS_LANG_KW=1
    # Science domain
    grep -qiE "science|experiment|color|colour|gravity|watercycle|mixing|canal|binary|farm" "$REPORT_FILE" 2>/dev/null && HAS_SCI_KW=1
    # Games domain
    grep -qiE "game|maze|memory|puzzle|spatial|logical|hexagon|football|programming" "$REPORT_FILE" 2>/dev/null && HAS_GAME_KW=1

    # Specific activity names
    grep -qi "addition\|additions" "$REPORT_FILE" 2>/dev/null && HAS_ADDITION=1
    grep -qi "alphabet" "$REPORT_FILE" 2>/dev/null && HAS_ALPHABET=1
    grep -qi "experiment\|science" "$REPORT_FILE" 2>/dev/null && HAS_EXPERIMENT=1
    grep -qi "\bmaze\b" "$REPORT_FILE" 2>/dev/null && HAS_MAZE=1
    grep -qi "memory" "$REPORT_FILE" 2>/dev/null && HAS_MEMORY=1
    grep -qi "color\|colour\|mixing" "$REPORT_FILE" 2>/dev/null && HAS_COLOR=1
    grep -qi "gravity\|watercycle\|water" "$REPORT_FILE" 2>/dev/null && HAS_GRAVITY=1
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
    "has_math_domain": $HAS_MATH_KW == 1,
    "has_language_domain": $HAS_LANG_KW == 1,
    "has_science_domain": $HAS_SCI_KW == 1,
    "has_games_domain": $HAS_GAME_KW == 1,
    "has_addition_keyword": $HAS_ADDITION == 1,
    "has_alphabet_keyword": $HAS_ALPHABET == 1,
    "has_experiment_keyword": $HAS_EXPERIMENT == 1,
    "has_maze_keyword": $HAS_MAZE == 1,
    "has_memory_keyword": $HAS_MEMORY == 1,
    "has_color_keyword": $HAS_COLOR == 1,
    "has_gravity_keyword": $HAS_GRAVITY == 1,
}

with open("/tmp/cross_domain_developmental_battery_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result JSON written to /tmp/cross_domain_developmental_battery_result.json")
PYEOF

echo "=== Export complete ==="
