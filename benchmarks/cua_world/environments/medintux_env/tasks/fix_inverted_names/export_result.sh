#!/bin/bash
echo "=== Exporting fix_inverted_names result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# GUIDs to check
GUID1="FIX-INV-001"
GUID2="FIX-INV-002"
GUID3="FIX-INV-003"

# Helper to query as JSON string
query_json() {
    mysql -u root DrTuxTest -N -B -e "$1" 2>/dev/null | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read().strip()))'
}

# 1. Check IndexNomPrenom for Corrected Names associated with original GUIDs
# We expect: GUID1 -> Nom=MARTIN, Prenom=Sophie
R1_INDEX=$(mysql -u root DrTuxTest -N -B -e "SELECT FchGnrl_NomDos, FchGnrl_Prenom FROM IndexNomPrenom WHERE FchGnrl_IDDos='$GUID1'" 2>/dev/null)
R2_INDEX=$(mysql -u root DrTuxTest -N -B -e "SELECT FchGnrl_NomDos, FchGnrl_Prenom FROM IndexNomPrenom WHERE FchGnrl_IDDos='$GUID2'" 2>/dev/null)
R3_INDEX=$(mysql -u root DrTuxTest -N -B -e "SELECT FchGnrl_NomDos, FchGnrl_Prenom FROM IndexNomPrenom WHERE FchGnrl_IDDos='$GUID3'" 2>/dev/null)

# 2. Check fchpat for Corrected Names associated with original GUIDs
# We expect: GUID1 -> NomFille=MARTIN
R1_FCHPAT=$(mysql -u root DrTuxTest -N -B -e "SELECT FchPat_NomFille FROM fchpat WHERE FchPat_GUID_Doss='$GUID1'" 2>/dev/null)
R2_FCHPAT=$(mysql -u root DrTuxTest -N -B -e "SELECT FchPat_NomFille FROM fchpat WHERE FchPat_GUID_Doss='$GUID2'" 2>/dev/null)
R3_FCHPAT=$(mysql -u root DrTuxTest -N -B -e "SELECT FchPat_NomFille FROM fchpat WHERE FchPat_GUID_Doss='$GUID3'" 2>/dev/null)

# 3. Safety Check: Ensure no NEW records were created for these people with DIFFERENT GUIDs
# If the agent deleted and re-inserted, there might be a "MARTIN Sophie" with a random GUID.
DUPLICATE_CHECK=$(mysql -u root DrTuxTest -N -B -e "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_NomDos='MARTIN' AND FchGnrl_Prenom='Sophie' AND FchGnrl_IDDos != '$GUID1'" 2>/dev/null)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Construct JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'record1': {
        'guid': '$GUID1',
        'index_val': '$R1_INDEX',
        'fchpat_val': '$R1_FCHPAT'
    },
    'record2': {
        'guid': '$GUID2',
        'index_val': '$R2_INDEX',
        'fchpat_val': '$R2_FCHPAT'
    },
    'record3': {
        'guid': '$GUID3',
        'index_val': '$R3_INDEX',
        'fchpat_val': '$R3_FCHPAT'
    },
    'duplicates_found': int('$DUPLICATE_CHECK'),
    'screenshot_path': '/tmp/task_final.png'
}
print(json.dumps(result))
" > "$TEMP_JSON"

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="