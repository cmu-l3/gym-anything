#!/bin/bash
echo "=== Exporting Collaborative Filtering Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- 1. Check File Existence ---
QUERY_FILE="/home/ga/recommendation_query.sql"
FILE_EXISTS="false"
FILE_SIZE=0
if [ -f "$QUERY_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$QUERY_FILE")
fi

# --- 2. Query Database State ---
echo "Querying database state..."

# Helper to get JSON result safely
get_sql_json() {
    orientdb_sql "demodb" "$1" 2>/dev/null
}

# A. Check Schema
SCHEMA_JSON=$(curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/demodb")
CLASS_EXISTS_REC=$(echo "$SCHEMA_JSON" | jq -r '.classes[] | select(.name=="Recommendations") | .name')
CLASS_EXISTS_EDGE=$(echo "$SCHEMA_JSON" | jq -r '.classes[] | select(.name=="HasRecommendation") | .name')

# B. Get Recommendations for Target
# We fetch all fields to verify content
RECS_JSON=$(get_sql_json "SELECT RestaurantName, Score, TargetEmail FROM Recommendations WHERE TargetEmail='john.smith@example.com'")
REC_COUNT=$(echo "$RECS_JSON" | jq '.result | length')

# Save raw recommendations for verifier to parse
echo "$RECS_JSON" > /tmp/recs_dump.json

# C. Check Edges
# Count edges out from John to Recommendations
EDGE_QUERY="SELECT count(*) as cnt FROM HasRecommendation WHERE out IN (SELECT FROM Profiles WHERE Email='john.smith@example.com') AND in.TargetEmail='john.smith@example.com'"
EDGE_JSON=$(get_sql_json "$EDGE_QUERY")
EDGE_COUNT=$(echo "$EDGE_JSON" | jq -r '.result[0].cnt // 0')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "query_file_exists": $FILE_EXISTS,
    "query_file_size": $FILE_SIZE,
    "schema": {
        "Recommendations": "$( [ -n "$CLASS_EXISTS_REC" ] && echo "true" || echo "false" )",
        "HasRecommendation": "$( [ -n "$CLASS_EXISTS_EDGE" ] && echo "true" || echo "false" )"
    },
    "data": {
        "rec_count": ${REC_COUNT:-0},
        "edge_count": ${EDGE_COUNT:-0},
        "recommendations": $(cat /tmp/recs_dump.json | jq '.result // []')
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to public location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON" /tmp/recs_dump.json

echo "Export complete. Result:"
cat /tmp/task_result.json