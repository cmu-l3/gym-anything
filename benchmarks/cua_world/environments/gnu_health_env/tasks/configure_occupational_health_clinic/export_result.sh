#!/bin/bash
echo "=== Exporting configure_occupational_health_clinic result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot before checking state
take_screenshot /tmp/clinic_final_state.png

# Load baselines
BASELINE_PARTY=$(cat /tmp/clinic_baseline_party 2>/dev/null || echo "0")
BASELINE_INST=$(cat /tmp/clinic_baseline_inst 2>/dev/null || echo "0")
BASELINE_WARD=$(cat /tmp/clinic_baseline_ward 2>/dev/null || echo "0")
BASELINE_BED=$(cat /tmp/clinic_baseline_bed 2>/dev/null || echo "0")

# --- Check 1: Institution (Party -> Institution) ---
# Check if a new party was created with the correct name
INST_PARTY_ID=$(gnuhealth_db_query "SELECT id FROM party_party WHERE name ILIKE '%PetroChem%' AND id > $BASELINE_PARTY ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')

INST_FOUND="false"
INST_ID=""
if [ -n "$INST_PARTY_ID" ]; then
    # Check if this party was registered as an institution
    INST_ID=$(gnuhealth_db_query "SELECT id FROM gnuhealth_institution WHERE name = $INST_PARTY_ID AND id > $BASELINE_INST ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')
    if [ -n "$INST_ID" ]; then
        INST_FOUND="true"
    fi
fi
echo "Institution found: $INST_FOUND (ID: $INST_ID)"

# --- Check 2: Hospital Ward ---
WARD_FOUND="false"
WARD_ID=""
WARD_LINKED_TO_INST="false"

# Query the ward. 'institution' is the foreign key to gnuhealth_institution
WARD_RECORD=$(gnuhealth_db_query "SELECT id, institution FROM gnuhealth_hospital_ward WHERE name ILIKE '%Decontamination%' AND id > $BASELINE_WARD ORDER BY id DESC LIMIT 1" | head -1)

if [ -n "$WARD_RECORD" ]; then
    WARD_FOUND="true"
    WARD_ID=$(echo "$WARD_RECORD" | awk -F'|' '{print $1}' | tr -d '[:space:]')
    WARD_INST_FK=$(echo "$WARD_RECORD" | awk -F'|' '{print $2}' | tr -d '[:space:]')
    
    if [ "$WARD_INST_FK" = "$INST_ID" ] && [ -n "$INST_ID" ]; then
        WARD_LINKED_TO_INST="true"
    fi
fi
echo "Ward found: $WARD_FOUND (Linked to Inst: $WARD_LINKED_TO_INST)"

# --- Check 3: Hospital Beds ---
BED1_FOUND="false"
BED1_LINKED="false"

BED1_RECORD=$(gnuhealth_db_query "SELECT id, ward FROM gnuhealth_hospital_bed WHERE name = 'DECON-1' AND id > $BASELINE_BED ORDER BY id DESC LIMIT 1" | head -1)
if [ -n "$BED1_RECORD" ]; then
    BED1_FOUND="true"
    BED1_WARD_FK=$(echo "$BED1_RECORD" | awk -F'|' '{print $2}' | tr -d '[:space:]')
    if [ "$BED1_WARD_FK" = "$WARD_ID" ] && [ -n "$WARD_ID" ]; then
        BED1_LINKED="true"
    fi
fi
echo "Bed 1 (DECON-1) found: $BED1_FOUND (Linked to Ward: $BED1_LINKED)"

BED2_FOUND="false"
BED2_LINKED="false"

BED2_RECORD=$(gnuhealth_db_query "SELECT id, ward FROM gnuhealth_hospital_bed WHERE name = 'DECON-2' AND id > $BASELINE_BED ORDER BY id DESC LIMIT 1" | head -1)
if [ -n "$BED2_RECORD" ]; then
    BED2_FOUND="true"
    BED2_WARD_FK=$(echo "$BED2_RECORD" | awk -F'|' '{print $2}' | tr -d '[:space:]')
    if [ "$BED2_WARD_FK" = "$WARD_ID" ] && [ -n "$WARD_ID" ]; then
        BED2_LINKED="true"
    fi
fi
echo "Bed 2 (DECON-2) found: $BED2_FOUND (Linked to Ward: $BED2_LINKED)"

# Export to JSON
TEMP_JSON=$(mktemp /tmp/clinic_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "inst_found": $INST_FOUND,
    "ward_found": $WARD_FOUND,
    "ward_linked_to_inst": $WARD_LINKED_TO_INST,
    "bed1_found": $BED1_FOUND,
    "bed1_linked_to_ward": $BED1_LINKED,
    "bed2_found": $BED2_FOUND,
    "bed2_linked_to_ward": $BED2_LINKED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Use sudo to prevent permission denied if moving across contexts
rm -f /tmp/configure_clinic_result.json 2>/dev/null || sudo rm -f /tmp/configure_clinic_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/configure_clinic_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/configure_clinic_result.json
chmod 666 /tmp/configure_clinic_result.json 2>/dev/null || sudo chmod 666 /tmp/configure_clinic_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "JSON Result exported to /tmp/configure_clinic_result.json:"
cat /tmp/configure_clinic_result.json
echo "=== Export Complete ==="