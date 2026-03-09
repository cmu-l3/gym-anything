#!/bin/bash
echo "=== Exporting hierarchy_salary_rollup results ==="

# Ensure safe PATH and source utils
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin
source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Agent's Output File
OUTPUT_FILE="/home/ga/salary_rollup.json"
FILE_EXISTS="false"
FILE_CONTENT="{}"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$OUTPUT_FILE")
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Verify Database State (Independent verification of work done)
# We query the DB to see if the user actually created the schema and data
echo "Querying database state..."

# Check Schema
SCHEMA_CHECK=$(orientdb_sql "demodb" "SELECT name FROM (SELECT expand(classes) FROM metadata:schema) WHERE name IN ['Staff', 'ReportsTo']" 2>/dev/null)

# Check Staff Count
STAFF_COUNT=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Staff" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

# Check Edge Count
EDGE_COUNT=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM ReportsTo" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

# Check Specific Hierarchy Link (e.g., Bob -> Alice)
# Note: ReportsTo is FROM subordinate TO boss. Bob reports to Alice.
# Query: Find edge where out.Name='Bob Driller' AND in.Name='Alice Sterling'
HIERARCHY_SAMPLE=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM ReportsTo WHERE out.Name='Bob Driller' AND in.Name='Alice Sterling'" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_content": $FILE_CONTENT,
    "db_schema_result": $SCHEMA_CHECK,
    "db_staff_count": $STAFF_COUNT,
    "db_edge_count": $EDGE_COUNT,
    "db_hierarchy_sample": $HIERARCHY_SAMPLE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="