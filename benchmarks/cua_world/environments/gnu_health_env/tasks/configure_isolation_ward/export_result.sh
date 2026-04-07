#!/bin/bash
echo "=== Exporting configure_isolation_ward result ==="

source /workspace/scripts/task_utils.sh

# Capture final state screenshot
take_screenshot /tmp/ward_final_state.png

# Load baselines
BASELINE_WARD_MAX=$(cat /tmp/ward_baseline_max 2>/dev/null || echo "0")
BASELINE_BED_MAX=$(cat /tmp/bed_baseline_max 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# --- Check 1: Verify the new Ward ---
WARD_RECORD=$(gnuhealth_db_query "
    SELECT id, name
    FROM gnuhealth_hospital_ward
    WHERE name ILIKE '%Airborne Infection Isolation Ward%'
      AND id > $BASELINE_WARD_MAX
    ORDER BY id DESC LIMIT 1
" 2>/dev/null | head -1)

WARD_FOUND="false"
WARD_ID="null"
WARD_NAME=""

if [ -n "$WARD_RECORD" ]; then
    WARD_FOUND="true"
    WARD_ID=$(echo "$WARD_RECORD" | awk -F'|' '{print $1}' | tr -d ' ')
    WARD_NAME=$(echo "$WARD_RECORD" | awk -F'|' '{print $2}' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
fi

# Count any newly created wards regardless of name
ANY_NEW_WARDS=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_hospital_ward
    WHERE id > $BASELINE_WARD_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- Check 2: Verify Bed 1 (AIIR-01) ---
BED1_RECORD=$(gnuhealth_db_query "
    SELECT id, name, COALESCE(ward::text, 'null')
    FROM gnuhealth_hospital_bed
    WHERE name ILIKE '%AIIR-01%'
      AND id > $BASELINE_BED_MAX
    ORDER BY id DESC LIMIT 1
" 2>/dev/null | head -1)

BED1_FOUND="false"
BED1_ID="null"
BED1_WARD_ID="null"

if [ -n "$BED1_RECORD" ]; then
    BED1_FOUND="true"
    BED1_ID=$(echo "$BED1_RECORD" | awk -F'|' '{print $1}' | tr -d ' ')
    BED1_WARD_ID=$(echo "$BED1_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
fi

# --- Check 3: Verify Bed 2 (AIIR-02) ---
BED2_RECORD=$(gnuhealth_db_query "
    SELECT id, name, COALESCE(ward::text, 'null')
    FROM gnuhealth_hospital_bed
    WHERE name ILIKE '%AIIR-02%'
      AND id > $BASELINE_BED_MAX
    ORDER BY id DESC LIMIT 1
" 2>/dev/null | head -1)

BED2_FOUND="false"
BED2_ID="null"
BED2_WARD_ID="null"

if [ -n "$BED2_RECORD" ]; then
    BED2_FOUND="true"
    BED2_ID=$(echo "$BED2_RECORD" | awk -F'|' '{print $1}' | tr -d ' ')
    BED2_WARD_ID=$(echo "$BED2_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
fi

# Count any newly created beds regardless of name
ANY_NEW_BEDS=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_hospital_bed
    WHERE id > $BASELINE_BED_MAX
" 2>/dev/null | tr -d '[:space:]')

# Ensure we cleanly output a JSON file
TEMP_JSON=$(mktemp /tmp/ward_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "export_timestamp": $(date +%s),
    "ward_found": $WARD_FOUND,
    "ward_id": "$WARD_ID",
    "ward_name": "$WARD_NAME",
    "any_new_wards_count": ${ANY_NEW_WARDS:-0},
    "bed1_found": $BED1_FOUND,
    "bed1_id": "$BED1_ID",
    "bed1_ward_id": "$BED1_WARD_ID",
    "bed2_found": $BED2_FOUND,
    "bed2_id": "$BED2_ID",
    "bed2_ward_id": "$BED2_WARD_ID",
    "any_new_beds_count": ${ANY_NEW_BEDS:-0}
}
EOF

# Move to final location safely
rm -f /tmp/configure_isolation_ward_result.json 2>/dev/null || sudo rm -f /tmp/configure_isolation_ward_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/configure_isolation_ward_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/configure_isolation_ward_result.json
chmod 666 /tmp/configure_isolation_ward_result.json 2>/dev/null || sudo chmod 666 /tmp/configure_isolation_ward_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved."
cat /tmp/configure_isolation_ward_result.json
echo "=== Export Complete ==="