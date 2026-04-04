#!/bin/bash
echo "=== Exporting graph_history_tracking results ==="

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Fetch Schema Information
echo "Fetching schema..."
SCHEMA_JSON=$(curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/demodb")

# 2. Fetch the Target Hotels (Live State)
# We fetch by both old and new names to be safe
echo "Fetching live hotels..."
HOTELS_JSON=$(orientdb_sql "demodb" "SELECT Name, Stars, Phone, out('HasHistory') as HistoryEdges FROM Hotels WHERE Name IN ['Hotel Artemide', 'The Savoy', 'Hotel Adlon Kempinski', 'Adlon Kempinski Berlin']")

# 3. Fetch all HotelHistory records
echo "Fetching history records..."
HISTORY_JSON=$(orientdb_sql "demodb" "SELECT * FROM HotelHistory")

# 4. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "schema": $SCHEMA_JSON,
    "hotels": $HOTELS_JSON,
    "history": $HISTORY_JSON
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Take final screenshot
take_screenshot /tmp/task_final.png

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="