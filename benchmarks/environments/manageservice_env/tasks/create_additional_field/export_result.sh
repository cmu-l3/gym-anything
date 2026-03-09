#!/bin/bash
echo "=== Exporting Create Additional Field Result ==="
source /workspace/scripts/task_utils.sh

# 1. Record End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Query Database for Field Definition
# We look in columndetails for the field label
echo "Querying database for field definition..."
FIELD_QUERY="SELECT column_alias, ismandatory, description FROM columndetails WHERE column_alias ILIKE '%Affected Network Segment%';"
FIELD_DATA=$(sdp_db_exec "$FIELD_QUERY")

# 3. Query Database for Pick List Values
# Since schema for values can be complex, we'll check if the values exist anywhere in the DB
# linked to recent changes, or simply check if they exist in the system configuration tables.
# A robust way for SDP (Postgres) is to dump relevant tables or strings.
# We'll specifically look for the unique VLAN strings.

echo "Checking for VLAN values in database..."
VALUES_FOUND_COUNT=0
VLAN_VALUES=("VLAN-10-Corporate" "VLAN-20-Guest" "VLAN-30-VoIP" "VLAN-40-Servers" "VLAN-50-DMZ")
FOUND_VALUES_JSON="["

for val in "${VLAN_VALUES[@]}"; do
    # We search in the whole DB text for these specific strings if we don't know exact table
    # Or typically they are in 'dist_string_value' or 'additionalcfgvalues'
    # Let's try a broad search in specific likely tables first, then fallback
    
    # Try finding it in the configuration values table
    # We use a broad grep on a dump of likely tables if specific query is hard
    # But let's try a specific query on a likely table 'additionalcfgvalues' or 'element'
    
    # Safer: Check if the string exists in the database output of a dump of recent config
    # We'll assume if the field exists, values are likely in a related table.
    # Let's count occurrences of the string in the entire DB dump (limited to config tables)
    # This is expensive, so let's try a smarter query.
    
    # In SDP, pick list values are often in `sddomainvalue` or `column_disp_value`
    # Let's simply grep for the string in a pg_dump of the configuration schema.
    
    if sdp_db_exec "SELECT 1 FROM additionalcfgvalues WHERE value ILIKE '%$val%' UNION SELECT 1 FROM sddomainvalue WHERE value ILIKE '%$val%';" | grep -q "1"; then
        VALUES_FOUND_COUNT=$((VALUES_FOUND_COUNT + 1))
        FOUND_VALUES_JSON="${FOUND_VALUES_JSON}\"$val\","
    else
        # Fallback: check if the string was entered at all (e.g. description)
        # But for scoring, we want it as a value. 
        # We'll stick to the query above.
        true
    fi
done

# Fix JSON comma
if [ "$FOUND_VALUES_JSON" != "[" ]; then
    FOUND_VALUES_JSON="${FOUND_VALUES_JSON%,}]"
else
    FOUND_VALUES_JSON="[]"
fi

# 4. Check if SDP is running
APP_RUNNING="false"
if pgrep -f "java" | grep -q "ManageEngine"; then
    APP_RUNNING="true"
fi

# 5. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
PRE_EXISTING=$(cat /tmp/pre_existing_field.txt 2>/dev/null || echo "false")

# Parse FIELD_DATA (pipe separated or similar from psql)
# psql -A -t output usually: value
# If multiple columns: col1|col2|col3
FIELD_EXISTS="false"
IS_MANDATORY="unknown"
DESCRIPTION=""

if [ -n "$FIELD_DATA" ]; then
    FIELD_EXISTS="true"
    # Basic parsing assuming the query returned one row
    # FIELD_DATA might look like: "Affected Network Segment|f|Network VLAN segment..."
    IS_MANDATORY=$(echo "$FIELD_DATA" | cut -d'|' -f2)
    DESCRIPTION=$(echo "$FIELD_DATA" | cut -d'|' -f3)
fi

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "pre_existing_field": $PRE_EXISTING,
    "field_exists": $FIELD_EXISTS,
    "field_data_raw": "$(echo "$FIELD_DATA" | sed 's/"/\\"/g')",
    "is_mandatory_db": "$IS_MANDATORY",
    "description_db": "$(echo "$DESCRIPTION" | sed 's/"/\\"/g')",
    "values_found_count": $VALUES_FOUND_COUNT,
    "found_values": $FOUND_VALUES_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 7. Move Result File
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="