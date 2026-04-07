#!/bin/bash
echo "=== Exporting ekos_robotic_schedule_generation results ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EKOS_DIR="/home/ga/Documents/Ekos"

# Helper function to get base64 of file if it exists and is created after task start
get_file_data() {
    local file_path=$1
    if [ -f "$file_path" ]; then
        local mtime=$(stat -c %Y "$file_path" 2>/dev/null || echo "0")
        if [ "$mtime" -ge "$TASK_START" ]; then
            echo $(base64 -w 0 "$file_path" 2>/dev/null)
        else
            echo "STALE"
        fi
    else
        echo "MISSING"
    fi
}

DIR_EXISTS="false"
if [ -d "$EKOS_DIR" ]; then
    DIR_EXISTS="true"
fi

M81_B64=$(get_file_data "$EKOS_DIR/m81_lrgb.esq")
NGC1499_B64=$(get_file_data "$EKOS_DIR/ngc1499_ha.esq")
M42_B64=$(get_file_data "$EKOS_DIR/m42_hdr.esq")
MASTER_B64=$(get_file_data "$EKOS_DIR/master_schedule.esl")

python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "dir_exists": "$DIR_EXISTS" == "true",
    "files": {
        "m81_lrgb.esq": "$M81_B64",
        "ngc1499_ha.esq": "$NGC1499_B64",
        "m42_hdr.esq": "$M42_B64",
        "master_schedule.esl": "$MASTER_B64"
    }
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="