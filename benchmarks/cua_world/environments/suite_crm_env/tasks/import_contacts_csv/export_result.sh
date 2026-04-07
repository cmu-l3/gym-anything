#!/bin/bash
set -e
echo "=== Exporting Import Contacts CSV task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ELAPSED=$((TASK_END - TASK_START))

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Initial and current contact counts
INITIAL_COUNT=$(cat /tmp/initial_contact_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(suitecrm_count "contacts" "deleted=0")

# Collect contact data
CONTACT_NAMES=(
    "Marcus:Chen"
    "Diana:Vasquez"
    "Robert:Okafor"
    "Sarah:Johansson"
    "James:Whitfield"
    "Priya:Ramanathan"
    "Thomas:Brennan"
    "Lisa:Nakamura"
    "David:Kowalski"
    "Angela:Torres"
    "Michael:Ostrowski"
    "Karen:Blackwood"
)

CONTACTS_JSON="["
FIRST=true
for name_pair in "${CONTACT_NAMES[@]}"; do
    first="${name_pair%%:*}"
    last="${name_pair##*:}"
    
    # Check if exists
    COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM contacts WHERE first_name='${first}' AND last_name='${last}' AND deleted=0" | tr -d '[:space:]')
    
    if [ -n "$COUNT" ] && [ "$COUNT" -gt 0 ] 2>/dev/null; then
        if [ "$FIRST" = true ]; then
            FIRST=false
        else
            CONTACTS_JSON="$CONTACTS_JSON,"
        fi
        
        TITLE=$(suitecrm_db_query "SELECT title FROM contacts WHERE first_name='${first}' AND last_name='${last}' AND deleted=0 LIMIT 1")
        PHONE=$(suitecrm_db_query "SELECT phone_work FROM contacts WHERE first_name='${first}' AND last_name='${last}' AND deleted=0 LIMIT 1")
        CITY=$(suitecrm_db_query "SELECT primary_address_city FROM contacts WHERE first_name='${first}' AND last_name='${last}' AND deleted=0 LIMIT 1")
        DESC=$(suitecrm_db_query "SELECT description FROM contacts WHERE first_name='${first}' AND last_name='${last}' AND deleted=0 LIMIT 1")
        
        TITLE_ESC=$(json_escape "$TITLE")
        PHONE_ESC=$(json_escape "$PHONE")
        CITY_ESC=$(json_escape "$CITY")
        DESC_ESC=$(json_escape "$DESC")
        
        CONTACTS_JSON="$CONTACTS_JSON{\"first_name\": \"$first\", \"last_name\": \"$last\", \"title\": \"$TITLE_ESC\", \"phone_work\": \"$PHONE_ESC\", \"city\": \"$CITY_ESC\", \"description\": \"$DESC_ESC\"}"
    fi
done
CONTACTS_JSON="$CONTACTS_JSON]"

# Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "elapsed_seconds": $ELAPSED,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "contacts": $CONTACTS_JSON
}
EOF

safe_write_result "/tmp/verify_result.json" "$(cat "$TEMP_JSON")"
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/verify_result.json"
echo "=== Export complete ==="