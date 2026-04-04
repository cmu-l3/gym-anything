#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting embedded_document_enrichment results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Schema Information
echo "Extracting schema..."
SCHEMA_JSON=$(curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/demodb")

# 3. Extract Data for Verification (The 5 target hotels)
echo "Extracting hotel data..."
# We use a custom SQL query to fetch exactly what we need to verify
HOTEL_DATA=$(orientdb_sql "demodb" "SELECT Name, Amenities, SocialMedia FROM Hotels WHERE Name IN ['Hotel Artemide', 'Hotel Adlon Kempinski', 'The Savoy', 'Park Hyatt Tokyo', 'Copacabana Palace']")

# 4. Check Output File
OUTPUT_FILE="/home/ga/Documents/hotels_with_pool.json"
OUTPUT_EXISTS="false"
OUTPUT_CREATED_DURING="false"
OUTPUT_CONTENT=""

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    FILE_TIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        OUTPUT_CREATED_DURING="true"
    fi
    # Read content safely
    OUTPUT_CONTENT=$(cat "$OUTPUT_FILE")
fi

# 5. Check if Studio is still open
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "output_file": {
        "exists": $OUTPUT_EXISTS,
        "created_during_task": $OUTPUT_CREATED_DURING,
        "path": "$OUTPUT_FILE",
        "content_preview": $(echo "$OUTPUT_CONTENT" | jq -R . 2>/dev/null || echo "\"\"")
    },
    "database_state": {
        "schema": $SCHEMA_JSON,
        "hotel_data": $HOTEL_DATA
    }
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="