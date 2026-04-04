#!/bin/bash
echo "=== Exporting Spatial Competition Analysis Result ==="

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- DATA EXTRACTION ---

# 1. Extract Schema Information (to check Property and Index)
echo "Extracting schema..."
SCHEMA_JSON=$(curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/demodb")

# 2. Extract Function Definition
echo "Extracting function definition..."
FUNCTION_JSON=$(orientdb_sql "demodb" "SELECT FROM OFunction WHERE name = 'CalculateCompetition'")

# 3. Extract Target Hotel Data (Verification Targets)
echo "Extracting hotel data..."
# We specifically check the hotels we set up ground truth for
HOTELS_JSON=$(orientdb_sql "demodb" "SELECT Name, CompetitionScore FROM Hotels WHERE Name IN ['Hotel Artemide', 'The Savoy', 'Park Hyatt Tokyo']")

# Create the result JSON safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "schema": $SCHEMA_JSON,
    "function_def": $FUNCTION_JSON,
    "hotels_data": $HOTELS_JSON
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="