#!/bin/bash
echo "=== Exporting Household Aggregation Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Export the CSV file if it exists
CSV_PATH="/home/ga/Documents/household_mailing_list.csv"
CSV_EXISTS="false"
CSV_CONTENT=""

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    # Read content, base64 encode to safely pass in JSON if needed, or just copy file
    cp "$CSV_PATH" /tmp/household_mailing_list.csv
fi

# 2. Verify Database State (Did they actually register the patients?)
# We query the DB and dump to a JSON-like structure or just raw text for the verifier to parse
echo "Querying database for inserted patients..."
mysql -u root DrTuxTest -N -e "
SELECT FchPat_NomFille, FchPat_Prenom, FchPat_Nee, FchPat_Adresse, FchPat_Ville 
FROM fchpat 
WHERE FchPat_NomFille IN ('LEMOINE', 'DUPUIS', 'MARTIN')
ORDER BY FchPat_NomFille, FchPat_Nee;
" > /tmp/db_patients_dump.txt 2>/dev/null || true

# 3. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Check if app is running
APP_RUNNING=$(pgrep -f "Manager.exe" > /dev/null && echo "true" || echo "false")

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_exists": $CSV_EXISTS,
    "app_running": $APP_RUNNING,
    "csv_path": "/tmp/household_mailing_list.csv",
    "db_dump_path": "/tmp/db_patients_dump.txt",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="