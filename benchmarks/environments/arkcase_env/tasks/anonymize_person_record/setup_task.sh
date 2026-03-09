#!/bin/bash
set -e
echo "=== Setting up anonymize_person_record task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure port-forward is active and ArkCase is ready
ensure_portforward
wait_for_arkcase

echo "=== Creating Person record to be anonymized ==="

# Define Person Data
PERSON_NAME="Marcus"
PERSON_LAST="PII-Holder"
PERSON_EMAIL="marcus.holder@example.com"
PERSON_PHONE="555-019-2834"

# Create Person via API
# We try the standard CRM/People endpoint or plugin endpoint
# Note: In ArkCase 2021+, people are often under plugin/cpr/person or similar.
# We will use the generic people creation if specific one fails.

# Construct JSON payload
PAYLOAD=$(cat <<EOF
{
    "firstName": "$PERSON_NAME",
    "lastName": "$PERSON_LAST",
    "email": "$PERSON_EMAIL",
    "businessPhone": "$PERSON_PHONE",
    "personType": "GENERAL",
    "status": "ACTIVE"
}
EOF
)

# Attempt creation
echo "Sending API request..."
CREATE_RESPONSE=$(curl -sk -X POST \
    -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "$PAYLOAD" \
    "${ARKCASE_URL}/api/v1/plugin/cpr/person" 2>/dev/null)

echo "Create response: $CREATE_RESPONSE"

# Extract Person ID
PERSON_ID=$(echo "$CREATE_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('personId', d.get('id', '')))" 2>/dev/null || echo "")

if [ -z "$PERSON_ID" ]; then
    echo "ERROR: Failed to create person record. Trying fallback endpoint..."
    # Fallback attempt if plugin endpoint differs
    CREATE_RESPONSE=$(curl -sk -X POST \
        -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "$PAYLOAD" \
        "${ARKCASE_URL}/api/v1/service/people" 2>/dev/null)
    PERSON_ID=$(echo "$CREATE_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('personId', d.get('id', '')))" 2>/dev/null || echo "")
fi

if [ -z "$PERSON_ID" ]; then
    echo "CRITICAL ERROR: Could not create person record. API Response: $CREATE_RESPONSE"
    exit 1
fi

echo "Created Person ID: $PERSON_ID"
echo "$PERSON_ID" > /tmp/target_person_id.txt

# Create the request document for the agent
mkdir -p /home/ga/Documents
cat <<EOF > /home/ga/Documents/privacy_request.txt
PRIVACY REQUEST - RIGHT TO BE FORGOTTEN
=======================================
Request ID: GDPR-2025-0892
Date: $(date +%F)

Subject: Marcus PII-Holder
System ID: $PERSON_ID

Action Required:
The data subject has exercised their right to erasure. Please anonymize their record in the Case Management System immediately.

Instructions:
1. Search for person "Marcus PII-Holder".
2. Change First Name to "Redacted".
3. Change Last Name to "User-$PERSON_ID" (or "User-Anonymized").
4. Remove all contact methods (Email, Phone).
5. Save the record.

CONFIDENTIAL
EOF

chown ga:ga /home/ga/Documents/privacy_request.txt

# Prepare Firefox
# Kill any existing Firefox and clean lock files
pkill -9 -f firefox 2>/dev/null || true
sleep 2
find /home/ga -name ".parentlock" -delete 2>/dev/null || true
find /home/ga -name "parent.lock" -delete 2>/dev/null || true

# Launch Firefox on ArkCase login page
echo "Launching Firefox..."
# The Firefox snap profile already has the SSL exception stored
SNAP_PROFILE=$(find /home/ga/snap/firefox -name "prefs.js" 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo "")
if [ -n "$SNAP_PROFILE" ]; then
    su - ga -c "DISPLAY=:1 firefox -profile '$SNAP_PROFILE' 'https://localhost:9443/arkcase/login' &>/dev/null &" &
else
    su - ga -c "DISPLAY=:1 firefox 'https://localhost:9443/arkcase/login' &>/dev/null &" &
fi

# Wait for Firefox window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Firefox"; then
        break
    fi
    sleep 1
done

# Focus and maximize
focus_firefox
maximize_firefox
sleep 5

# Auto-login to ArkCase (UI automation)
# Login form coordinates in 1920x1080:
#   Username: (994, 312), Password: (994, 368), Log In button: (994, 438)
DISPLAY=:1 xdotool mousemove 994 312 click 1
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'arkcase-admin@dev.arkcase.com'
sleep 0.3
DISPLAY=:1 xdotool mousemove 994 368 click 1
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'ArkCase1234!'
sleep 0.3
DISPLAY=:1 xdotool mousemove 994 438 click 1
sleep 15

# Navigate to People module explicitly to help the agent start
DISPLAY=:1 xdotool key ctrl+l
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers 'https://localhost:9443/arkcase/#!/people'
DISPLAY=:1 xdotool key Return
sleep 8

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="