#!/bin/bash
set -e
echo "=== Exporting Polymorphic Attraction Hierarchy Results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# === DATA GATHERING ===

# 1. Output File Analysis
OUTPUT_FILE="/home/ga/attraction_hierarchy_report.txt"
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CONTENT=""

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    # Read first 50 lines for verification
    FILE_CONTENT=$(head -n 50 "$OUTPUT_FILE" | base64 -w 0)
fi

# 2. Database Schema Analysis
# Fetch schema to check inheritance and properties
SCHEMA_JSON=$(curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/demodb" 2>/dev/null | base64 -w 0)

# 3. Database Content Analysis
# Check count of Museums
MUSEUM_COUNT=$(orientdb_sql "demodb" "SELECT count(*) as cnt FROM Museums" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

# Check specific museum records
# We select key fields to verify data accuracy
MUSEUMS_DATA=$(orientdb_sql "demodb" "SELECT Name, Collection, FreeEntry, AnnualVisitors, Category, @class FROM Museums" 2>/dev/null | base64 -w 0)

# Check polymorphic query count (Attractions that are Museums)
POLY_COUNT=$(orientdb_sql "demodb" "SELECT count(*) as cnt FROM Attractions WHERE @class='Museums'" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

# Check if Category property exists on Attractions (Parent)
# We need to query schema, but we can also test by querying Attractions for Category
CATEGORY_ON_ATTRACTIONS=$(orientdb_sql "demodb" "SELECT count(*) as cnt FROM Attractions WHERE Category IS NOT NULL" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")


# === JSON EXPORT ===
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_check": {
        "exists": $FILE_EXISTS,
        "size_bytes": $FILE_SIZE,
        "content_b64": "$FILE_CONTENT"
    },
    "schema_b64": "$SCHEMA_JSON",
    "data_check": {
        "museum_count": $MUSEUM_COUNT,
        "polymorphic_count": $POLY_COUNT,
        "category_data_count": $CATEGORY_ON_ATTRACTIONS,
        "records_b64": "$MUSEUMS_DATA"
    }
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"