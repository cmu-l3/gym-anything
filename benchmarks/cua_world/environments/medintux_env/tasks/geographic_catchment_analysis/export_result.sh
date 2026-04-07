#!/bin/bash
echo "=== Exporting Task Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Paths
OUTPUT_CSV="/home/ga/reports/catchment_analysis.csv"
GROUND_TRUTH_CSV="/tmp/ground_truth.csv"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Generate Ground Truth
# We execute the EXACT logic required against the DB to get the reference truth
echo "Generating ground truth..."
mysql -u root DrTuxTest -B -e "
SELECT 
    FchPat_CP as postal_code,
    CASE 
        WHEN TIMESTAMPDIFF(YEAR, FchPat_Nee, CURDATE()) <= 17 THEN '0-17'
        WHEN TIMESTAMPDIFF(YEAR, FchPat_Nee, CURDATE()) BETWEEN 18 AND 39 THEN '18-39'
        WHEN TIMESTAMPDIFF(YEAR, FchPat_Nee, CURDATE()) BETWEEN 40 AND 59 THEN '40-59'
        WHEN TIMESTAMPDIFF(YEAR, FchPat_Nee, CURDATE()) BETWEEN 60 AND 79 THEN '60-79'
        ELSE '80+'
    END as age_bracket,
    FchPat_Sexe as sex,
    COUNT(*) as patient_count
FROM fchpat
GROUP BY postal_code, age_bracket, sex
ORDER BY postal_code, age_bracket, sex;
" > /tmp/ground_truth_raw.tsv

# Convert TSV to CSV (handling the header manually to ensure it matches expected format exactly)
# MySQL output is tab-separated. We need comma-separated.
# Also, MySQL -B output includes headers.
cat /tmp/ground_truth_raw.tsv | tr '\t' ',' > "$GROUND_TRUTH_CSV"

# 2. Check Agent Output
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
HEADERS_MATCH="false"
ROW_COUNT=0

if [ -f "$OUTPUT_CSV" ]; then
    FILE_EXISTS="true"
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$OUTPUT_CSV" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Check Row Count (excluding header)
    ROW_COUNT=$(tail -n +2 "$OUTPUT_CSV" | wc -l)
    
    # Check Headers
    ACTUAL_HEADER=$(head -n 1 "$OUTPUT_CSV" | tr -d '\r')
    EXPECTED_HEADER="postal_code,age_bracket,sex,patient_count"
    if [ "$ACTUAL_HEADER" == "$EXPECTED_HEADER" ]; then
        HEADERS_MATCH="true"
    fi
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Prepare result JSON
# We will copy both the agent's CSV and the ground truth CSV to the host via copy_from_env
# So we don't need to embed the full content in JSON, but we'll include metadata.

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "headers_match": $HEADERS_MATCH,
    "row_count": $ROW_COUNT,
    "agent_csv_path": "$OUTPUT_CSV",
    "ground_truth_csv_path": "$GROUND_TRUTH_CSV"
}
EOF

# Move to standard result path
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result export complete."
cat /tmp/task_result.json