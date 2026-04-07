#!/bin/bash
# Post-task export script
source /workspace/scripts/task_utils.sh

echo "=== Exporting Waste Treatment Task Results ==="

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Close OpenLCA to release Derby database lock
echo "Closing OpenLCA to query database..."
close_openlca
sleep 3

# 3. Locate the Active Database
# We look for the most recently modified database directory
DB_ROOT="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=$(ls -td "$DB_ROOT"/*/ 2>/dev/null | head -1)

if [ -z "$ACTIVE_DB" ]; then
    echo "No database found in $DB_ROOT"
    ACTIVE_DB_FOUND="false"
else
    echo "Found active database: $ACTIVE_DB"
    ACTIVE_DB_FOUND="true"
fi

# 4. Query Derby Database for verification
# We need to verify Flow Type, Process Links, and Quantitative Reference directions
if [ "$ACTIVE_DB_FOUND" = "true" ]; then
    echo "Querying Derby DB..."

    # Create a SQL script
    cat > /tmp/verify_query.sql << 'SQL_EOF'
-- Check Flow Name and Type
SELECT NAME, FLOW_TYPE FROM TBL_FLOWS WHERE NAME LIKE '%Hazardous Sludge%';

-- Check Treatment Process Logic
-- We join Process -> Exchange -> Flow to check if Hazardous Sludge is an INPUT and QUANTITATIVE REFERENCE
SELECT 
    p.NAME AS PROCESS_NAME, 
    f.NAME AS FLOW_NAME, 
    e.IS_INPUT, 
    e.IS_QUANTITATIVE_REFERENCE 
FROM TBL_PROCESSES p
JOIN TBL_EXCHANGES e ON e.F_OWNER = p.ID
JOIN TBL_FLOWS f ON e.F_FLOW = f.ID
WHERE p.NAME LIKE '%Sludge Incineration Service%' 
  AND f.NAME LIKE '%Hazardous Sludge%';

-- Check Generator Process Logic
SELECT 
    p.NAME AS PROCESS_NAME, 
    f.NAME AS FLOW_NAME, 
    e.IS_INPUT
FROM TBL_PROCESSES p
JOIN TBL_EXCHANGES e ON e.F_OWNER = p.ID
JOIN TBL_FLOWS f ON e.F_FLOW = f.ID
WHERE p.NAME LIKE '%Chemical Plant Operation%' 
  AND f.NAME LIKE '%Hazardous Sludge%';

-- Check Product System Existence
SELECT NAME FROM TBL_PRODUCT_SYSTEMS WHERE NAME LIKE '%Plant_Waste_System%';
SQL_EOF

    # Run query
    QUERY_OUTPUT=$(derby_query "$ACTIVE_DB" "$(cat /tmp/verify_query.sql)")
    echo "$QUERY_OUTPUT" > /tmp/db_queries.txt
else
    echo "Skipping DB query (no DB found)"
    echo "" > /tmp/db_queries.txt
fi

# 5. Check if OpenLCA was running
APP_WAS_RUNNING="true" # We closed it, so it was running. 
# (In a real scenario, we might track PID before closing, but close_openlca handles logic)

# 6. Prepare JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Encode DB output safe for JSON
DB_CONTENT=$(cat /tmp/db_queries.txt | python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))')

cat > "$TEMP_JSON" << EOF
{
    "db_found": $ACTIVE_DB_FOUND,
    "db_path": "$ACTIVE_DB",
    "query_output": $DB_CONTENT,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": $(date +%s)
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="
cat /tmp/task_result.json