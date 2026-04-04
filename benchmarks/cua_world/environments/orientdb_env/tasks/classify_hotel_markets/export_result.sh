#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Data for Verification
# We need to export:
# - Schema definition of Hotels (to check for Market property)
# - The actual data: Hotel Name, Country, Market value, and list of Visitor Nationalities

echo "Querying database for results..."

# Check Schema
SCHEMA_JSON=$(orientdb_sql "demodb" "SELECT expand(properties) FROM (SELECT expand(classes) FROM metadata:schema) WHERE name = 'Hotels'")

# Check Data
# Query: Select Hotel Name, Country, Market, and list of Visitor Nationalities
# Note: In OrientDB, we can traverse edges. 
# in('HasStayed') gives the edges coming into the hotel.
# in('HasStayed').outV() gives the profiles who visited.
DATA_JSON=$(orientdb_sql "demodb" "SELECT Name, Country, Market, in('HasStayed').outV().Nationality as VisitorNationalities FROM Hotels")

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "timestamp": $(date +%s),
    "schema": $SCHEMA_JSON,
    "data": $DATA_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 4. Save to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"