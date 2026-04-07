#!/bin/bash
# Export results for "configure_custom_threat_feed" task

echo "=== Exporting Custom Threat Feed Result ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
HTTP_LOG="/tmp/threat_server_access.log"
FINAL_SCREENSHOT="/tmp/task_final.png"

# ==============================================================================
# 1. Check HTTP Access Logs (Strong Signal)
# If ELA fetched the feed, we'll see a GET request in the logs
# ==============================================================================
FEED_ACCESSED="false"
ACCESS_COUNT=0

if [ -f "$HTTP_LOG" ]; then
    # Look for GET requests to /threats.txt
    # We filter for requests that happened roughly after we started (log ordering usually sufficient)
    ACCESS_COUNT=$(grep -c "GET /threats.txt" "$HTTP_LOG" || echo "0")
    
    if [ "$ACCESS_COUNT" -gt 0 ]; then
        FEED_ACCESSED="true"
        echo "Confirmed: Threat feed was accessed $ACCESS_COUNT times."
    fi
else
    echo "Warning: HTTP log file not found."
fi

# ==============================================================================
# 2. Database Verification (Persistence Check)
# Query ELA database for the configured URL
# ==============================================================================
DB_RECORD_FOUND="false"
FEED_NAME_MATCH="false"
FEED_URL_MATCH="false"

# Helper query to search for the specific URL in likely tables
# Note: Table names vary by ELA version. We try a broad search if specific tables fail.
# Common tables: UV_ThreatSources, Sl_ThreatSource, ThreatSourceDetails
echo "Querying database for threat configuration..."

# We construct a query that looks for our specific URL
QUERY_URL="http://localhost:8888/threats.txt"
QUERY_NAME="Internal_Botnet_Feed"

# Attempt 1: Try to find the string in the entire database (simulated by checking common tables)
# We use ela_db_query helper from task_utils.sh
DB_OUTPUT=$(ela_db_query "SELECT * FROM UV_ThreatSources WHERE URL LIKE '%$QUERY_URL%' OR THREAT_SOURCE_NAME = '$QUERY_NAME'" 2>/dev/null)

if [[ -z "$DB_OUTPUT" ]]; then
    # Fallback table
    DB_OUTPUT=$(ela_db_query "SELECT * FROM Sl_ThreatSource WHERE URL LIKE '%$QUERY_URL%' OR NAME = '$QUERY_NAME'" 2>/dev/null)
fi

if [[ -n "$DB_OUTPUT" ]]; then
    DB_RECORD_FOUND="true"
    echo "Database record found: $DB_OUTPUT"
    
    if echo "$DB_OUTPUT" | grep -q "$QUERY_URL"; then
        FEED_URL_MATCH="true"
    fi
    if echo "$DB_OUTPUT" | grep -iq "$QUERY_NAME"; then
        FEED_NAME_MATCH="true"
    fi
fi

# ==============================================================================
# 3. Final State Capture
# ==============================================================================
take_screenshot "$FINAL_SCREENSHOT"

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "feed_accessed_via_http": $FEED_ACCESSED,
    "access_count": $ACCESS_COUNT,
    "db_record_found": $DB_RECORD_FOUND,
    "feed_name_match": $FEED_NAME_MATCH,
    "feed_url_match": $FEED_URL_MATCH,
    "db_raw_output": "$(echo $DB_OUTPUT | sed 's/"/\\"/g' | cut -c 1-200)",
    "screenshot_path": "$FINAL_SCREENSHOT"
}
EOF

# Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="