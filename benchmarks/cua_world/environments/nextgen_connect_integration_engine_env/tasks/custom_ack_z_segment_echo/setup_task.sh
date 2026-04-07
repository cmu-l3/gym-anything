#!/bin/bash
echo "=== Setting up Custom ACK Task ==="

source /workspace/scripts/task_utils.sh

# 1. Prepare sample data
# Create a realistic HL7 message with the custom ZID segment
cat > /home/ga/sample_zid_message.hl7 <<EOF
MSH|^~\&|ANALYZER|LAB|NEXTGEN|HOSP|202501010000||ORU^R01|MSG001|P|2.3
PID|1||12345^^^MRN||DOE^JOHN
OBR|1|ORD123|ACC456|80004^ELECTROLYTES^CPT
ZID|1|TX-SAMPLE-999|
EOF
chown ga:ga /home/ga/sample_zid_message.hl7
chmod 644 /home/ga/sample_zid_message.hl7

# 2. Ensure output directory exists (so file writer doesn't fail on permissions if agent is lazy)
mkdir -p /home/ga/received_results
chown ga:ga /home/ga/received_results
chmod 777 /home/ga/received_results

# 3. Clean previous state
# Remove any existing channels to ensure clean slate
# (In a real scenario we might keep others, but here we want isolation)
# Note: We rely on the agent to create the channel, so we just check port availability
if netstat -tuln | grep -q ":6661 "; then
    echo "WARNING: Port 6661 is already in use. Attempting to clear..."
    # This might kill the java process if not careful, but usually channels bind specific ports
    # We'll assume the environment is clean or previous task cleanup worked.
fi

# 4. Open Terminal with Instructions
# Launch a terminal with helpful context for the agent
DISPLAY=:1 gnome-terminal --geometry=100x30+50+50 -- bash -c '
echo "======================================================="
echo " TASK: Custom ACK with Z-Segment Echo"
echo "======================================================="
echo "You need to create a channel that:"
echo " 1. Listens on TCP Port 6661"
echo " 2. Saves messages to /home/ga/received_results/"
echo " 3. Sends a CUSTOM RESPONSE (ACK)"
echo ""
echo "Protocol Requirement:"
echo " INPUT:  ... \r ZID|1|<TRANS_ID>| \r ..."
echo " OUTPUT: ... \r MSA|AA|... \r ZAK|1|<TRANS_ID>| \r ..."
echo ""
echo "The <TRANS_ID> must be dynamically extracted from the"
echo "incoming message. Hardcoding it will fail verification."
echo ""
echo "Sample message: /home/ga/sample_zid_message.hl7"
echo "======================================================="
echo ""
exec bash
' 2>/dev/null &

# 5. Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_file_count.txt

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="