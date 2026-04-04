#!/bin/bash
echo "=== Exporting science_experiment_catalog result ==="

source /workspace/scripts/task_utils.sh

REPORT_FILE="/home/ga/Desktop/science_curriculum_report.txt"
TASK_START=$(cat /tmp/task_start_ts_science_catalog 2>/dev/null || echo "0")

take_screenshot /tmp/science_catalog_end.png

REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_MTIME=0

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(wc -c < "$REPORT_FILE")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE")
fi

# Physics/gravity/water keywords
HAS_PHYSICS_KW=0
# Color/mixing/optics keywords
HAS_COLOR_KW=0
# Other science activity keywords
HAS_OTHER_SCI_KW=0
# NGSS/grade/recommendation content
HAS_CURRICULUM_KW=0
# Specific activity names
HAS_GRAVITY=0
HAS_WATERCYCLE=0
HAS_MIXING_PAINT=0
HAS_MIXING_LIGHT=0
HAS_CANAL=0
HAS_BINARY=0
HAS_FARM=0

if [ "$REPORT_EXISTS" = "true" ]; then
    grep -qiE "gravity|gravitational|gravit" "$REPORT_FILE" 2>/dev/null && HAS_GRAVITY=1
    grep -qiE "watercycle|water cycle|evaporation|condensation|precipitation|hydrological" "$REPORT_FILE" 2>/dev/null && HAS_WATERCYCLE=1
    grep -qiE "mixing paint|paint color|subtractive|cmy|cyan|magenta|yellow" "$REPORT_FILE" 2>/dev/null && HAS_MIXING_PAINT=1
    grep -qiE "mixing light|light color|additive|rgb|red.*green.*blue" "$REPORT_FILE" 2>/dev/null && HAS_MIXING_LIGHT=1
    grep -qiE "canal lock\|canal\|hydraulic\|lock" "$REPORT_FILE" 2>/dev/null && HAS_CANAL=1
    grep -qiE "binary bulb\|binary\|bulb" "$REPORT_FILE" 2>/dev/null && HAS_BINARY=1
    grep -qiE "farm animal\|farm\|animal" "$REPORT_FILE" 2>/dev/null && HAS_FARM=1

    # Physics domain (gravity OR watercycle OR canal)
    [ $HAS_GRAVITY -eq 1 ] || [ $HAS_WATERCYCLE -eq 1 ] || [ $HAS_CANAL -eq 1 ] && HAS_PHYSICS_KW=1
    # Color/optics domain
    [ $HAS_MIXING_PAINT -eq 1 ] || [ $HAS_MIXING_LIGHT -eq 1 ] && HAS_COLOR_KW=1
    # Other science
    [ $HAS_BINARY -eq 1 ] || [ $HAS_FARM -eq 1 ] && HAS_OTHER_SCI_KW=1

    grep -qiE "ngss|grade|standard|curriculum|k-2|3-5|6-8|kindergarten|elementary|middle|recommend|align" "$REPORT_FILE" 2>/dev/null && HAS_CURRICULUM_KW=1
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
    "has_physics_content": $HAS_PHYSICS_KW == 1,
    "has_color_optics_content": $HAS_COLOR_KW == 1,
    "has_other_science_content": $HAS_OTHER_SCI_KW == 1,
    "has_curriculum_alignment_content": $HAS_CURRICULUM_KW == 1,
    "has_gravity_activity": $HAS_GRAVITY == 1,
    "has_watercycle_activity": $HAS_WATERCYCLE == 1,
    "has_mixing_paint_activity": $HAS_MIXING_PAINT == 1,
    "has_mixing_light_activity": $HAS_MIXING_LIGHT == 1,
    "has_canal_activity": $HAS_CANAL == 1,
    "has_binary_activity": $HAS_BINARY == 1,
    "has_farm_activity": $HAS_FARM == 1,
}

with open("/tmp/science_experiment_catalog_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result JSON written to /tmp/science_experiment_catalog_result.json")
PYEOF

echo "=== Export complete ==="
