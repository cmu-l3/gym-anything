#!/bin/bash
echo "=== Exporting restore_patient_from_backup results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Patient details to check
PATIENT_NOM="SOUBIROUS"
PATIENT_PRENOM="Bernadette"

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check Database State
echo "Checking database for restored patient..."

# Get current count
CURRENT_COUNT=$(mysql -u root DrTuxTest -N -e \
    "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_NomDos='$PATIENT_NOM' AND FchGnrl_Prenom='$PATIENT_PRENOM'" \
    2>/dev/null || echo "0")

# Get current details (GUID, DOB, Address)
# We join tables to ensure both records were restored
CURRENT_DATA=$(mysql -u root DrTuxTest -N -e \
    "SELECT i.FchGnrl_IDDos, f.FchPat_Nee, f.FchPat_Ville \
     FROM IndexNomPrenom i \
     LEFT JOIN fchpat f ON i.FchGnrl_IDDos = f.FchPat_GUID_Doss \
     WHERE i.FchGnrl_NomDos='$PATIENT_NOM' AND i.FchGnrl_Prenom='$PATIENT_PRENOM' \
     LIMIT 1" 2>/dev/null || echo "NULL NULL NULL")

# Parse SQL result
# If record missing, these will be empty or NULL
CURRENT_GUID=$(echo "$CURRENT_DATA" | awk '{print $1}')
CURRENT_DOB=$(echo "$CURRENT_DATA" | awk '{print $2}')
CURRENT_VILLE=$(echo "$CURRENT_DATA" | awk '{print $3}')

# 3. Get Ground Truth
GROUND_TRUTH_GUID=""
if [ -f "/var/lib/medintux_task/ground_truth_guid.txt" ]; then
    GROUND_TRUTH_GUID=$(cat /var/lib/medintux_task/ground_truth_guid.txt)
fi

# 4. Check Tables Individually (to give specific feedback)
INDEX_COUNT=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_NomDos='$PATIENT_NOM'" 2>/dev/null || echo 0)
DETAILS_COUNT=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM fchpat WHERE FchPat_NomFille='$PATIENT_NOM' AND FchPat_GUID_Doss='$CURRENT_GUID'" 2>/dev/null || echo 0)

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/restore_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_found": $(( CURRENT_COUNT > 0 ? 1 : 0 )),
    "index_table_count": $INDEX_COUNT,
    "details_table_count": $DETAILS_COUNT,
    "current_guid": "$CURRENT_GUID",
    "expected_guid": "$GROUND_TRUTH_GUID",
    "current_dob": "$CURRENT_DOB",
    "current_city": "$CURRENT_VILLE",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json