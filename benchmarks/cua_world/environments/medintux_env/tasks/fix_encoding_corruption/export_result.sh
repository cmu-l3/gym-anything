#!/bin/bash
echo "=== Exporting fix_encoding_corruption results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check database state
# We export the specific records we care about to JSON
# We look for both the corrected versions and any remaining corrupted versions

# Define output file
TEMP_JSON=$(mktemp /tmp/db_result.XXXXXX.json)

echo "{" > "$TEMP_JSON"
echo "  \"timestamp\": $TASK_END," >> "$TEMP_JSON"

# Check report file
REPORT_PATH="/home/ga/Documents/encoding_fix_report.txt"
if [ -f "$REPORT_PATH" ]; then
    echo "  \"report_exists\": true," >> "$TEMP_JSON"
    echo "  \"report_size\": $(stat -c%s "$REPORT_PATH")," >> "$TEMP_JSON"
    # Read first 10 lines of report safely for verification
    REPORT_CONTENT=$(head -n 20 "$REPORT_PATH" | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}')
    echo "  \"report_content\": \"$REPORT_CONTENT\"," >> "$TEMP_JSON"
else
    echo "  \"report_exists\": false," >> "$TEMP_JSON"
fi

# Count remaining corrupted patterns in relevant columns
# Pattern: Ã©, Ã¨, Ãª, Ã§, Ã¢, Ã‰ (repesented as %Ã% usually works for finding them)
CORRUPT_INDEX=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_NomDos LIKE '%Ã%' OR FchGnrl_Prenom LIKE '%Ã%'")
CORRUPT_FCHPAT=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM fchpat WHERE FchPat_NomFille LIKE '%Ã%' OR FchPat_Adresse LIKE '%Ã%' OR FchPat_Ville LIKE '%Ã%'")

echo "  \"remaining_corrupted_index\": ${CORRUPT_INDEX:-0}," >> "$TEMP_JSON"
echo "  \"remaining_corrupted_fchpat\": ${CORRUPT_FCHPAT:-0}," >> "$TEMP_JSON"

# Check total count (to detect deletion)
FINAL_COUNT=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_Type='Dossier'")
INITIAL_COUNT=$(cat /tmp/initial_patient_count.txt 2>/dev/null || echo "0")
echo "  \"initial_count\": ${INITIAL_COUNT:-0}," >> "$TEMP_JSON"
echo "  \"final_count\": ${FINAL_COUNT:-0}," >> "$TEMP_JSON"

# Export specific patients' data for precise verification
# We query by the EXPECTED correct names OR the original corrupted names to find them
echo "  \"patients\": [" >> "$TEMP_JSON"

PATIENTS=("BERENGER" "LEFEVRE" "GONÇALVES" "GONÃ§ALVES" "PREVOST" "FORTIER" "BEAUPRÉ" "BEAUPRÃ©")
FIRST=true

for NAME in "${PATIENTS[@]}"; do
    # Get Index data
    RES_INDEX=$(mysql -u root DrTuxTest -N -e "SELECT FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom FROM IndexNomPrenom WHERE FchGnrl_NomDos='$NAME'" 2>/dev/null || true)
    
    if [ -n "$RES_INDEX" ]; then
        while IFS=$'\t' read -r guid nom prenom; do
            if [ "$FIRST" = true ]; then FIRST=false; else echo "," >> "$TEMP_JSON"; fi
            
            # Get fchpat data for this GUID
            RES_FCHPAT=$(mysql -u root DrTuxTest -N -e "SELECT FchPat_Adresse, FchPat_Ville FROM fchpat WHERE FchPat_GUID_Doss='$guid'" 2>/dev/null || true)
            IFS=$'\t' read -r adresse ville <<< "$RES_FCHPAT"
            
            # Escape JSON strings
            nom_esc=$(echo "$nom" | sed 's/"/\\"/g')
            prenom_esc=$(echo "$prenom" | sed 's/"/\\"/g')
            adresse_esc=$(echo "$adresse" | sed 's/"/\\"/g')
            ville_esc=$(echo "$ville" | sed 's/"/\\"/g')
            
            echo "    {" >> "$TEMP_JSON"
            echo "      \"guid\": \"$guid\"," >> "$TEMP_JSON"
            echo "      \"nom\": \"$nom_esc\"," >> "$TEMP_JSON"
            echo "      \"prenom\": \"$prenom_esc\"," >> "$TEMP_JSON"
            echo "      \"adresse\": \"$adresse_esc\"," >> "$TEMP_JSON"
            echo "      \"ville\": \"$ville_esc\"" >> "$TEMP_JSON"
            echo "    }" >> "$TEMP_JSON"
        done <<< "$RES_INDEX"
    fi
done

echo "  ]" >> "$TEMP_JSON"
echo "}" >> "$TEMP_JSON"

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="