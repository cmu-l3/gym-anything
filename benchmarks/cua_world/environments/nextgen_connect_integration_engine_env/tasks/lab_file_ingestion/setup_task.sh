#!/bin/bash
echo "=== Setting up lab_file_ingestion task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
echo "$INITIAL_COUNT" > /tmp/initial_channel_count.txt

# Create the test HL7 file on the host (for the agent to copy later)
cat > /home/ga/test_oru.hl7 <<EOF
MSH|^~\&|LABSYSTEM|MAINLAB|OLDRECEIVER|FACILITY|20240115103000||ORU^R01^ORU_R01|MSG00001|P|2.5.1|||AL|NE
PID|1||PAT12345^^^HOSP^MR||JOHNSON^ROBERT^A||19650812|M|||456 OAK STREET^^SPRINGFIELD^IL^62704||2175551234|||S|||999-88-7777
PV1|1|O|CLINIC^^^HOSP||||1234^SMITH^JOHN^D^MD|5678^JONES^SARAH^M^MD|||||||||OUTPT|VN12345
ORC|RE|ORD001|FIL001||CM||||20240115090000|||1234^SMITH^JOHN^D^MD
OBR|1|ORD001|FIL001|58410-2^CBC^LN|||20240115090000|||||||20240115093000||1234^SMITH^JOHN^D^MD||||||20240115103000|||F
OBX|1|NM|6690-2^WBC^LN||7.5|10*3/uL|4.5-11.0|N|||F|||20240115103000
OBX|2|NM|789-8^RBC^LN||4.85|10*6/uL|4.50-5.50|N|||F|||20240115103000
OBX|3|NM|718-7^Hemoglobin^LN||14.2|g/dL|13.5-17.5|N|||F|||20240115103000
EOF

chown ga:ga /home/ga/test_oru.hl7
chmod 644 /home/ga/test_oru.hl7

# Ensure NextGen Connect is running
if ! curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 | grep -q "200"; then
    echo "Waiting for NextGen Connect..."
    wait_for_nextgen_connect || true
fi

# Cleanup any previous directories in the container (to ensure clean state)
docker exec nextgen-connect rm -rf /opt/mirthdata/input /opt/mirthdata/output /opt/mirthdata/processed 2>/dev/null || true

# Open a terminal window for the agent
DISPLAY=:1 gnome-terminal --geometry=100x30+50+50 -- bash -c '
echo "============================================"
echo " NextGen Connect - Lab File Ingestion Task"
echo "============================================"
echo ""
echo "GOAL: Create a File Reader -> File Writer channel."
echo ""
echo "1. Create directories in container:"
echo "   docker exec nextgen-connect mkdir -p /opt/mirthdata/{input,output,processed}"
echo ""
echo "2. Configure Channel:"
echo "   - Source: File Reader (/opt/mirthdata/input)"
echo "   - Action after processing: Move to /opt/mirthdata/processed"
echo "   - Transformer: Set MSH-5 to 'LAB_REPOSITORY'"
echo "   - Dest: File Writer (/opt/mirthdata/output)"
echo ""
echo "3. Test Data:"
echo "   /home/ga/test_oru.hl7"
echo ""
echo "Access NextGen Connect at http://localhost:8080"
echo "API credentials: admin / admin"
echo "============================================"
echo ""
exec bash
' 2>/dev/null &

sleep 2
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="