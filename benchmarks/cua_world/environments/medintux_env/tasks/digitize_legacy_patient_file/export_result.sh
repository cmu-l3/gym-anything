#!/bin/bash
echo "=== Exporting digitize_legacy_patient_file results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture final state screenshot
take_screenshot /tmp/task_final.png

# 2. Query Database for Patient Existence and Details
# We look for Sarah CONNOR
echo "Querying patient data..."
PATIENT_DATA=$(mysql -u root DrTuxTest -N -e \
    "SELECT i.FchGnrl_IDDos, f.FchPat_Nee, f.FchPat_Adresse, f.FchPat_Ville \
     FROM IndexNomPrenom i \
     LEFT JOIN fchpat f ON i.FchGnrl_IDDos = f.FchPat_GUID_Doss \
     WHERE i.FchGnrl_NomDos='CONNOR' AND i.FchGnrl_Prenom='Sarah' \
     LIMIT 1" 2>/dev/null)

PATIENT_FOUND="false"
PATIENT_GUID=""
PATIENT_DOB=""
PATIENT_ADDR=""
PATIENT_CITY=""

if [ -n "$PATIENT_DATA" ]; then
    PATIENT_FOUND="true"
    PATIENT_GUID=$(echo "$PATIENT_DATA" | cut -f1)
    PATIENT_DOB=$(echo "$PATIENT_DATA" | cut -f2)
    PATIENT_ADDR=$(echo "$PATIENT_DATA" | cut -f3)
    PATIENT_CITY=$(echo "$PATIENT_DATA" | cut -f4)
    echo "Patient found: $PATIENT_GUID"
else
    echo "Patient NOT found"
fi

# 3. Query Clinical Notes (Documents)
# MedinTux stores document content in RubriquesBlobs linked to the patient GUID
# We fetch all text blobs associated with this patient
NOTE_FOUND="false"
NOTE_CONTENT=""
KEYWORDS_FOUND_COUNT=0
HISTORY_FOUND="false"
ALLERGY_FOUND="false"

if [ "$PATIENT_FOUND" = "true" ]; then
    echo "Querying document content for GUID: $PATIENT_GUID"
    
    # Get all blob data for this patient. 
    # CAST(RbDate_Data AS CHAR) converts the blob to string. 
    # MedinTux might store RTF, but grep should still find the words.
    ALL_NOTES=$(mysql -u root DrTuxTest -N -e \
        "SELECT CAST(RbDate_Data AS CHAR) FROM RubriquesBlobs WHERE RbDate_IDDos='$PATIENT_GUID'" \
        2>/dev/null)
    
    if [ -n "$ALL_NOTES" ]; then
        NOTE_FOUND="true"
        # Sanitize for JSON (basic escaping)
        NOTE_CONTENT=$(echo "$ALL_NOTES" | tr -d '\000-\037' | sed 's/"/\\"/g')
        
        # Check for keywords roughly in bash to populate debug info
        # (Real rigorous check happens in python verifier)
        if echo "$ALL_NOTES" | grep -qi "Appendicectomy"; then ((KEYWORDS_FOUND_COUNT++)); fi
        if echo "$ALL_NOTES" | grep -qi "Fracture"; then ((KEYWORDS_FOUND_COUNT++)); fi
        if echo "$ALL_NOTES" | grep -qi "Latex"; then ((KEYWORDS_FOUND_COUNT++)); fi
        if echo "$ALL_NOTES" | grep -qi "Penicillin"; then ((KEYWORDS_FOUND_COUNT++)); fi
    fi
fi

# 4. Check timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
NOW=$(date +%s)

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "export_timestamp": $NOW,
    "patient_found": $PATIENT_FOUND,
    "patient_guid": "$PATIENT_GUID",
    "patient_dob": "$PATIENT_DOB",
    "patient_address": "$PATIENT_ADDR",
    "patient_city": "$PATIENT_CITY",
    "note_found": $NOTE_FOUND,
    "note_content_preview": "${NOTE_CONTENT:0:1000}", 
    "full_note_content": "$NOTE_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json