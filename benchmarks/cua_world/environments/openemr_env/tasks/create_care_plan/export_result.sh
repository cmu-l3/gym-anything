#!/bin/bash
# Export script for Create Care Plan task

echo "=== Exporting Create Care Plan Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh || true

# Configuration
PATIENT_PID=5
PATIENT_NAME="Jayme Kunze"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

if [ -f /tmp/task_final_state.png ]; then
    echo "Final screenshot captured"
else
    echo "WARNING: Could not capture final screenshot"
fi

# Get initial counts
INITIAL_FORMS=$(cat /tmp/initial_forms_count.txt 2>/dev/null || echo "0")
INITIAL_LISTS=$(cat /tmp/initial_lists_count.txt 2>/dev/null || echo "0")
INITIAL_ALL_LISTS=$(cat /tmp/initial_all_lists_count.txt 2>/dev/null || echo "0")

# Query current forms count
CURRENT_FORMS=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM forms WHERE pid=$PATIENT_PID AND (formdir LIKE '%care%' OR form_name LIKE '%care%' OR form_name LIKE '%Care%')" 2>/dev/null || echo "0")
echo "Forms count: initial=$INITIAL_FORMS, current=$CURRENT_FORMS"

# Query current care plan lists count
CURRENT_LISTS=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID AND type IN ('care_plan', 'goal', 'intervention', 'health_concern')" 2>/dev/null || echo "0")
echo "Care plan lists count: initial=$INITIAL_LISTS, current=$CURRENT_LISTS"

# Query total lists count
CURRENT_ALL_LISTS=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "Total lists count: initial=$INITIAL_ALL_LISTS, current=$CURRENT_ALL_LISTS"

# Check for new entries in lists table that might be care plan related
echo ""
echo "=== DEBUG: Recent list entries for patient ==="
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
    "SELECT id, date, type, title, diagnosis FROM lists WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 10" 2>/dev/null
echo "=== END DEBUG ==="

# Look for care plan specific entries
echo ""
echo "=== Checking for care plan entries ==="

# Check for entries with care plan related types
CAREPLAN_ENTRIES=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT id, type, title FROM lists WHERE pid=$PATIENT_PID AND type IN ('care_plan', 'goal', 'intervention', 'health_concern') ORDER BY id DESC LIMIT 5" 2>/dev/null)
echo "Care plan entries found:"
echo "$CAREPLAN_ENTRIES"

# Look for goals containing HbA1c or diabetes keywords
GOAL_ENTRIES=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT id, type, title FROM lists WHERE pid=$PATIENT_PID AND (LOWER(title) LIKE '%hba1c%' OR LOWER(title) LIKE '%a1c%' OR LOWER(title) LIKE '%7%' OR LOWER(title) LIKE '%glucose%' OR LOWER(title) LIKE '%diabetes%') ORDER BY id DESC LIMIT 5" 2>/dev/null)
echo "Goal-related entries:"
echo "$GOAL_ENTRIES"

# Look for intervention entries
INTERVENTION_ENTRIES=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT id, type, title FROM lists WHERE pid=$PATIENT_PID AND (LOWER(title) LIKE '%adherence%' OR LOWER(title) LIKE '%monitor%' OR LOWER(title) LIKE '%counsel%' OR LOWER(title) LIKE '%medication%') ORDER BY id DESC LIMIT 5" 2>/dev/null)
echo "Intervention-related entries:"
echo "$INTERVENTION_ENTRIES"

# Check forms table for care plan forms
echo ""
echo "=== Checking forms table ==="
CAREPLAN_FORMS=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT id, date, form_name, formdir FROM forms WHERE pid=$PATIENT_PID AND (formdir LIKE '%care%' OR form_name LIKE '%care%' OR form_name LIKE '%Care%') ORDER BY id DESC LIMIT 5" 2>/dev/null)
echo "Care plan forms:"
echo "$CAREPLAN_FORMS"

# Check for form_care_plan table if it exists
FORM_CAREPLAN_EXISTS=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='openemr' AND table_name='form_care_plan'" 2>/dev/null || echo "0")
FORM_CAREPLAN_COUNT="0"
FORM_CAREPLAN_DATA=""
if [ "$FORM_CAREPLAN_EXISTS" = "1" ]; then
    FORM_CAREPLAN_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
        "SELECT COUNT(*) FROM form_care_plan WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
    FORM_CAREPLAN_DATA=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
        "SELECT * FROM form_care_plan WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 3" 2>/dev/null)
    echo "form_care_plan table entries: $FORM_CAREPLAN_COUNT"
    echo "$FORM_CAREPLAN_DATA"
fi

# Check for any new entries since task started (using id comparison)
NEW_ENTRIES_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID AND id > (SELECT COALESCE(MAX(id), 0) - 20 FROM lists WHERE pid=$PATIENT_PID)" 2>/dev/null || echo "0")

# Determine if care plan was created
CAREPLAN_FOUND="false"
GOAL_FOUND="false"
INTERVENTION_FOUND="false"
HEALTH_CONCERN_FOUND="false"

# Check if new forms were added
if [ "$CURRENT_FORMS" -gt "$INITIAL_FORMS" ]; then
    CAREPLAN_FOUND="true"
fi

# Check if new list entries were added
if [ "$CURRENT_LISTS" -gt "$INITIAL_LISTS" ]; then
    CAREPLAN_FOUND="true"
fi

# Check for goal keywords
if [ -n "$GOAL_ENTRIES" ]; then
    GOAL_FOUND="true"
fi

# Check for intervention keywords
if [ -n "$INTERVENTION_ENTRIES" ]; then
    INTERVENTION_FOUND="true"
fi

# Check for health concern (diabetes)
DIABETES_CONCERN=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID AND type IN ('health_concern', 'care_plan') AND LOWER(title) LIKE '%diabetes%'" 2>/dev/null || echo "0")
if [ "$DIABETES_CONCERN" -gt 0 ]; then
    HEALTH_CONCERN_FOUND="true"
fi

# Check for target date (enddate set in lists)
TARGET_DATE_SET="false"
TARGET_DATE_CHECK=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM lists WHERE pid=$PATIENT_PID AND type IN ('goal', 'care_plan') AND enddate IS NOT NULL AND enddate > CURDATE()" 2>/dev/null || echo "0")
if [ "$TARGET_DATE_CHECK" -gt 0 ]; then
    TARGET_DATE_SET="true"
fi

# Get any goal text for verification
GOAL_TEXT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT title FROM lists WHERE pid=$PATIENT_PID AND type IN ('goal', 'care_plan') AND (LOWER(title) LIKE '%hba1c%' OR LOWER(title) LIKE '%a1c%' OR LOWER(title) LIKE '%7%') LIMIT 1" 2>/dev/null | tr '\t' ' ' | tr '\n' ' ')

# Get any intervention text
INTERVENTION_TEXT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT title FROM lists WHERE pid=$PATIENT_PID AND type IN ('intervention', 'care_plan') AND (LOWER(title) LIKE '%adherence%' OR LOWER(title) LIKE '%monitor%' OR LOWER(title) LIKE '%counsel%') LIMIT 1" 2>/dev/null | tr '\t' ' ' | tr '\n' ' ')

# Escape special characters for JSON
GOAL_TEXT_ESCAPED=$(echo "$GOAL_TEXT" | sed 's/"/\\"/g' | tr -d '\n')
INTERVENTION_TEXT_ESCAPED=$(echo "$INTERVENTION_TEXT" | sed 's/"/\\"/g' | tr -d '\n')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/careplan_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "patient_name": "$PATIENT_NAME",
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "initial_state": {
        "forms_count": ${INITIAL_FORMS:-0},
        "careplan_lists_count": ${INITIAL_LISTS:-0},
        "total_lists_count": ${INITIAL_ALL_LISTS:-0}
    },
    "current_state": {
        "forms_count": ${CURRENT_FORMS:-0},
        "careplan_lists_count": ${CURRENT_LISTS:-0},
        "total_lists_count": ${CURRENT_ALL_LISTS:-0},
        "form_careplan_table_count": ${FORM_CAREPLAN_COUNT:-0}
    },
    "detection": {
        "careplan_found": $CAREPLAN_FOUND,
        "goal_found": $GOAL_FOUND,
        "intervention_found": $INTERVENTION_FOUND,
        "health_concern_found": $HEALTH_CONCERN_FOUND,
        "target_date_set": $TARGET_DATE_SET
    },
    "content": {
        "goal_text": "$GOAL_TEXT_ESCAPED",
        "intervention_text": "$INTERVENTION_TEXT_ESCAPED"
    },
    "screenshot_exists": $([ -f "/tmp/task_final_state.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/create_careplan_result.json 2>/dev/null || sudo rm -f /tmp/create_careplan_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/create_careplan_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/create_careplan_result.json
chmod 666 /tmp/create_careplan_result.json 2>/dev/null || sudo chmod 666 /tmp/create_careplan_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Result JSON ==="
cat /tmp/create_careplan_result.json
echo ""
echo "=== Export Complete ==="