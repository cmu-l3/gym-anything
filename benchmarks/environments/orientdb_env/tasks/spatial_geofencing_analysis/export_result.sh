#!/bin/bash
echo "=== Exporting spatial_geofencing_analysis result ==="

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin
source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# --- Gather Database State ---

# 1. Check for Index Existence via REST API
# Using a query to metadata:index
INDEX_INFO=$(orientdb_sql "demodb" "SELECT FROM metadata:index WHERE name='Hotels.Location'")
INDEX_EXISTS="false"
INDEX_ALGORITHM=""
if echo "$INDEX_INFO" | grep -q "Hotels.Location"; then
    INDEX_EXISTS="true"
    # Extract algorithm (looking for LUCENE)
    INDEX_ALGORITHM=$(echo "$INDEX_INFO" | python3 -c "import sys, json; 
try:
    data = json.load(sys.stdin)
    res = data.get('result', [])
    if res:
        print(res[0].get('algorithm', 'unknown'))
    else:
        print('none')
except:
    print('error')
")
fi

# 2. Check Hotel Data (Positive and Negative controls)
# We select specific hotels to verify if they were tagged correctly
DATA_CHECK=$(orientdb_sql "demodb" "SELECT Name, MarketingZone FROM Hotels WHERE Name IN ['Hotel Artemide', 'Hotel Adlon Kempinski']")

# Parse results using Python
TAG_RESULTS=$(echo "$DATA_CHECK" | python3 -c "import sys, json;
try:
    data = json.load(sys.stdin)
    results = data.get('result', [])
    artemide_tag = next((r.get('MarketingZone') for r in results if r.get('Name') == 'Hotel Artemide'), None)
    adlon_tag = next((r.get('MarketingZone') for r in results if r.get('Name') == 'Hotel Adlon Kempinski'), None)
    print(json.dumps({'artemide': artemide_tag, 'adlon': adlon_tag}))
except:
    print(json.dumps({'artemide': None, 'adlon': None}))
")

# 3. Count total tagged hotels (To ensure they didn't just update *all* hotels)
TOTAL_TAGGED=$(orientdb_sql "demodb" "SELECT count(*) as cnt FROM Hotels WHERE MarketingZone = 'HistoricCenter'" | \
    python3 -c "import sys, json; print(json.load(sys.stdin).get('result', [{}])[0].get('cnt', 0))" 2>/dev/null || echo "0")


# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "index_exists": $INDEX_EXISTS,
    "index_algorithm": "$INDEX_ALGORITHM",
    "tag_results": $TAG_RESULTS,
    "total_tagged_count": $TOTAL_TAGGED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Exported data:"
cat /tmp/task_result.json
echo "=== Export complete ==="