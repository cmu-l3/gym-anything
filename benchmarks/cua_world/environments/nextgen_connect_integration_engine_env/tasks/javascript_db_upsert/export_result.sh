#!/bin/bash
echo "=== Exporting javascript_db_upsert task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Initialize results
CHANNEL_EXISTS="false"
CHANNEL_ID=""
CONNECTOR_TYPE_CORRECT="false"
INSERT_TEST_PASSED="false"
UPDATE_TEST_PASSED="false"
SCRIPT_CONTENT_VALID="false"

# 1. Find the channel
CHANNEL_DATA=$(query_postgres "SELECT id, name FROM channel WHERE LOWER(name) LIKE '%census%upsert%processor%' LIMIT 1;" 2>/dev/null || true)

if [ -n "$CHANNEL_DATA" ]; then
    CHANNEL_EXISTS="true"
    CHANNEL_ID=$(echo "$CHANNEL_DATA" | cut -d'|' -f1)
    echo "Found channel ID: $CHANNEL_ID"

    # 2. Check Configuration (JavaScript Writer)
    CHANNEL_XML=$(query_postgres "SELECT channel FROM channel WHERE id='$CHANNEL_ID';" 2>/dev/null || true)
    
    # Check for JavaScript Writer specific class/element
    if echo "$CHANNEL_XML" | grep -q "JavaScriptDispatcherProperties"; then
        CONNECTOR_TYPE_CORRECT="true"
    fi
    
    # Check for keywords in script (DB connection, update, insert)
    if echo "$CHANNEL_XML" | grep -q "DatabaseConnection" && \
       echo "$CHANNEL_XML" | grep -qi "UPDATE" && \
       echo "$CHANNEL_XML" | grep -qi "INSERT"; then
        SCRIPT_CONTENT_VALID="true"
    fi

    # 3. Dynamic Testing
    # Ensure channel is deployed
    DEPLOYED=$(query_postgres "SELECT COUNT(*) FROM d_channels WHERE channel_id='$CHANNEL_ID';" 2>/dev/null || echo "0")
    
    if [ "$DEPLOYED" -gt 0 ]; then
        echo "Channel is deployed. Starting functional tests..."
        
        # Test A: INSERT (New Record)
        # Clear DB first
        docker exec nextgen-postgres psql -U postgres -d mirthdb -c "DELETE FROM current_census;" >/dev/null
        
        # Inject Message
        TEST_JSON_1='{"mrn": "TEST001", "name": "Alice Test", "location": "ER-01"}'
        echo "Injecting Insert Test Message..."
        api_call_json POST "/channels/$CHANNEL_ID/messages" "$TEST_JSON_1" > /dev/null
        
        sleep 5 # Wait for processing
        
        # Check DB
        ROW_COUNT=$(docker exec nextgen-postgres psql -U postgres -d mirthdb -t -A -c "SELECT COUNT(*) FROM current_census WHERE mrn='TEST001' AND location='ER-01';")
        if [ "$ROW_COUNT" -eq "1" ]; then
            INSERT_TEST_PASSED="true"
            echo "INSERT test passed."
        else
            echo "INSERT test failed. Row count: $ROW_COUNT"
        fi
        
        # Test B: UPDATE (Existing Record)
        TEST_JSON_2='{"mrn": "TEST001", "name": "Alice Test", "location": "ICU-05"}'
        echo "Injecting Update Test Message..."
        api_call_json POST "/channels/$CHANNEL_ID/messages" "$TEST_JSON_2" > /dev/null
        
        sleep 5
        
        # Check DB - Should still have 1 row for TEST001, but location updated
        TOTAL_ROWS=$(docker exec nextgen-postgres psql -U postgres -d mirthdb -t -A -c "SELECT COUNT(*) FROM current_census WHERE mrn='TEST001';")
        UPDATED_ROW=$(docker exec nextgen-postgres psql -U postgres -d mirthdb -t -A -c "SELECT COUNT(*) FROM current_census WHERE mrn='TEST001' AND location='ICU-05';")
        
        if [ "$TOTAL_ROWS" -eq "1" ] && [ "$UPDATED_ROW" -eq "1" ]; then
            UPDATE_TEST_PASSED="true"
            echo "UPDATE test passed."
        else
            echo "UPDATE test failed. Total Rows: $TOTAL_ROWS (expected 1), Updated Match: $UPDATED_ROW (expected 1)"
        fi
        
    else
        echo "Channel not deployed, skipping dynamic tests."
    fi
else
    echo "Channel not found."
fi

# Create JSON result
JSON_CONTENT=$(cat <<EOF
{
    "channel_exists": $CHANNEL_EXISTS,
    "connector_type_correct": $CONNECTOR_TYPE_CORRECT,
    "script_content_valid": $SCRIPT_CONTENT_VALID,
    "insert_test_passed": $INSERT_TEST_PASSED,
    "update_test_passed": $UPDATE_TEST_PASSED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/javascript_db_upsert_result.json" "$JSON_CONTENT"
cat /tmp/javascript_db_upsert_result.json
echo "=== Export complete ==="