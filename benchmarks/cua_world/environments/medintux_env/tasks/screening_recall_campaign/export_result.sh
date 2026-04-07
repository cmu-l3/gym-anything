#!/bin/bash
echo "=== Exporting Screening Recall Campaign Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CSV_PATH="/home/ga/Documents/screening_recall_list.csv"
SUMMARY_PATH="/home/ga/Documents/screening_recall_summary.txt"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check output files
CSV_EXISTS="false"
SUMMARY_EXISTS="false"
CSV_SIZE=0

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c%s "$CSV_PATH" 2>/dev/null || echo "0")
fi

if [ -f "$SUMMARY_PATH" ]; then
    SUMMARY_EXISTS="true"
fi

# Calculate GROUND TRUTH from database
echo "Calculating ground truth from database..."

# Query: Total Eligible (Female, 1950-1974)
GT_TOTAL_ELIGIBLE=$(mysql -u root DrTuxTest -N -e "
    SELECT COUNT(*) FROM fchpat 
    WHERE FchPat_Sexe='F' 
    AND FchPat_Nee >= '1950-01-01' 
    AND FchPat_Nee <= '1974-12-31'
" 2>/dev/null || echo "0")

# Query: Contact Complet (Eligible + Address + CP + City not empty)
GT_CONTACT_COMPLET=$(mysql -u root DrTuxTest -N -e "
    SELECT COUNT(*) FROM fchpat 
    WHERE FchPat_Sexe='F' 
    AND FchPat_Nee >= '1950-01-01' 
    AND FchPat_Nee <= '1974-12-31'
    AND FchPat_Adresse != '' AND FchPat_Adresse IS NOT NULL
    AND FchPat_CP != '' AND FchPat_CP IS NOT NULL
    AND FchPat_Ville != '' AND FchPat_Ville IS NOT NULL
" 2>/dev/null || echo "0")

# Query: Avec Telephone (Eligible + Tel not empty)
GT_AVEC_TELEPHONE=$(mysql -u root DrTuxTest -N -e "
    SELECT COUNT(*) FROM fchpat 
    WHERE FchPat_Sexe='F' 
    AND FchPat_Nee >= '1950-01-01' 
    AND FchPat_Nee <= '1974-12-31'
    AND FchPat_Tel1 != '' AND FchPat_Tel1 IS NOT NULL
" 2>/dev/null || echo "0")

# Calculate remaining metrics
GT_CONTACT_INCOMPLET=$((GT_TOTAL_ELIGIBLE - GT_CONTACT_COMPLET))
GT_SANS_TELEPHONE=$((GT_TOTAL_ELIGIBLE - GT_AVEC_TELEPHONE))

echo "Ground Truth Calculated:"
echo "  Total: $GT_TOTAL_ELIGIBLE"
echo "  Complete Contact: $GT_CONTACT_COMPLET"
echo "  With Phone: $GT_AVEC_TELEPHONE"

# Prepare files for copy_from_env (copy to /tmp with known names)
cp "$CSV_PATH" /tmp/user_recall_list.csv 2>/dev/null || true
cp "$SUMMARY_PATH" /tmp/user_recall_summary.txt 2>/dev/null || true
chmod 644 /tmp/user_recall_list.csv /tmp/user_recall_summary.txt 2>/dev/null || true

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "summary_exists": $SUMMARY_EXISTS,
    "ground_truth": {
        "total_eligible": $GT_TOTAL_ELIGIBLE,
        "contact_complet": $GT_CONTACT_COMPLET,
        "contact_incomplet": $GT_CONTACT_INCOMPLET,
        "avec_telephone": $GT_AVEC_TELEPHONE,
        "sans_telephone": $GT_SANS_TELEPHONE
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="