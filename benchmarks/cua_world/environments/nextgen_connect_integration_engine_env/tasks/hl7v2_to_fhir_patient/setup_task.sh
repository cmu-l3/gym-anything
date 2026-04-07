#!/bin/bash
echo "=== Setting up HL7v2 to FHIR Patient task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure API is ready
echo "Waiting for NextGen Connect API..."
wait_for_api 60 || echo "Warning: API not yet fully ready"

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
echo "$INITIAL_COUNT" > /tmp/initial_channel_count.txt

# Prepare output directory with wide permissions so Docker container can write to it
mkdir -p /tmp/fhir_output
chmod 777 /tmp/fhir_output
# Also ensure the directory exists inside the container's perspective
docker exec nextgen-connect mkdir -p /tmp/fhir_output 2>/dev/null || true
docker exec nextgen-connect chmod 777 /tmp/fhir_output 2>/dev/null || true

# Clean up any existing files in output
rm -f /tmp/fhir_output/*.json

# Check port 6661 availability
if nc -z localhost 6661 2>/dev/null; then
    echo "Warning: Port 6661 seems to be in use. Trying to clear..."
    # Cannot easily kill internal listeners without stopping channels, 
    # but we can warn the agent or rely on them to fix it.
fi

# Create the test HL7 message file
cat > /home/ga/test_adt.hl7 << 'EOF'
MSH|^~\&|EPIC|MAIN_HOSP|FHIR_GW|DEST_SYS|20240115120000||ADT^A01^ADT_A01|MSG00001|P|2.5.1|||AL|NE
EVN|A01|20240115120000
PID|1||MRN12345^^^MAIN_HOSP^MR~987654321^^^SSA^SS||SMITH^JOHN^MICHAEL^^MR||19780523|M|||123 OAK STREET^^CHICAGO^IL^60601^US||3125551234^PRN^PH|||M|CAT|ACCT001
PV1|1|I|ICU^0101^01||||1234^JONES^SARAH^^DR|||MED||||||||VN98765|||||||||||||||||||||||||20240115120000
EOF
chown ga:ga /home/ga/test_adt.hl7

# Ensure Firefox is running (Agent needs dashboard)
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'https://localhost:8443' &"
    sleep 5
fi

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "Test message created at: /home/ga/test_adt.hl7"