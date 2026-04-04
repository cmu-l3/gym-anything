#!/bin/bash
# Export script for Min-Max Data Entry Bounds task

echo "=== Exporting Min-Max Task Result ==="

source /workspace/scripts/task_utils.sh

# Inline fallbacks
if ! type dhis2_query &>/dev/null; then
    dhis2_query() {
        docker exec dhis2-db psql -U dhis -d dhis2 -t -c "$1" 2>/dev/null
    }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START_EPOCH=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_minmax_count 2>/dev/null | tr -d ' ' || echo "0")

echo "Initial min-max count: $INITIAL_COUNT"

# 1. Query Current Min-Max Count for Bombali
echo "Querying current min-max records..."
CURRENT_COUNT=$(dhis2_query "
    SELECT COUNT(*) 
    FROM minmaxdataelement mmd
    JOIN organisationunit ou ON mmd.sourceid = ou.organisationunitid
    WHERE ou.path LIKE '%/O6uvpzGd5pu%' OR ou.name ILIKE '%Bombali%'
" 2>/dev/null | tr -d ' ' || echo "0")

echo "Current min-max count: $CURRENT_COUNT"

# 2. Check if generated values are for Immunization/EPI data elements
# This ensures the agent selected the *correct* dataset, not just random generation
echo "Checking linkage to immunization data..."
IMMUNIZATION_RECORD_COUNT=$(dhis2_query "
    SELECT COUNT(*) 
    FROM minmaxdataelement mmd
    JOIN organisationunit ou ON mmd.sourceid = ou.organisationunitid
    JOIN dataelement de ON mmd.dataelementid = de.dataelementid
    WHERE (ou.path LIKE '%/O6uvpzGd5pu%' OR ou.name ILIKE '%Bombali%')
    AND (
        de.name ILIKE '%immun%' OR 
        de.name ILIKE '%vaccin%' OR 
        de.name ILIKE '%bcg%' OR 
        de.name ILIKE '%penta%' OR 
        de.name ILIKE '%measles%' OR 
        de.name ILIKE '%opv%' OR 
        de.name ILIKE '%yellow fever%'
    )
" 2>/dev/null | tr -d ' ' || echo "0")

echo "Immunization-linked records: $IMMUNIZATION_RECORD_COUNT"

# 3. Check documentation file
SUMMARY_FILE="/home/ga/Desktop/minmax_config_summary.txt"
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_LENGTH=0

if [ -f "$SUMMARY_FILE" ]; then
    FILE_MTIME=$(stat -c %Y "$SUMMARY_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START_EPOCH" ]; then
        FILE_EXISTS="true"
        FILE_CONTENT=$(cat "$SUMMARY_FILE" | head -c 1000) # Cap size
        FILE_LENGTH=$(echo "$FILE_CONTENT" | wc -c)
    fi
fi

# Create JSON Result
cat > /tmp/minmax_result.json << ENDJSON
{
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "immunization_linked_count": $IMMUNIZATION_RECORD_COUNT,
    "file_exists": $FILE_EXISTS,
    "file_length": $FILE_LENGTH,
    "file_content": $(echo "$FILE_CONTENT" | jq -R .),
    "task_timestamp": $TASK_START_EPOCH
}
ENDJSON

chmod 666 /tmp/minmax_result.json 2>/dev/null || true
echo "Result JSON saved."
cat /tmp/minmax_result.json
echo "=== Export Complete ==="