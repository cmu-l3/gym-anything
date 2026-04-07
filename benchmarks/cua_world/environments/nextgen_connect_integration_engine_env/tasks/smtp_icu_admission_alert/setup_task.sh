#!/bin/bash
echo "=== Setting up ICU Admission Alert task ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Start MailHog (SMTP Test Server)
echo "Starting MailHog..."
# Check if running, if not start it
if ! docker ps | grep -q mailhog; then
    docker run -d \
        --name mailhog \
        --restart unless-stopped \
        --network nextgen-network \
        -p 1025:1025 \
        -p 8025:8025 \
        mailhog/mailhog:latest
    
    # Wait for MailHog
    echo "Waiting for MailHog..."
    for i in {1..30}; do
        if curl -s http://localhost:8025/api/v2/messages > /dev/null; then
            echo "MailHog ready."
            break
        fi
        sleep 1
    done
else
    echo "MailHog already running."
    # Clear any existing messages
    curl -s -X DELETE http://localhost:8025/api/v1/messages > /dev/null 2>&1 || true
fi

# 2. Verify NextGen Connect is ready
echo "Waiting for NextGen Connect API..."
wait_for_api 60 || echo "WARNING: API might not be ready yet."

# 3. Record initial channel count (Anti-gaming)
INITIAL_COUNT=$(get_channel_count)
echo "$INITIAL_COUNT" > /tmp/initial_channel_count.txt
echo "Initial channel count: $INITIAL_COUNT"

# 4. Prepare Test Data (Hidden from agent usually, but used by export script)
mkdir -p /tmp/test_data

# ICU Admission Message
cat > /tmp/test_data/icu_adt.hl7 <<EOF
MSH|^~\\&|ADT|HOSPITAL|MIRTH|CONNECT|202501011200||ADT^A01|MSG001|P|2.3
EVN|A01|202501011200
PID|1||1001^^^HOSPITAL^MR||TESTPATIENT^ICU^USER||19800101|M
PV1|1|I|ICU^01^01^^^HOSPITAL||||1234^DOCTOR^ATTENDING
EOF

# General Ward Admission Message (Should be filtered)
cat > /tmp/test_data/med_adt.hl7 <<EOF
MSH|^~\\&|ADT|HOSPITAL|MIRTH|CONNECT|202501011205||ADT^A01|MSG002|P|2.3
EVN|A01|202501011205
PID|1||1002^^^HOSPITAL^MR||TESTPATIENT^MED^USER||19850101|F
PV1|1|I|MED^02^02^^^HOSPITAL||||5678^DOCTOR^RESIDENT
EOF

# 5. Open Firefox to Landing Page
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080' &"
    sleep 5
fi
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Capture Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="