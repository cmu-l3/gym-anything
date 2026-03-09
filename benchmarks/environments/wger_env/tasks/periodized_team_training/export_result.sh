#!/bin/bash
# Export results: periodized_team_training
# Queries the wger database for the three phase routines and their training days,
# then writes the result to /tmp/periodized_training_result.json.

source /workspace/scripts/task_utils.sh

echo "=== Exporting periodized_team_training results ==="

# Take final screenshot
take_screenshot /tmp/task_periodized_team_training_final.png

# ---------------------------------------------------------------
# Helper: escape a string for safe JSON embedding
# ---------------------------------------------------------------
json_esc() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/}"
    s="${s//$'\t'/\\t}"
    echo "$s"
}

# ---------------------------------------------------------------
# Read initial baselines
# ---------------------------------------------------------------
INITIAL_ROUTINE_COUNT=0
INITIAL_DAY_COUNT=0
if [ -f /tmp/periodized_training_initial.json ]; then
    INITIAL_ROUTINE_COUNT=$(python3 -c "import json; d=json.load(open('/tmp/periodized_training_initial.json')); print(d.get('initial_routine_count', 0))" 2>/dev/null || echo "0")
    INITIAL_DAY_COUNT=$(python3 -c "import json; d=json.load(open('/tmp/periodized_training_initial.json')); print(d.get('initial_day_count', 0))" 2>/dev/null || echo "0")
fi

# ---------------------------------------------------------------
# Query each routine by exact name
# ---------------------------------------------------------------
ADMIN_ID=$(db_query "SELECT id FROM auth_user WHERE username='admin'" | tr -d '[:space:]')

# --- Phase 1 ---
P1_DATA=$(db_query "SELECT id, description FROM manager_routine WHERE name='Phase 1 - Anatomical Adaptation' AND user_id=${ADMIN_ID} ORDER BY id DESC LIMIT 1")
P1_FOUND="false"
P1_ID=""
P1_DESC=""
if [ -n "$P1_DATA" ]; then
    P1_FOUND="true"
    P1_ID=$(echo "$P1_DATA" | awk -F'|' '{print $1}' | tr -d '[:space:]')
    P1_DESC=$(echo "$P1_DATA" | awk -F'|' '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
fi

# --- Phase 2 ---
P2_DATA=$(db_query "SELECT id, description FROM manager_routine WHERE name='Phase 2 - Maximal Strength' AND user_id=${ADMIN_ID} ORDER BY id DESC LIMIT 1")
P2_FOUND="false"
P2_ID=""
P2_DESC=""
if [ -n "$P2_DATA" ]; then
    P2_FOUND="true"
    P2_ID=$(echo "$P2_DATA" | awk -F'|' '{print $1}' | tr -d '[:space:]')
    P2_DESC=$(echo "$P2_DATA" | awk -F'|' '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
fi

# --- Phase 3 ---
P3_DATA=$(db_query "SELECT id, description FROM manager_routine WHERE name='Phase 3 - Power Development' AND user_id=${ADMIN_ID} ORDER BY id DESC LIMIT 1")
P3_FOUND="false"
P3_ID=""
P3_DESC=""
if [ -n "$P3_DATA" ]; then
    P3_FOUND="true"
    P3_ID=$(echo "$P3_DATA" | awk -F'|' '{print $1}' | tr -d '[:space:]')
    P3_DESC=$(echo "$P3_DATA" | awk -F'|' '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
fi

# ---------------------------------------------------------------
# Query training days for each routine
# The day_of_week is stored in a many-to-many table: manager_day_day
# manager_day_day columns: day_id, dayofweek_id
# dayofweek_id: 1=Monday, 2=Tuesday, 3=Wednesday, 4=Thursday, 5=Friday, 6=Saturday, 7=Sunday
# ---------------------------------------------------------------

query_days_for_routine() {
    local routine_id="$1"
    if [ -z "$routine_id" ]; then
        echo "[]"
        return
    fi
    # Get all days for this routine, with their day-of-week assignments
    local days_json="["
    local first="true"
    while IFS='|' read -r day_id day_name; do
        day_id=$(echo "$day_id" | tr -d '[:space:]')
        day_name=$(echo "$day_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -z "$day_id" ]; then continue; fi

        # Get day_of_week values for this day
        local dow_list=""
        dow_list=$(db_query "SELECT dayofweek_id FROM manager_day_day WHERE day_id=${day_id} ORDER BY dayofweek_id")
        # Build a JSON array of day-of-week integers
        local dow_json="["
        local dow_first="true"
        while IFS= read -r dow_val; do
            dow_val=$(echo "$dow_val" | tr -d '[:space:]')
            if [ -z "$dow_val" ]; then continue; fi
            if [ "$dow_first" = "true" ]; then
                dow_json="${dow_json}${dow_val}"
                dow_first="false"
            else
                dow_json="${dow_json},${dow_val}"
            fi
        done <<< "$dow_list"
        dow_json="${dow_json}]"

        if [ "$first" = "true" ]; then
            first="false"
        else
            days_json="${days_json},"
        fi
        days_json="${days_json}{\"id\":${day_id},\"name\":\"$(json_esc "$day_name")\",\"day_of_week\":${dow_json}}"
    done <<< "$(db_query "SELECT id, name FROM manager_day WHERE routine_id=${routine_id} ORDER BY id")"
    days_json="${days_json}]"
    echo "$days_json"
}

P1_DAYS=$(query_days_for_routine "$P1_ID")
P2_DAYS=$(query_days_for_routine "$P2_ID")
P3_DAYS=$(query_days_for_routine "$P3_ID")

# ---------------------------------------------------------------
# Current counts
# ---------------------------------------------------------------
CURRENT_ROUTINE_COUNT=$(db_query "SELECT COUNT(*) FROM manager_routine WHERE user_id=${ADMIN_ID}" | tr -d '[:space:]')
CURRENT_DAY_COUNT=$(db_query "SELECT COUNT(*) FROM manager_day WHERE routine_id IN (SELECT id FROM manager_routine WHERE user_id=${ADMIN_ID})" | tr -d '[:space:]')

# ---------------------------------------------------------------
# Build result JSON
# ---------------------------------------------------------------
RESULT_JSON=$(cat << JSONEOF
{
  "phase1": {
    "found": ${P1_FOUND},
    "id": "${P1_ID}",
    "description": "$(json_esc "$P1_DESC")",
    "days": ${P1_DAYS}
  },
  "phase2": {
    "found": ${P2_FOUND},
    "id": "${P2_ID}",
    "description": "$(json_esc "$P2_DESC")",
    "days": ${P2_DAYS}
  },
  "phase3": {
    "found": ${P3_FOUND},
    "id": "${P3_ID}",
    "description": "$(json_esc "$P3_DESC")",
    "days": ${P3_DAYS}
  },
  "initial_routine_count": ${INITIAL_ROUTINE_COUNT},
  "initial_day_count": ${INITIAL_DAY_COUNT},
  "current_routine_count": ${CURRENT_ROUTINE_COUNT:-0},
  "current_day_count": ${CURRENT_DAY_COUNT:-0}
}
JSONEOF
)

# Write result file
echo "$RESULT_JSON" > /tmp/periodized_training_result.json

echo "Result saved to /tmp/periodized_training_result.json"
echo "$RESULT_JSON"
echo "=== periodized_team_training export complete ==="
