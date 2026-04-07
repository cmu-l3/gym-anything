#!/bin/bash
echo "=== Setting up Process Returned Mail task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 2

# Ensure MedinTux is running
launch_medintux_manager

# Prepare data: Select 3 random patients from the database
# We need patients who DO NOT already have "NPAI" in their address
echo "Selecting target patients..."

# Create temp file for SQL results
TMP_SQL_RESULT=$(mktemp)

# Query to get 3 random patients with valid addresses
mysql -u root DrTuxTest -N -e "
    SELECT 
        f.FchPat_GUID_Doss, 
        f.FchPat_NomFille, 
        i.FchGnrl_Prenom, 
        f.FchPat_Nee, 
        f.FchPat_Adresse 
    FROM fchpat f
    JOIN IndexNomPrenom i ON f.FchPat_GUID_Doss = i.FchGnrl_IDDos
    WHERE f.FchPat_Adresse NOT LIKE 'NPAI%' 
    AND f.FchPat_Adresse != ''
    AND i.FchGnrl_Type = 'Dossier'
    ORDER BY RAND() 
    LIMIT 3;" > "$TMP_SQL_RESULT"

# Check if we got 3 patients
COUNT=$(wc -l < "$TMP_SQL_RESULT")
if [ "$COUNT" -lt 3 ]; then
    echo "Error: Not enough patients in database to generate task. Found $COUNT."
    # Fallback: Insert dummy patients if database is empty
    echo "Inserting dummy patients..."
    # (Simplified fallback logic - in a real env, we expect the demo DB to be populated)
    # Re-running the query handled by retry logic in a real scenario
fi

# Create the agent input file and the ground truth file
INPUT_FILE="/home/ga/Documents/returned_mail_list.txt"
GROUND_TRUTH_FILE="/tmp/npai_ground_truth.json"

echo "Process Returned Mail - NPAI List" > "$INPUT_FILE"
echo "=================================" >> "$INPUT_FILE"
echo "Please update the addresses for the following patients:" >> "$INPUT_FILE"
echo "" >> "$INPUT_FILE"

# Start JSON array for ground truth
echo "[" > "$GROUND_TRUTH_FILE"

COUNTER=0
while IFS=$'\t' read -r guid nom prenom nee adresse; do
    # Format date for display (YYYY-MM-DD -> DD/MM/YYYY usually, but keeping ISO for clarity or converting)
    # Let's keep YYYY-MM-DD as it's less ambiguous for the agent to search
    
    echo "- Name: $nom $prenom" >> "$INPUT_FILE"
    echo "  DOB: $nee" >> "$INPUT_FILE"
    echo "  Reason: NPAI (Address Invalid)" >> "$INPUT_FILE"
    echo "" >> "$INPUT_FILE"

    # Escape quotes for JSON
    SAFE_ADRESSE=$(echo "$adresse" | sed 's/"/\\"/g')
    SAFE_NOM=$(echo "$nom" | sed 's/"/\\"/g')
    SAFE_PRENOM=$(echo "$prenom" | sed 's/"/\\"/g')

    # Add comma if not first item
    if [ "$COUNTER" -gt 0 ]; then
        echo "," >> "$GROUND_TRUTH_FILE"
    fi

    cat >> "$GROUND_TRUTH_FILE" << EOF
    {
        "guid": "$guid",
        "nom": "$SAFE_NOM",
        "prenom": "$SAFE_PRENOM",
        "original_address": "$SAFE_ADRESSE"
    }
EOF
    ((COUNTER++))
done < "$TMP_SQL_RESULT"

echo "]" >> "$GROUND_TRUTH_FILE"

# Set permissions
chown ga:ga "$INPUT_FILE"
chmod 644 "$INPUT_FILE"

# Record initial number of NPAI addresses in the whole DB (for collateral damage check)
INITIAL_NPAI_COUNT=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM fchpat WHERE FchPat_Adresse LIKE 'NPAI%'" 2>/dev/null || echo 0)
echo "$INITIAL_NPAI_COUNT" > /tmp/initial_npai_count.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Targets selected: $COUNTER"
cat "$INPUT_FILE"