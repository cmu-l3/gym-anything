#!/bin/bash
echo "=== Setting up Preprocessor Message Normalizer task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for API to be ready
wait_for_api 120

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
echo "$INITIAL_COUNT" > /tmp/initial_channel_count.txt
echo "Initial channel count: $INITIAL_COUNT"

# Clean up any pre-existing output directory
rm -rf /tmp/normalized_messages 2>/dev/null || true
mkdir -p /tmp/normalized_messages
chmod 777 /tmp/normalized_messages

# Create the malformed test HL7 message file
# We explicitly use \n (LF) line endings and add trailing whitespace
# This simulates the "legacy system" output described in the task
cat > /home/ga/test_message.hl7 << 'MSGEOF'
MSH|^~\&|OMNICELL|PHARMACY|NEXTGEN|HIS|20240115143052||RDE^O11^RDE_O11|MSG20240115143052|P|2.5.1   
PID|1||MRN78234^^^HOSP^MR||DOE^JANE^M||19670423|F|||456 OAK AVE^^SPRINGFIELD^IL^62704||2175559876   
PV1|1|I|4EAST^401^A^^^^HOSP||||1234567890^SMITH^ROBERT^J^^^MD|9876543210^JONES^SARAH^A^^^MD|||MED||||||||V123456789|||||||||||||||||||||||||20240115083000   
ORC|NW|ORD889234|ORD889234||CM||||20240115143000|||1234567890^SMITH^ROBERT^J^^^MD   
RXO|00069-3060-83^AMOXICILLIN 500MG CAP^NDC|500||MG|CAPSULE|PO||||30|EA   
RXE|1^BID&TWICE A DAY&HL70335|00069-3060-83^AMOXICILLIN 500MG CAP^NDC|500||MG|CAPSULE|PO|||30|EA|||||||||||||||||||20240115143000|20240125143000   
RXR|PO^ORAL^HL70162   
MSGEOF

# Ensure the file strictly uses LF (Unix) line endings for the test case
sed -i 's/\r//g' /home/ga/test_message.hl7

# Set permissions
chown ga:ga /home/ga/test_message.hl7
chmod 644 /home/ga/test_message.hl7

# Ensure output directory exists inside Docker container as well
# (NextGen Connect runs as a distinct user inside Docker)
docker exec nextgen-connect mkdir -p /tmp/normalized_messages 2>/dev/null || true
docker exec nextgen-connect chmod 777 /tmp/normalized_messages 2>/dev/null || true

# Ensure Firefox is visible and on landing page
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080' &"
    sleep 5
fi

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "Test message created at /home/ga/test_message.hl7"
echo "Output directory prepared at /tmp/normalized_messages"