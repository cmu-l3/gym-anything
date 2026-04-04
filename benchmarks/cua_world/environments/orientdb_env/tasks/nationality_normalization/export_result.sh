#!/bin/bash
echo "=== Exporting Nationality Normalization Result ==="

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check Report File
REPORT_PATH="/home/ga/nationality_audit.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -c 2000) # Limit size
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# 3. Database State Export using SQL Queries
# We need to verify if the edges exist and if they connect the right things.

# Check if class exists
CLASS_EXISTS=$(orientdb_class_exists "demodb" "IsCitizenOf"; echo $?)
# orientdb_class_exists returns 0 for yes, 1 for no.
if [ "$CLASS_EXISTS" -eq 0 ]; then
    IS_CITIZEN_OF_EXISTS="true"
else
    IS_CITIZEN_OF_EXISTS="false"
fi

# Query edges to verify mappings
# We select the Nationality of the Profile (out) and the Name of the Country (in)
# This allows us to verify: "American" -> "United States"
EDGE_DATA_JSON="[]"
if [ "$IS_CITIZEN_OF_EXISTS" == "true" ]; then
    echo "Querying edge data..."
    # Query: Select out.Nationality, in.Name, out.Email from IsCitizenOf
    EDGE_DATA_JSON=$(orientdb_sql "demodb" "SELECT out.Nationality as nat, in.Name as country, out.Email as email FROM IsCitizenOf LIMIT 100")
fi

# Check for Orphans (Profiles connected to nothing vs Profiles connected to something)
# Specifically check Carlos (Mexican)
CARLOS_EDGES=$(orientdb_sql "demodb" "SELECT count(*) as cnt FROM IsCitizenOf WHERE out.Email='carlos.lopez@example.com'")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content": $(echo "$REPORT_CONTENT" | jq -R -s '.'),
    "class_is_citizen_of_exists": $IS_CITIZEN_OF_EXISTS,
    "edge_data": ${EDGE_DATA_JSON:-"{}"},
    "carlos_edges": ${CARLOS_EDGES:-"{}"},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"