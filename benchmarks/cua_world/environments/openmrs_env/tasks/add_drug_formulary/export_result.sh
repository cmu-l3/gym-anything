#!/bin/bash
# Export: add_drug_formulary task
# Queries the database to check if the drug was created correctly.

echo "=== Exporting add_drug_formulary result ==="
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Target Name
TARGET_DRUG="Aspirin 500mg ES"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Database for the drug
# We join with concept_name to verify the linked concept is actually "Aspirin"
echo "Querying database for '$TARGET_DRUG'..."

# Construct SQL query to get details
SQL="SELECT d.drug_id, d.name, d.strength, cn.name, d.date_created, d.retired 
     FROM drug d 
     JOIN concept_name cn ON d.concept_id = cn.concept_id 
     WHERE d.name = '$TARGET_DRUG' 
     AND cn.locale = 'en' 
     AND cn.concept_name_type = 'FULLY_SPECIFIED' 
     LIMIT 1;"

# Run Query
RESULT_LINE=$(omrs_db_query "$SQL" 2>/dev/null || echo "")

# Parse Result
# Expected format: id<tab>name<tab>strength<tab>concept_name<tab>date<tab>retired
DRUG_FOUND="false"
DRUG_NAME=""
DRUG_STRENGTH=""
CONCEPT_NAME=""
DATE_CREATED=""
IS_RETIRED="1"

if [ -n "$RESULT_LINE" ]; then
    DRUG_FOUND="true"
    DRUG_NAME=$(echo "$RESULT_LINE" | awk -F'\t' '{print $2}')
    DRUG_STRENGTH=$(echo "$RESULT_LINE" | awk -F'\t' '{print $3}')
    CONCEPT_NAME=$(echo "$RESULT_LINE" | awk -F'\t' '{print $4}')
    DATE_CREATED=$(echo "$RESULT_LINE" | awk -F'\t' '{print $5}')
    IS_RETIRED=$(echo "$RESULT_LINE" | awk -F'\t' '{print $6}')
fi

# Check timestamps using python to parse SQL datetime
CREATED_DURING_TASK="false"
if [ "$DRUG_FOUND" = "true" ] && [ -n "$DATE_CREATED" ]; then
    CREATED_DURING_TASK=$(python3 -c "
import sys
from datetime import datetime
try:
    task_start = $TASK_START
    # SQL format usually YYYY-MM-DD HH:MM:SS
    created_str = '$DATE_CREATED'
    created_dt = datetime.strptime(created_str, '%Y-%m-%d %H:%M:%S')
    created_ts = created_dt.timestamp()
    # Allow small clock skew, check if created after start
    print('true' if created_ts >= (task_start - 5) else 'false')
except Exception as e:
    print('false')
")
fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "drug_found": $DRUG_FOUND,
    "drug_name": "$DRUG_NAME",
    "drug_strength": "$DRUG_STRENGTH",
    "linked_concept_name": "$CONCEPT_NAME",
    "is_retired": $IS_RETIRED,
    "created_during_task": $CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
sudo mv "$TEMP_JSON" /tmp/task_result.json
sudo chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="