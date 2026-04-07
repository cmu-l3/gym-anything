#!/bin/bash
echo "=== Exporting register_health_professional result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM verification
take_screenshot /tmp/task_final_state.png

# Read setup metrics
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_HP_COUNT=$(cat /tmp/initial_hp_count.txt 2>/dev/null || echo "0")
INITIAL_PARTY_COUNT=$(cat /tmp/initial_party_count.txt 2>/dev/null || echo "0")

# 1. Check if Party record exists
PARTY_ID=$(gnuhealth_db_query "
    SELECT id FROM party_party 
    WHERE name ILIKE '%Maria%' AND lastname ILIKE '%Santos%' 
    ORDER BY id DESC LIMIT 1
" 2>/dev/null | tr -d '[:space:]')

PARTY_FOUND="false"
PARTY_CREATED_EPOCH=0
if [ -n "$PARTY_ID" ] && [ "$PARTY_ID" -gt 0 ] 2>/dev/null; then
    PARTY_FOUND="true"
    PARTY_CREATED_EPOCH=$(gnuhealth_db_query "SELECT EXTRACT(EPOCH FROM create_date)::bigint FROM party_party WHERE id = $PARTY_ID" 2>/dev/null | tr -d '[:space:]')
fi

# 2. Check if Health Professional record exists
HP_FOUND="false"
HP_ID=""
LICENSE_FOUND="false"
LICENSE_VALUE=""

if [ "$PARTY_FOUND" = "true" ]; then
    # In GNU Health, healthprofessional connects to party_party usually via the 'name' column (FK to party_party.id)
    HP_ID=$(gnuhealth_db_query "SELECT id FROM gnuhealth_healthprofessional WHERE name = $PARTY_ID ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')
    
    # Try alternative column 'party' if schema differs
    if [ -z "$HP_ID" ]; then
        HP_ID=$(gnuhealth_db_query "SELECT id FROM gnuhealth_healthprofessional WHERE party = $PARTY_ID ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')
    fi

    if [ -n "$HP_ID" ] && [ "$HP_ID" -gt 0 ] 2>/dev/null; then
        HP_FOUND="true"

        # Check for Professional ID (MED20247891) in HP record
        for col in puid code name; do
            val=$(gnuhealth_db_query "SELECT ${col} FROM gnuhealth_healthprofessional WHERE id = $HP_ID" 2>/dev/null | tr -d '[:space:]')
            if echo "$val" | grep -qi "MED20247891"; then
                LICENSE_FOUND="true"
                LICENSE_VALUE="$val"
                break
            fi
        done
        
        # Check Party record for code/ref if not found
        if [ "$LICENSE_FOUND" = "false" ]; then
            for col in ref code; do
                val=$(gnuhealth_db_query "SELECT ${col} FROM party_party WHERE id = $PARTY_ID" 2>/dev/null | tr -d '[:space:]')
                if echo "$val" | grep -qi "MED20247891"; then
                    LICENSE_FOUND="true"
                    LICENSE_VALUE="$val"
                    break
                fi
            done
        fi
    fi
fi

# 3. Check current counts
CURRENT_HP_COUNT=$(gnuhealth_db_query "SELECT COUNT(*) FROM gnuhealth_healthprofessional" | tr -d '[:space:]')
CURRENT_PARTY_COUNT=$(gnuhealth_db_query "SELECT COUNT(*) FROM party_party" | tr -d '[:space:]')

# Build JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "initial_hp_count": $INITIAL_HP_COUNT,
    "current_hp_count": ${CURRENT_HP_COUNT:-0},
    "initial_party_count": $INITIAL_PARTY_COUNT,
    "current_party_count": ${CURRENT_PARTY_COUNT:-0},
    "party_found": $PARTY_FOUND,
    "party_id": "${PARTY_ID:-}",
    "party_created_epoch": ${PARTY_CREATED_EPOCH:-0},
    "hp_found": $HP_FOUND,
    "hp_id": "${HP_ID:-}",
    "license_found": $LICENSE_FOUND,
    "license_value": "${LICENSE_VALUE:-}"
}
EOF

# Move to final location
rm -f /tmp/register_health_professional_result.json 2>/dev/null || sudo rm -f /tmp/register_health_professional_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/register_health_professional_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/register_health_professional_result.json
chmod 666 /tmp/register_health_professional_result.json 2>/dev/null || sudo chmod 666 /tmp/register_health_professional_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/register_health_professional_result.json"
cat /tmp/register_health_professional_result.json

echo "=== Export complete ==="