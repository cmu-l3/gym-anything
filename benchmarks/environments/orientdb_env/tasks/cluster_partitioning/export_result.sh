#!/bin/bash
echo "=== Exporting Cluster Partitioning Result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- 1. Check Report File ---
REPORT_PATH="/home/ga/partitioning_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_MTIME="0"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -c 1000) # Limit size
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
fi

# --- 2. Query OrientDB for Schema State ---
# We need to check:
# a) Do the clusters exist?
# b) Is the Hotels class configured to use them?

DB_SCHEMA=$(curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/demodb")

# Parse Schema with Python to get clusters and class config
SCHEMA_ANALYSIS=$(echo "$DB_SCHEMA" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    
    # Get all cluster names
    clusters = [c['name'] for c in data.get('clusters', [])]
    
    # Get Hotels class details
    hotels_class = next((c for c in data.get('classes', []) if c['name'] == 'Hotels'), None)
    hotels_cluster_ids = hotels_class.get('clusterIds', []) if hotels_class else []
    
    # Map cluster IDs back to names for the class
    cluster_map = {c['id']: c['name'] for c in data.get('clusters', [])}
    hotels_cluster_names = [cluster_map.get(cid) for cid in hotels_cluster_ids]
    
    print(json.dumps({
        'all_clusters': clusters,
        'hotels_clusters': hotels_cluster_names,
        'hotels_class_exists': bool(hotels_class)
    }))
except Exception as e:
    print(json.dumps({'error': str(e)}))
")

# --- 3. Query OrientDB for Data Partitioning Correctness ---
# We need to verify that data is actually physically located in the correct clusters.
# We use 'SELECT FROM cluster:<name>' to verify.

# Function to count valid/invalid records in a cluster given a list of valid countries
check_cluster_content() {
    local cluster="$1"
    local valid_countries="$2" # JSON array string like '["Italy", "France"]'
    
    # Count total in cluster
    local count_query="SELECT COUNT(*) as cnt FROM cluster:${cluster}"
    local total=$(orientdb_sql "demodb" "$count_query" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")
    
    # Count misplaced (Country NOT IN valid_list)
    # Construct SQL list: ["A","B"] -> 'A','B'
    local sql_list=$(echo "$valid_countries" | python3 -c "import sys, json; print(','.join([f'\'{c}\'' for c in json.load(sys.stdin)]))")
    local invalid_query="SELECT COUNT(*) as cnt FROM cluster:${cluster} WHERE Country NOT IN [${sql_list}]"
    local invalid=$(orientdb_sql "demodb" "$invalid_query" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")
    
    echo "{\"total\": $total, \"invalid\": $invalid}"
}

echo "Verifying Europe Cluster..."
EUROPE_STATS=$(check_cluster_content "hotels_europe" '["Italy", "Germany", "France", "United Kingdom", "Spain", "Greece", "Netherlands"]')

echo "Verifying Americas Cluster..."
AMERICAS_STATS=$(check_cluster_content "hotels_americas" '["United States", "Canada", "Brazil"]')

echo "Verifying AsiaPacific Cluster..."
ASIAPACIFIC_STATS=$(check_cluster_content "hotels_asiapacific" '["Japan", "Australia"]')

# Check Default Cluster (should be empty if fully partitioned)
# Note: The default cluster for Hotels is usually just 'Hotels' (id varies)
# We check if there are records in the class that are NOT in the new clusters.
TOTAL_RECORDS=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Hotels" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

# --- 4. Compile Result JSON ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_mtime": $REPORT_MTIME,
    "report_content": $(echo "$REPORT_CONTENT" | jq -R .),
    "schema_analysis": $SCHEMA_ANALYSIS,
    "partition_stats": {
        "europe": $EUROPE_STATS,
        "americas": $AMERICAS_STATS,
        "asiapacific": $ASIAPACIFIC_STATS,
        "total_records": $TOTAL_RECORDS
    },
    "screenshot_exists": $([ -f /tmp/task_final.png ] && echo "true" || echo "false")
}
EOF

# Save result safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"