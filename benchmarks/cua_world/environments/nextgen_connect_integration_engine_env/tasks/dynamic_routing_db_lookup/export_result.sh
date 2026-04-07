#!/bin/bash
echo "=== Exporting dynamic_routing_db_lookup task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Load start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# --- 1. CONFIGURATION CHECK ---
# Find channel by name
CHANNEL_INFO=$(query_postgres "SELECT id, channel FROM channel WHERE name='Dynamic_Clinic_Router';" 2>/dev/null || true)
CHANNEL_ID=$(echo "$CHANNEL_INFO" | head -1 | cut -d'|' -f1)
CHANNEL_XML=$(echo "$CHANNEL_INFO" | cut -d'|' -f2-)

CHANNEL_EXISTS="false"
CHANNEL_STARTED="false"
DYNAMIC_CONFIG="false"
DB_CODE_DETECTED="false"

if [ -n "$CHANNEL_ID" ]; then
    CHANNEL_EXISTS="true"
    
    # Check status
    STATUS=$(get_channel_status_api "$CHANNEL_ID")
    if [ "$STATUS" = "STARTED" ] || [ "$STATUS" = "POLLING" ]; then
        CHANNEL_STARTED="true"
    fi
    
    # Check if variables are used in destination (e.g., ${host} or ${port} or similar map variable syntax)
    # Looking for ${...} inside remoteAddress or remotePort tags
    # Or reference to variables in connector properties
    if echo "$CHANNEL_XML" | grep -q '\${[^}]*}'; then
        DYNAMIC_CONFIG="true"
    fi
    
    # Check for DB connection code (DatabaseConnectionFactory or similar)
    if echo "$CHANNEL_XML" | grep -qi "DatabaseConnectionFactory\|java.sql.DriverManager\|jdbc:postgresql"; then
        DB_CODE_DETECTED="true"
    fi
fi

# --- 2. FUNCTIONAL TESTING ---
# Clear simulator logs
echo "" > /tmp/received_6671.log
echo "" > /tmp/received_6672.log

ROUTED_A="false"
ROUTED_B="false"

if [ "$CHANNEL_STARTED" = "true" ]; then
    echo "Running Functional Tests..."
    
    # Send Message for CLINIC_A
    echo "Sending CLINIC_A message..."
    # MLLP framing: 0x0B ... 0x1C 0x0D
    printf '\x0b' | nc localhost 6661
    cat /home/ga/msg_clinic_a.hl7 | nc localhost 6661
    printf '\x1c\x0d' | nc localhost 6661
    
    sleep 2
    
    # Send Message for CLINIC_B
    echo "Sending CLINIC_B message..."
    printf '\x0b' | nc localhost 6661
    cat /home/ga/msg_clinic_b.hl7 | nc localhost 6661
    printf '\x1c\x0d' | nc localhost 6661
    
    sleep 3
    
    # Verify Routing
    if grep -q "CLINIC_A" /tmp/received_6671.log; then
        ROUTED_A="true"
        echo "SUCCESS: CLINIC_A message received on 6671"
    else
        echo "FAIL: CLINIC_A message NOT received on 6671"
    fi
    
    # Ensure CLINIC_A didn't go to B
    if grep -q "CLINIC_A" /tmp/received_6672.log; then
        echo "FAIL: CLINIC_A message WRONGLY received on 6672"
        ROUTED_A="false" # Invalidate if cross-talk
    fi
    
    if grep -q "CLINIC_B" /tmp/received_6672.log; then
        ROUTED_B="true"
        echo "SUCCESS: CLINIC_B message received on 6672"
    else
        echo "FAIL: CLINIC_B message NOT received on 6672"
    fi
fi

# Create Result JSON
JSON_CONTENT=$(cat <<EOF
{
    "channel_exists": $CHANNEL_EXISTS,
    "channel_started": $CHANNEL_STARTED,
    "dynamic_config_detected": $DYNAMIC_CONFIG,
    "db_code_detected": $DB_CODE_DETECTED,
    "routed_clinic_a": $ROUTED_A,
    "routed_clinic_b": $ROUTED_B,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/dynamic_routing_result.json" "$JSON_CONTENT"
echo "Result saved to /tmp/dynamic_routing_result.json"
cat /tmp/dynamic_routing_result.json
echo "=== Export complete ==="