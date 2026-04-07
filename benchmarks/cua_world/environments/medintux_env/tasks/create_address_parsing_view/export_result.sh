#!/bin/bash
echo "=== Exporting Create Address Parsing View Result ==="

# 1. Record basic file stats
OUTPUT_PATH="/home/ga/Documents/parsed_addresses.csv"
CSV_EXISTS="false"
CSV_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$OUTPUT_PATH")
fi

# 2. Verify View Logic via Injection Testing (Running inside container)
# We inject a specific test case into the DB, query the agent's view, and check if it parses correctly.

TEST_GUID="TEST_VERIFY_999"
TEST_NOM="TESTMAN"
TEST_PRENOM="Johnny"
TEST_ADDR="9999 Verification Boulevard"
EXPECTED_NUM="9999"
EXPECTED_VOIE="Verification Boulevard"

VIEW_EXISTS="false"
COLUMNS_CORRECT="false"
LOGIC_CORRECT="false"
ACTUAL_NUM="NULL"
ACTUAL_VOIE="NULL"

# Check if view exists
if mysql -u root DrTuxTest -e "SHOW CREATE VIEW vue_adresse_parsed" > /dev/null 2>&1; then
    VIEW_EXISTS="true"
    
    # Check columns
    COLS=$(mysql -u root DrTuxTest -N -e "DESCRIBE vue_adresse_parsed;" | awk '{print $1}' | tr '\n' ',')
    # Expected roughly: guid,nom_complet,adresse_brute,num_voie,nom_voie,
    if [[ "$COLS" == *"num_voie"* && "$COLS" == *"nom_voie"* && "$COLS" == *"adresse_brute"* ]]; then
        COLUMNS_CORRECT="true"
    fi

    # INJECTION TEST
    echo "Injecting test data..."
    # Clean up any residual test data first
    mysql -u root DrTuxTest -e "DELETE FROM fchpat WHERE FchPat_GUID_Doss='$TEST_GUID';" 2>/dev/null || true
    mysql -u root DrTuxTest -e "DELETE FROM IndexNomPrenom WHERE FchGnrl_IDDos='$TEST_GUID';" 2>/dev/null || true

    # Insert into IndexNomPrenom
    mysql -u root DrTuxTest -e "INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) VALUES ('$TEST_GUID', '$TEST_NOM', '$TEST_PRENOM', 'Dossier');"
    
    # Insert into fchpat
    mysql -u root DrTuxTest -e "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe, FchPat_Adresse) VALUES ('$TEST_GUID', '', '1980-01-01', 'M', '$TEST_ADDR');"

    # Query the view
    echo "Querying view..."
    RESULT_JSON=$(mysql -u root DrTuxTest -N -e "SELECT num_voie, nom_voie FROM vue_adresse_parsed WHERE guid='$TEST_GUID'")
    
    # Cleanup test data immediately
    mysql -u root DrTuxTest -e "DELETE FROM fchpat WHERE FchPat_GUID_Doss='$TEST_GUID';" 2>/dev/null || true
    mysql -u root DrTuxTest -e "DELETE FROM IndexNomPrenom WHERE FchGnrl_IDDos='$TEST_GUID';" 2>/dev/null || true

    # Parse result (Tab separated)
    read -r ACTUAL_NUM ACTUAL_VOIE <<< "$RESULT_JSON"
    
    echo "Injection Result: NUM='$ACTUAL_NUM', VOIE='$ACTUAL_VOIE'"
    
    if [[ "$ACTUAL_NUM" == "$EXPECTED_NUM" ]] && [[ "$ACTUAL_VOIE" == "$EXPECTED_VOIE" ]]; then
        LOGIC_CORRECT="true"
    fi
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "view_exists": $VIEW_EXISTS,
    "columns_correct": $COLUMNS_CORRECT,
    "logic_correct": $LOGIC_CORRECT,
    "test_case": {
        "input": "$TEST_ADDR",
        "expected_num": "$EXPECTED_NUM",
        "expected_voie": "$EXPECTED_VOIE",
        "actual_num": "$ACTUAL_NUM",
        "actual_voie": "$ACTUAL_VOIE"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="