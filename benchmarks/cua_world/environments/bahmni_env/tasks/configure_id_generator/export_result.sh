#!/bin/bash
set -e

echo "=== Exporting configure_id_generator result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Query Database for Result
# We need to join idgen_identifier_source, idgen_seq_id_gen, and patient_identifier_type
# to verify all aspects of the configuration.

SQL_QUERY="
SELECT 
    s.name as source_name,
    pit.name as identifier_type_name,
    g.prefix,
    g.min_length,
    g.max_length,
    g.base_character_set,
    UNIX_TIMESTAMP(s.date_created) as created_ts,
    s.retired
FROM idgen_identifier_source s
JOIN idgen_seq_id_gen g ON s.id = g.id
LEFT JOIN patient_identifier_type pit ON s.identifier_type = pit.patient_identifier_type_id
WHERE s.name = 'Nutrition ID Sequence';
"

# Execute query inside the DB container
# Use -B (batch/tab-separated) and -N (skip headers) for easy parsing
DB_RESULT=$(docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -B -e "$SQL_QUERY" 2>/dev/null || echo "")

# Parse result
FOUND="false"
SOURCE_NAME=""
TYPE_NAME=""
PREFIX=""
MIN_LEN="0"
MAX_LEN="0"
BASE_SET=""
CREATED_TS="0"
RETIRED="1"

if [ -n "$DB_RESULT" ]; then
    FOUND="true"
    # Parse tab-separated output
    SOURCE_NAME=$(echo "$DB_RESULT" | cut -f1)
    TYPE_NAME=$(echo "$DB_RESULT" | cut -f2)
    PREFIX=$(echo "$DB_RESULT" | cut -f3)
    MIN_LEN=$(echo "$DB_RESULT" | cut -f4)
    MAX_LEN=$(echo "$DB_RESULT" | cut -f5)
    BASE_SET=$(echo "$DB_RESULT" | cut -f6)
    CREATED_TS=$(echo "$DB_RESULT" | cut -f7)
    RETIRED=$(echo "$DB_RESULT" | cut -f8)
fi

# Get task start time for anti-gaming check
TASK_START_TS=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Construct JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "found": $FOUND,
    "source_name": "$SOURCE_NAME",
    "identifier_type_name": "$TYPE_NAME",
    "prefix": "$PREFIX",
    "min_length": "$MIN_LEN",
    "max_length": "$MAX_LEN",
    "base_character_set": "$BASE_SET",
    "created_timestamp": $CREATED_TS,
    "is_retired": $([ "$RETIRED" == "1" ] && echo "true" || echo "false"),
    "task_start_timestamp": $TASK_START_TS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location (handling permissions)
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="