#!/bin/bash
echo "=== Setting up HL7 Canonical XML Transformer Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
echo "$INITIAL_COUNT" > /tmp/initial_channel_count.txt

# Ensure output directory does NOT exist (force agent to create it or clean start)
rm -rf /home/ga/xml_out
# But ensure parent exists
mkdir -p /home/ga

# Create a sample HL7 file for the agent to use
cat > /home/ga/sample_adt.hl7 <<EOF
MSH|^~\&|HIS|HOSPITAL|CPI|DATALAKE|20240308120000||ADT^A01|MSG001|P|2.3
EVN|A01|20240308120000
PID|1||MRN12345^^^HOSPITAL||DOE^JOHN^A||19800101|M|||123 MAIN ST^^BOSTON^MA^02110
PV1|1|I|ICU^101^1
EOF
chown ga:ga /home/ga/sample_adt.hl7
chmod 644 /home/ga/sample_adt.hl7

# Open a terminal window with context
DISPLAY=:1 gnome-terminal --geometry=100x30+50+50 -- bash -c '
echo "======================================================="
echo " Task: HL7 v2 to Canonical XML Transformation"
echo "======================================================="
echo "1. Create channel: Canonical_XML_Transformer"
echo "2. Source: TCP Listener on Port 6661 (HL7 v2)"
echo "3. Destination: File Writer to /home/ga/xml_out/ (XML)"
echo "4. Implement logic to map fields and normalize gender:"
echo "   M -> Male, F -> Female"
echo ""
echo "Sample data: /home/ga/sample_adt.hl7"
echo ""
echo "REST API: https://localhost:8443/api (admin/admin)"
echo "======================================================="
exec bash
' 2>/dev/null &

# Wait for terminal
sleep 2
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="