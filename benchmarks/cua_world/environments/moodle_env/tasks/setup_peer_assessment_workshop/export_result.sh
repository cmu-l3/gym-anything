#!/bin/bash
echo "=== Exporting Peer Assessment Workshop Result ==="
source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
COURSE_ID=$(cat /tmp/course_id.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_workshop_count.txt 2>/dev/null || echo "0")

# Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Query the database for the newly created workshop in this course
WORKSHOP_DATA=$(moodle_query "SELECT id, name, strategy, phase FROM mdl_workshop WHERE course=$COURSE_ID ORDER BY id DESC LIMIT 1")

WORKSHOP_ID="0"
WORKSHOP_NAME=""
WORKSHOP_STRATEGY=""
WORKSHOP_PHASE="0"
WORKSHOP_FOUND="false"

if [ -n "$WORKSHOP_DATA" ]; then
    WORKSHOP_FOUND="true"
    WORKSHOP_ID=$(echo "$WORKSHOP_DATA" | cut -f1)
    WORKSHOP_NAME=$(echo "$WORKSHOP_DATA" | cut -f2)
    WORKSHOP_STRATEGY=$(echo "$WORKSHOP_DATA" | cut -f3)
    WORKSHOP_PHASE=$(echo "$WORKSHOP_DATA" | cut -f4)
fi

# 2. Check if instructions were populated
INSTRUCTIONS_SET="false"
if [ "$WORKSHOP_ID" != "0" ]; then
    INSTR_DATA=$(moodle_query "SELECT LENGTH(instructauthors), LENGTH(instructreviewers) FROM mdl_workshop WHERE id=$WORKSHOP_ID")
    INSTR_A=$(echo "$INSTR_DATA" | cut -f1)
    INSTR_R=$(echo "$INSTR_DATA" | cut -f2)
    
    # Check if both fields have some substantial content
    if [ -n "$INSTR_A" ] && [ "$INSTR_A" -gt 20 ] && [ -n "$INSTR_R" ] && [ "$INSTR_R" -gt 20 ]; then
        INSTRUCTIONS_SET="true"
    fi
fi

# 3. Query the assessment aspects if accumulative strategy was chosen
ASPECTS_RAW=""
if [ "$WORKSHOP_ID" != "0" ] && [ "$WORKSHOP_STRATEGY" = "accumulative" ]; then
    ASPECTS_RAW=$(moodle_query "SELECT grade, description FROM mdl_workshopform_accumulative WHERE workshopid=$WORKSHOP_ID ORDER BY id ASC")
fi

# Use Python to safely convert tab-separated data with potential newlines/quotes into a clean JSON array
python3 -c "
import sys, json
raw = sys.stdin.read().strip()
aspects = []
if raw:
    for line in raw.split('\n'):
        parts = line.split('\t')
        if len(parts) >= 2:
            try:
                grade = float(parts[0])
            except ValueError:
                grade = 0.0
            aspects.append({'grade': grade, 'description': parts[1]})
print(json.dumps(aspects))
" <<< "$ASPECTS_RAW" > /tmp/aspects.json

ASPECTS_JSON=$(cat /tmp/aspects.json)

# 4. Construct the final JSON result payload
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "course_id": $COURSE_ID,
    "initial_workshop_count": $INITIAL_COUNT,
    "workshop_found": $WORKSHOP_FOUND,
    "workshop_id": $WORKSHOP_ID,
    "workshop_name": "$WORKSHOP_NAME",
    "workshop_strategy": "$WORKSHOP_STRATEGY",
    "workshop_phase": $WORKSHOP_PHASE,
    "instructions_set": $INSTRUCTIONS_SET,
    "aspects": $ASPECTS_JSON
}
EOF

# Move to standard location securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON" /tmp/aspects.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="