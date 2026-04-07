#!/bin/bash
set -e
echo "=== Setting up Failed Message Archiver Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Prepare sample data
echo "Creating sample HL7 message..."
cat > /home/ga/sample.hl7 <<EOF
MSH|^~\\&|HIS|HOSPITAL|LIS|LAB|20240315100000||ADT^A01|MSG00001|P|2.5
EVN|A01|20240315100000
PID|1||12345^^^MRN||DOE^JANE^A||19850101|F|||123 MAIN ST^^SPRINGFIELD^IL^62704
PV1|1|I|ICU^01^01||||1234^DOCTOR^M||||||||||||||||||||||||||20240315100000
EOF
chown ga:ga /home/ga/sample.hl7
chmod 644 /home/ga/sample.hl7

# 3. Create the archive directory inside the container
echo "Creating archive directory in container..."
docker exec nextgen-connect mkdir -p /tmp/failed_messages
docker exec nextgen-connect chmod 777 /tmp/failed_messages

# 4. Clean up any previous state (in case of retry)
docker exec nextgen-connect sh -c "rm -f /tmp/failed_messages/*"

# 5. Record initial state
INITIAL_CHANNELS=$(get_channel_count)
echo "$INITIAL_CHANNELS" > /tmp/initial_channel_count.txt

# 6. Ensure NextGen Connect is responsive
wait_for_api 30

# 7. Open Terminal for the agent
DISPLAY=:1 gnome-terminal --geometry=120x35+70+30 -- bash -c '
echo "============================================"
echo " NextGen Connect - Failed Message Archiver"
echo "============================================"
echo ""
echo "TASK: Configure a Fail-Safe Archival Channel"
echo ""
echo "1. Create channel: Fail_Safe_Archiver"
echo "2. Source: TCP Listener @ 6661"
echo "3. Dest: TCP Sender @ localhost:9999 (Must FAIL)"
echo "   - Queue: Never"
echo "   - Retry: 0"
echo "4. Script: Post-Processor to write failed msgs"
echo "   - Target Dir: /tmp/failed_messages/"
echo "   - Filename: \${messageId}.hl7"
echo ""
echo "Sample Data: /home/ga/sample.hl7"
echo "API: https://localhost:8443/api (admin/admin)"
echo "     Header: X-Requested-With: OpenAPI"
echo ""
exec bash
' 2>/dev/null &

# 8. Maximize terminal
sleep 1
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 9. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="