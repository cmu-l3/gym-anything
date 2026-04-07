#!/bin/bash
# Export Result: mark_patient_deceased
# Checks if Harold Bergstrom is dead and has the correct death date.

echo "=== Exporting Results ==="
source /workspace/scripts/task_utils.sh

# 1. Get Target UUID
PATIENT_UUID=$(cat /tmp/target_patient_uuid.txt 2>/dev/null)
if [ -z "$PATIENT_UUID" ]; then
    # Fallback search
    PATIENT_UUID=$(get_patient_uuid "Harold Bergstrom")
fi
PERSON_UUID=$(get_person_uuid "$PATIENT_UUID")

echo "Checking patient: $PATIENT_UUID (Person: $PERSON_UUID)"

# 2. Database Verification (Primary)
# Columns in 'person' table: dead (bit/tinyint), death_date (datetime)
DB_RESULT=$(omrs_db_query "SELECT dead, DATE_FORMAT(death_date, '%Y-%m-%d') FROM person WHERE uuid='$PERSON_UUID'")
# Expected format from mariadb CLI with -N: "1  2025-01-15" (tab separated)

IS_DEAD_DB=$(echo "$DB_RESULT" | awk '{print $1}')
DEATH_DATE_DB=$(echo "$DB_RESULT" | awk '{print $2}')

echo "DB Result: Dead=$IS_DEAD_DB, Date=$DEATH_DATE_DB"

# 3. REST API Verification (Secondary/Cross-check)
API_RESP=$(omrs_get "/person/$PERSON_UUID?v=default")
IS_DEAD_API=$(echo "$API_RESP" | python3 -c "import sys,json; print(str(json.load(sys.stdin).get('dead','')).lower())")
DEATH_DATE_API=$(echo "$API_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('deathDate',''))")
# API date format is typically ISO like "2025-01-15T00:00:00.000+0000"

# Normalize API date to YYYY-MM-DD
if [ "$DEATH_DATE_API" != "None" ] && [ -n "$DEATH_DATE_API" ]; then
    DEATH_DATE_API_FMT=$(date -d "$DEATH_DATE_API" +%Y-%m-%d 2>/dev/null || echo "$DEATH_DATE_API")
else
    DEATH_DATE_API_FMT=""
fi

echo "API Result: Dead=$IS_DEAD_API, Date=$DEATH_DATE_API_FMT"

# 4. Anti-gaming: Check modification time
# We check 'date_changed' column in person table
TASK_START_TS=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
LAST_CHANGED_TS=$(omrs_db_query "SELECT UNIX_TIMESTAMP(date_changed) FROM person WHERE uuid='$PERSON_UUID'")
if [ -z "$LAST_CHANGED_TS" ] || [ "$LAST_CHANGED_TS" == "NULL" ]; then
    LAST_CHANGED_TS=0
fi

MODIFIED_DURING_TASK="false"
if [ "$LAST_CHANGED_TS" -ge "$TASK_START_TS" ]; then
    MODIFIED_DURING_TASK="true"
fi

# 5. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Generate JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_uuid": "$PATIENT_UUID",
    "db_dead": "$IS_DEAD_DB",
    "db_death_date": "$DEATH_DATE_DB",
    "api_dead": "$IS_DEAD_API",
    "api_death_date": "$DEATH_DATE_API_FMT",
    "modified_during_task": $MODIFIED_DURING_TASK,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/task_result.json