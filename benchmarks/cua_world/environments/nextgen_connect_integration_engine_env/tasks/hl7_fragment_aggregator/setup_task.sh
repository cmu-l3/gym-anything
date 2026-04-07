#!/bin/bash
echo "=== Setting up HL7 Fragment Aggregator task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
echo "$INITIAL_COUNT" > /tmp/initial_channel_count.txt

# Create directories
mkdir -p /home/ga/lab_fragments
mkdir -p /home/ga/aggregated_output
chown -R ga:ga /home/ga/lab_fragments /home/ga/aggregated_output
chmod 777 /home/ga/lab_fragments /home/ga/aggregated_output

# Generate HL7 Fragment 1 (Cholesterol)
cat > /home/ga/lab_fragments/fragment_1.hl7 <<EOF
MSH|^~\&|POC_DEVICE|LAB|EMR|HOSP|20231025100000||ORU^R01|MSG001|P|2.5
PID|1||PAT12345^^^MRN||DOE^JOHN||19800101|M
OBR|1|ORD123|FILL123|LIPID^Lipid Panel|||20231025095000|||||||||||||1/3
OBX|1|NM|2093-3^Cholesterol||200|mg/dL|100-200|N|||F
EOF

# Generate HL7 Fragment 2 (HDL)
cat > /home/ga/lab_fragments/fragment_2.hl7 <<EOF
MSH|^~\&|POC_DEVICE|LAB|EMR|HOSP|20231025100001||ORU^R01|MSG002|P|2.5
PID|1||PAT12345^^^MRN||DOE^JOHN||19800101|M
OBR|1|ORD123|FILL123|LIPID^Lipid Panel|||20231025095000|||||||||||||2/3
OBX|1|NM|2085-9^HDL Cholesterol||50|mg/dL|>40|N|||F
EOF

# Generate HL7 Fragment 3 (LDL)
cat > /home/ga/lab_fragments/fragment_3.hl7 <<EOF
MSH|^~\&|POC_DEVICE|LAB|EMR|HOSP|20231025100002||ORU^R01|MSG003|P|2.5
PID|1||PAT12345^^^MRN||DOE^JOHN||19800101|M
OBR|1|ORD123|FILL123|LIPID^Lipid Panel|||20231025095000|||||||||||||3/3
OBX|1|NM|2089-1^LDL Cholesterol||130|mg/dL|<100|H|||F
EOF

chown ga:ga /home/ga/lab_fragments/*.hl7

# Open a terminal with instructions
DISPLAY=:1 gnome-terminal --geometry=100x30+50+50 -- bash -c '
echo "========================================================"
echo " TASK: HL7 Fragment Aggregator"
echo "========================================================"
echo "Goal: Aggregate 3 fragmented messages into 1 complete result."
echo ""
echo "Input Directory: /home/ga/lab_fragments/"
echo "  - fragment_1.hl7 (1/3)"
echo "  - fragment_2.hl7 (2/3)"
echo "  - fragment_3.hl7 (3/3)"
echo ""
echo "Output Directory: /home/ga/aggregated_output/"
echo ""
echo "Logic Required:"
echo "  1. Extract Order ID (OBR-2) and Sequence (OBR-20)"
echo "  2. Store OBX segments in GlobalChannelMap"
echo "  3. ONLY send the combined message when sequence is 3/3"
echo "  4. Discard/Filter the first two partial messages"
echo ""
echo "NextGen Connect API: https://localhost:8443/api"
echo "Creds: admin / admin"
echo "========================================================"
exec bash
' 2>/dev/null &

sleep 2
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="