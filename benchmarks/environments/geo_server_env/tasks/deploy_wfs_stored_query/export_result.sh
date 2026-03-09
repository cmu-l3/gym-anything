#!/bin/bash
echo "=== Exporting deploy_wfs_stored_query result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# 1. Check if the agent's output file exists
AGENT_FILE="/home/ga/large_cities_response.xml"
FILE_EXISTS="false"
FILE_SIZE=0
if [ -f "$AGENT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$AGENT_FILE")
fi

# 2. Verify Stored Query Existence via WFS ListStoredQueries
echo "Checking for Stored Query existence..."
LIST_RESPONSE=$(curl -s "http://localhost:8080/geoserver/wfs?request=ListStoredQueries&service=WFS&version=2.0.0")
QUERY_EXISTS="false"
if echo "$LIST_RESPONSE" | grep -q "GetLargeCities"; then
    QUERY_EXISTS="true"
fi

# 3. Test Execution of the Stored Query (Live Verification)
# We test with minPop=5000000 (5 million)
TEST_URL="http://localhost:8080/geoserver/wfs?request=GetFeature&service=WFS&version=2.0.0&storedQuery_id=GetLargeCities&minPop=5000000"
echo "Testing query execution: $TEST_URL"

# Capture HTTP status and body
TEST_HTTP_CODE=$(curl -s -o /tmp/wfs_test_response.xml -w "%{http_code}" "$TEST_URL")
TEST_RESPONSE_SIZE=$(stat -c%s /tmp/wfs_test_response.xml 2>/dev/null || echo "0")

# Analyze the response content
# We expect cities like 'London', 'New York', etc. to be present
# We expect small cities to be absent
RESPONSE_CONTAINS_FEATURES="false"
RESPONSE_VALID_FILTER="false"

if [ "$TEST_HTTP_CODE" = "200" ]; then
    # Simple check for feature members
    if grep -q "wfs:member" /tmp/wfs_test_response.xml || grep -q "featureMember" /tmp/wfs_test_response.xml; then
        RESPONSE_CONTAINS_FEATURES="true"
    fi
    
    # Check for known large cities (sanity check)
    if grep -q "New York" /tmp/wfs_test_response.xml || grep -q "Tokyo" /tmp/wfs_test_response.xml; then
        # Check that we don't have too many features (filtering worked)
        # Using a rough line count or feature count estimation
        FEATURE_COUNT=$(grep -c "ne_populated_places" /tmp/wfs_test_response.xml || echo "0")
        
        # There are ~7300 cities total. >5M should be < 100 cities.
        if [ "$FEATURE_COUNT" -gt 0 ] && [ "$FEATURE_COUNT" -lt 200 ]; then
            RESPONSE_VALID_FILTER="true"
        fi
    fi
fi

# Check for GUI interaction via access logs
GUI_INTERACTION=$(check_gui_interaction)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "agent_file_exists": ${FILE_EXISTS},
    "agent_file_size": ${FILE_SIZE},
    "stored_query_found": ${QUERY_EXISTS},
    "test_execution_http_code": "${TEST_HTTP_CODE}",
    "test_response_contains_features": ${RESPONSE_CONTAINS_FEATURES},
    "test_response_valid_filter": ${RESPONSE_VALID_FILTER},
    "gui_interaction_detected": ${GUI_INTERACTION},
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/deploy_wfs_stored_query_result.json"

echo "=== Export complete ==="