#!/bin/bash
echo "=== Exporting ICU Admission Alert result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# --- DATA COLLECTION ---

# 1. Get current channel count and list
INITIAL_COUNT=$(cat /tmp/initial_channel_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_channel_count)
CHANNEL_LIST=$(curl -sk -u admin:admin -H "X-Requested-With: OpenAPI" -H "Accept: application/json" "https://localhost:8443/api/channels" 2>/dev/null)

# 2. Find the target channel (fuzzy search for 'ICU')
CHANNEL_ID=$(echo "$CHANNEL_LIST" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    channels = data.get('list', {}).get('channel', []) if isinstance(data.get('list'), dict) else data.get('list', [])
    if isinstance(channels, dict): channels = [channels] # Handle single entry
    for c in channels:
        if 'ICU' in c.get('name', '').upper():
            print(c.get('id'))
            break
except: pass
")

CHANNEL_CONFIG=""
CHANNEL_STATUS=""
if [ -n "$CHANNEL_ID" ]; then
    # Get full config
    CHANNEL_CONFIG=$(curl -sk -u admin:admin -H "X-Requested-With: OpenAPI" -H "Accept: application/xml" "https://localhost:8443/api/channels/$CHANNEL_ID")
    # Get status
    CHANNEL_STATUS=$(get_channel_status_api "$CHANNEL_ID")
fi

# --- FUNCTIONAL TESTING ---

# Clear MailHog before tests
curl -s -X DELETE http://localhost:8025/api/v1/messages > /dev/null 2>&1

TEST_ICU_SENT=false
TEST_ICU_EMAIL_RECEIVED=false
TEST_MED_SENT=false
TEST_MED_EMAIL_RECEIVED=false
ICU_EMAIL_SUBJECT=""
ICU_EMAIL_BODY=""

if [ "$CHANNEL_STATUS" == "STARTED" ]; then
    echo "Channel is STARTED. Performing functional tests..."

    # Test 1: Send ICU Message (Should trigger email)
    echo "Sending ICU HL7 message..."
    if [ -f /tmp/test_data/icu_adt.hl7 ]; then
        # MLLP wrapping: 0x0B [msg] 0x1C 0x0D
        cat /tmp/test_data/icu_adt.hl7 | sed 's/\r/\r/g' > /tmp/msg_crlf.hl7 # Ensure line endings
        printf "\x0b" > /tmp/mllp_msg
        cat /tmp/test_data/icu_adt.hl7 >> /tmp/mllp_msg
        printf "\x1c\x0d" >> /tmp/mllp_msg
        
        # Send via netcat
        nc -w 2 localhost 6661 < /tmp/mllp_msg
        TEST_ICU_SENT=true
        
        # Wait for processing
        sleep 5
        
        # Check MailHog
        MAIL_DATA=$(curl -s http://localhost:8025/api/v2/messages)
        COUNT=$(echo "$MAIL_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin).get('total', 0))")
        
        if [ "$COUNT" -gt 0 ]; then
            TEST_ICU_EMAIL_RECEIVED=true
            # Extract subject and body for verification
            ICU_EMAIL_SUBJECT=$(echo "$MAIL_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['items'][0]['Content']['Headers']['Subject'][0])")
            ICU_EMAIL_BODY=$(echo "$MAIL_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['items'][0]['Content']['Body'])")
        fi
    fi

    # Clear MailHog again
    curl -s -X DELETE http://localhost:8025/api/v1/messages > /dev/null 2>&1

    # Test 2: Send Medical Ward Message (Should be filtered)
    echo "Sending Non-ICU HL7 message..."
    if [ -f /tmp/test_data/med_adt.hl7 ]; then
        printf "\x0b" > /tmp/mllp_msg_med
        cat /tmp/test_data/med_adt.hl7 >> /tmp/mllp_msg_med
        printf "\x1c\x0d" >> /tmp/mllp_msg_med
        
        nc -w 2 localhost 6661 < /tmp/mllp_msg_med
        TEST_MED_SENT=true
        
        sleep 5
        
        # Check MailHog (Count should be 0)
        MAIL_DATA_MED=$(curl -s http://localhost:8025/api/v2/messages)
        COUNT_MED=$(echo "$MAIL_DATA_MED" | python3 -c "import sys, json; print(json.load(sys.stdin).get('total', 0))")
        
        if [ "$COUNT_MED" -gt 0 ]; then
            TEST_MED_EMAIL_RECEIVED=true # This is a failure case for the task
        fi
    fi
else
    echo "Channel is not STARTED (Status: $CHANNEL_STATUS). Skipping functional tests."
fi

# --- EXPORT JSON ---

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_channel_count": $INITIAL_COUNT,
    "current_channel_count": $CURRENT_COUNT,
    "channel_found": $(if [ -n "$CHANNEL_ID" ]; then echo "true"; else echo "false"; fi),
    "channel_id": "$CHANNEL_ID",
    "channel_status": "$CHANNEL_STATUS",
    "functional_test": {
        "icu_msg_sent": $TEST_ICU_SENT,
        "icu_email_received": $TEST_ICU_EMAIL_RECEIVED,
        "icu_email_subject": "$(echo $ICU_EMAIL_SUBJECT | sed 's/"/\\"/g')",
        "icu_email_body_snippet": "$(echo $ICU_EMAIL_BODY | head -c 100 | sed 's/"/\\"/g')",
        "med_msg_sent": $TEST_MED_SENT,
        "med_email_received": $TEST_MED_EMAIL_RECEIVED
    },
    "channel_config_xml": "$(echo "$CHANNEL_CONFIG" | base64 -w 0)",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save to public location
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="