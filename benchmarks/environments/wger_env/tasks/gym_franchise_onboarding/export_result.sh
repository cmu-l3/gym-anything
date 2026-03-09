#!/bin/bash
# Export results: gym_franchise_onboarding
# Queries the wger database for all entities the agent was supposed to create,
# then writes a structured JSON result file for the verifier to consume.

source /workspace/scripts/task_utils.sh

echo "=== Exporting gym_franchise_onboarding results ==="

# Take final screenshot
take_screenshot /tmp/task_gym_franchise_onboarding_final.png

# -----------------------------------------------------------------------
# Helper: escape a string for safe JSON embedding
# -----------------------------------------------------------------------
json_esc() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/}"
    s="${s//$'\t'/\\t}"
    echo "$s"
}

# -----------------------------------------------------------------------
# Query user accounts
# -----------------------------------------------------------------------
docker exec wger-web python3 manage.py shell -c "
import json
from django.contrib.auth.models import User

users_data = {}
for uname, expected_first, expected_last, expected_email in [
    ('coach_rivera', 'Carlos', 'Rivera', 'carlos.rivera@ironpeakfit.com'),
    ('coach_nakamura', 'Yuki', 'Nakamura', 'yuki.nakamura@ironpeakfit.com'),
    ('front_desk_jones', 'Tamika', 'Jones', 'tamika.jones@ironpeakfit.com'),
    ('member_williams', 'Derek', 'Williams', 'derek.williams@ironpeakfit.com'),
]:
    try:
        u = User.objects.get(username=uname)
        users_data[uname] = {
            'exists': True,
            'first_name': u.first_name,
            'last_name': u.last_name,
            'email': u.email,
            'expected_first': expected_first,
            'expected_last': expected_last,
            'expected_email': expected_email
        }
    except User.DoesNotExist:
        users_data[uname] = {
            'exists': False,
            'expected_first': expected_first,
            'expected_last': expected_last,
            'expected_email': expected_email
        }

print(json.dumps(users_data))
" 2>/dev/null > /tmp/_gfo_users.json || echo '{}' > /tmp/_gfo_users.json

# -----------------------------------------------------------------------
# Query routine and its training days
# -----------------------------------------------------------------------
ADMIN_ID=$(db_query "SELECT id FROM auth_user WHERE username='admin'" | tr -d '[:space:]')

ROUTINE_DATA=$(db_query "SELECT id, description FROM manager_routine WHERE name='New Member Welcome Routine' AND user_id=${ADMIN_ID} ORDER BY id DESC LIMIT 1")
ROUTINE_FOUND="false"
ROUTINE_ID=""
ROUTINE_DESC=""
if [ -n "$ROUTINE_DATA" ]; then
    ROUTINE_FOUND="true"
    ROUTINE_ID=$(echo "$ROUTINE_DATA" | awk -F'|' '{print $1}' | tr -d '[:space:]')
    ROUTINE_DESC=$(echo "$ROUTINE_DATA" | awk -F'|' '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
fi

# -----------------------------------------------------------------------
# Query training days for the routine
# The day_of_week is stored in a many-to-many table: manager_day_day
# manager_day_day columns: day_id, dayofweek_id
# dayofweek_id: 1=Monday, 2=Tuesday, 3=Wednesday, 4=Thursday, 5=Friday, 6=Saturday, 7=Sunday
# -----------------------------------------------------------------------
query_days_for_routine() {
    local routine_id="$1"
    if [ -z "$routine_id" ]; then
        echo "[]"
        return
    fi
    local days_json="["
    local first="true"
    while IFS='|' read -r day_id day_name; do
        day_id=$(echo "$day_id" | tr -d '[:space:]')
        day_name=$(echo "$day_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -z "$day_id" ]; then continue; fi

        # Get day_of_week values for this day
        local dow_list=""
        dow_list=$(db_query "SELECT dayofweek_id FROM manager_day_day WHERE day_id=${day_id} ORDER BY dayofweek_id")
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

ROUTINE_DAYS="[]"
if [ -n "$ROUTINE_ID" ]; then
    ROUTINE_DAYS=$(query_days_for_routine "$ROUTINE_ID")
fi

# -----------------------------------------------------------------------
# Query nutrition plan
# -----------------------------------------------------------------------
PLAN_FOUND="false"
PLAN_DATA=$(db_query "SELECT id FROM nutrition_nutritionplan WHERE description='30-Day Transformation Kickstart' AND user_id=${ADMIN_ID} ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')
if [ -n "$PLAN_DATA" ]; then
    PLAN_FOUND="true"
fi

# -----------------------------------------------------------------------
# Query measurement categories
# -----------------------------------------------------------------------
docker exec wger-web python3 manage.py shell -c "
import json
from wger.measure.models import Category as MeasureCategory

categories_data = {}
for cname, expected_unit in [('Body Fat Percentage', '%'), ('Lean Muscle Mass', 'kg')]:
    qs = MeasureCategory.objects.filter(name=cname)
    if qs.exists():
        cat = qs.first()
        categories_data[cname] = {
            'exists': True,
            'unit': cat.unit if hasattr(cat, 'unit') else '',
            'expected_unit': expected_unit
        }
    else:
        categories_data[cname] = {
            'exists': False,
            'expected_unit': expected_unit
        }

print(json.dumps(categories_data))
" 2>/dev/null > /tmp/_gfo_categories.json || echo '{}' > /tmp/_gfo_categories.json

# -----------------------------------------------------------------------
# Read baselines
# -----------------------------------------------------------------------
BASELINES="{}"
if [ -f /tmp/gym_franchise_initial.json ]; then
    BASELINES=$(cat /tmp/gym_franchise_initial.json)
fi

# -----------------------------------------------------------------------
# Assemble final result JSON
# -----------------------------------------------------------------------
USERS_JSON=$(cat /tmp/_gfo_users.json 2>/dev/null || echo '{}')
CATEGORIES_JSON=$(cat /tmp/_gfo_categories.json 2>/dev/null || echo '{}')

RESULT_JSON=$(cat << JSONEOF
{
  "users": ${USERS_JSON},
  "routine": {
    "found": ${ROUTINE_FOUND},
    "id": "${ROUTINE_ID}",
    "description": "$(json_esc "$ROUTINE_DESC")",
    "days": ${ROUTINE_DAYS}
  },
  "nutrition_plan": {
    "found": ${PLAN_FOUND}
  },
  "measurement_categories": ${CATEGORIES_JSON},
  "baselines": ${BASELINES}
}
JSONEOF
)

echo "$RESULT_JSON" > /tmp/gym_franchise_result.json

if [ -f /tmp/gym_franchise_result.json ]; then
    echo "Results exported to /tmp/gym_franchise_result.json"
    cat /tmp/gym_franchise_result.json
else
    echo "Warning: Failed to export results, writing empty result"
    echo '{"users":{},"routine":{"found":false},"nutrition_plan":{"found":false},"measurement_categories":{},"baselines":{}}' > /tmp/gym_franchise_result.json
fi

# Clean up temp files
rm -f /tmp/_gfo_users.json /tmp/_gfo_categories.json

echo "=== Export complete: gym_franchise_onboarding ==="
