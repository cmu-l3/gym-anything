#!/bin/bash
echo "=== Exporting Task Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper to query specific fields for a patient
# Usage: get_patient_data NOM PRENOM
get_patient_json() {
    local nom="$1"
    local prenom="$2"
    
    # Query specific fields from fchpat joined with index
    # Note: Using GROUP_CONCAT to handle potential duplicates (though setup cleans them)
    mysql -u root DrTuxTest -N -e "
        SELECT 
            JSON_OBJECT(
                'exists', TRUE,
                'guid', f.FchPat_GUID_Doss,
                'dob', f.FchPat_Nee,
                'sex', f.FchPat_Sexe,
                'address', f.FchPat_Adresse,
                'city', f.FchPat_Ville,
                'phone', f.FchPat_Tel1,
                'zip', f.FchPat_CP
            )
        FROM fchpat f
        JOIN IndexNomPrenom i ON f.FchPat_GUID_Doss = i.FchGnrl_IDDos
        WHERE i.FchGnrl_NomDos = '$nom' AND i.FchGnrl_Prenom = '$prenom'
        LIMIT 1;
    " 2>/dev/null || echo "{\"exists\": false}"
}

echo "Querying database for Child 1 (Paul)..."
JSON_CHILD1=$(get_patient_json "LEGRAND" "Paul")
if [ -z "$JSON_CHILD1" ]; then JSON_CHILD1="{\"exists\": false}"; fi

echo "Querying database for Child 2 (Juliette)..."
JSON_CHILD2=$(get_patient_json "LEGRAND" "Juliette")
if [ -z "$JSON_CHILD2" ]; then JSON_CHILD2="{\"exists\": false}"; fi

# Check if app is running
APP_RUNNING=$(pgrep -f "Manager.exe" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "child1": $JSON_CHILD1,
    "child2": $JSON_CHILD2
}
EOF

# Move to standard location with permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="