#!/bin/bash
echo "=== Exporting configure_company_holidays results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot as evidence
take_screenshot /tmp/configure_holidays_final.png

# Fetch initial state
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_holiday_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM holidays WHERE deleted=0" | tr -d '[:space:]')

# Query Holiday 1 (Independence Day)
H1_DATA=$(suitecrm_db_query "SELECT id, holiday_date, description, person_id FROM holidays WHERE holiday_date='2026-07-03' AND deleted=0 LIMIT 1")
H1_FOUND="false"
H1_PERSON=""
if [ -n "$H1_DATA" ]; then
    H1_FOUND="true"
    H1_PERSON=$(echo "$H1_DATA" | awk -F'\t' '{print $4}')
fi

# Query Holiday 2 (Thanksgiving)
H2_DATA=$(suitecrm_db_query "SELECT id, holiday_date, description, person_id FROM holidays WHERE holiday_date='2026-11-26' AND deleted=0 LIMIT 1")
H2_FOUND="false"
H2_PERSON=""
if [ -n "$H2_DATA" ]; then
    H2_FOUND="true"
    H2_PERSON=$(echo "$H2_DATA" | awk -F'\t' '{print $4}')
fi

# Query Holiday 3 (Sarah PTO) with join to users table to verify assignment
H3_DATA=$(suitecrm_db_query "SELECT h.id, h.holiday_date, h.description, h.person_id, u.first_name, u.last_name FROM holidays h LEFT JOIN users u ON h.person_id = u.id WHERE h.holiday_date='2026-08-14' AND h.deleted=0 LIMIT 1")
H3_FOUND="false"
H3_PERSON=""
H3_FNAME=""
H3_LNAME=""
if [ -n "$H3_DATA" ]; then
    H3_FOUND="true"
    H3_PERSON=$(echo "$H3_DATA" | awk -F'\t' '{print $4}')
    H3_FNAME=$(echo "$H3_DATA" | awk -F'\t' '{print $5}')
    H3_LNAME=$(echo "$H3_DATA" | awk -F'\t' '{print $6}')
fi

# Check for overall anti-gaming (did they actually create new records?)
NEWLY_CREATED="false"
if [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
    NEWLY_CREATED="true"
fi

# Create JSON output
RESULT_JSON=$(cat << JSONEOF
{
  "task_start": $TASK_START,
  "initial_count": $INITIAL_COUNT,
  "current_count": $CURRENT_COUNT,
  "newly_created": $NEWLY_CREATED,
  "h1_found": $H1_FOUND,
  "h1_person": "$(json_escape "${H1_PERSON:-}")",
  "h2_found": $H2_FOUND,
  "h2_person": "$(json_escape "${H2_PERSON:-}")",
  "h3_found": $H3_FOUND,
  "h3_person": "$(json_escape "${H3_PERSON:-}")",
  "h3_fname": "$(json_escape "${H3_FNAME:-}")",
  "h3_lname": "$(json_escape "${H3_LNAME:-}")"
}
JSONEOF
)

# Safely write the results
safe_write_result "/tmp/configure_holidays_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/configure_holidays_result.json"
echo "$RESULT_JSON"
echo "=== configure_company_holidays export complete ==="