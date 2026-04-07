#!/bin/bash
echo "=== Exporting manage_event_delegates results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/manage_event_delegates_final.png

# Retrieve task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Query for the Event
EVENT_DATA=$(suitecrm_db_query "SELECT id, name, location, budget, UNIX_TIMESTAMP(date_entered) FROM fp_events WHERE name='VIP Executive Dinner 2026' AND deleted=0 LIMIT 1" 2>/dev/null)

EVENT_FOUND="false"
E_ID=""
E_NAME=""
E_LOCATION=""
E_BUDGET=""
E_CREATED_TIME="0"

if [ -n "$EVENT_DATA" ]; then
    EVENT_FOUND="true"
    E_ID=$(echo "$EVENT_DATA" | awk -F'\t' '{print $1}')
    E_NAME=$(echo "$EVENT_DATA" | awk -F'\t' '{print $2}')
    E_LOCATION=$(echo "$EVENT_DATA" | awk -F'\t' '{print $3}')
    E_BUDGET=$(echo "$EVENT_DATA" | awk -F'\t' '{print $4}')
    E_CREATED_TIME=$(echo "$EVENT_DATA" | awk -F'\t' '{print $5}')
fi

# 2. Check contacts linked via Many-to-Many Relationship Tables
C1_LINKED="false"
C2_LINKED="false"
C3_LINKED="false"

if [ -n "$E_ID" ]; then
    # Grab all active relationship records for Events
    REL_DUMP=$(suitecrm_db_query "SELECT * FROM fp_events_contacts_c WHERE deleted=0" 2>/dev/null)
    if [ -z "$REL_DUMP" ]; then
        # Fallback to standard table name
        REL_DUMP=$(suitecrm_db_query "SELECT * FROM fp_events_contacts WHERE deleted=0" 2>/dev/null)
    fi
    
    # Get database IDs of our 3 seeded contacts
    C1_ID=$(suitecrm_db_query "SELECT id FROM contacts WHERE first_name='Olivia' AND last_name='Sterling' AND deleted=0 LIMIT 1" 2>/dev/null)
    C2_ID=$(suitecrm_db_query "SELECT id FROM contacts WHERE first_name='Jameson' AND last_name='Wright' AND deleted=0 LIMIT 1" 2>/dev/null)
    C3_ID=$(suitecrm_db_query "SELECT id FROM contacts WHERE first_name='Elena' AND last_name='Rostova' AND deleted=0 LIMIT 1" 2>/dev/null)
    
    # Check if both Event ID and Contact ID co-exist in the relationship dump rows
    if [ -n "$C1_ID" ] && echo "$REL_DUMP" | grep -q "$E_ID" && echo "$REL_DUMP" | grep "$E_ID" | grep -q "$C1_ID"; then C1_LINKED="true"; fi
    if [ -n "$C2_ID" ] && echo "$REL_DUMP" | grep -q "$E_ID" && echo "$REL_DUMP" | grep "$E_ID" | grep -q "$C2_ID"; then C2_LINKED="true"; fi
    if [ -n "$C3_ID" ] && echo "$REL_DUMP" | grep -q "$E_ID" && echo "$REL_DUMP" | grep "$E_ID" | grep -q "$C3_ID"; then C3_LINKED="true"; fi
fi

# 3. Check for Anti-Gaming (Did they just create NEW contacts instead of linking?)
# If they created new contacts during the task with the same names, that's a failure of the subpanel selection workflow.
DUPLICATES_CREATED="false"
NEW_CONTACTS_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM contacts WHERE UNIX_TIMESTAMP(date_entered) > $TASK_START AND first_name IN ('Olivia', 'Jameson', 'Elena') AND deleted=0" 2>/dev/null)

if [ -n "$NEW_CONTACTS_COUNT" ] && [ "$NEW_CONTACTS_COUNT" -gt 0 ]; then
    DUPLICATES_CREATED="true"
fi

# Export to JSON
RESULT_JSON=$(cat << JSONEOF
{
  "task_start": ${TASK_START},
  "event_found": ${EVENT_FOUND},
  "event_created_time": ${E_CREATED_TIME},
  "event_id": "$(json_escape "${E_ID:-}")",
  "name": "$(json_escape "${E_NAME:-}")",
  "location": "$(json_escape "${E_LOCATION:-}")",
  "budget": "$(json_escape "${E_BUDGET:-}")",
  "c1_linked": ${C1_LINKED},
  "c2_linked": ${C2_LINKED},
  "c3_linked": ${C3_LINKED},
  "duplicates_created": ${DUPLICATES_CREATED}
}
JSONEOF
)

safe_write_result "/tmp/manage_event_delegates_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/manage_event_delegates_result.json"
echo "$RESULT_JSON"
echo "=== manage_event_delegates export complete ==="