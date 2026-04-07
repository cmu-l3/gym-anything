#!/bin/bash
set -e
echo "=== Setting up HL7 Batch File Splitter task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Source shared utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Ensure NextGen Connect API is ready
echo "Waiting for NextGen Connect..."
for i in {1..30}; do
    if curl -sk -o /dev/null https://localhost:8443/api/server/version; then
        echo "API is ready."
        break
    fi
    sleep 2
done

# Record initial channel count
INITIAL_COUNT=$(docker exec nextgen-postgres psql -U postgres -d mirthdb -t -A -c "SELECT COUNT(*) FROM channel;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_channel_count.txt

# Create local directories
mkdir -p /home/ga/hl7_input
mkdir -p /home/ga/hl7_output
chmod 777 /home/ga/hl7_input /home/ga/hl7_output

# Create the batch HL7 file with 5 ORU^R01 messages
# Using python to ensure correct \r delimiters which are standard for HL7 batching
cat > /tmp/build_batch.py << 'PYTHON_SCRIPT'
import os

# HL7 Standard Segment Delimiter
SEG_DELIM = "\r"

messages = []

# Message 1: CBC
msg1 = [
    "MSH|^~\\&|LAB|HOSP|EHR|HOSP|202401150830||ORU^R01|MSG001|P|2.5.1",
    "PID|1||PAT10001||Smith^Alice",
    "OBR|1|||CBC",
    "OBX|1|NM|WBC||7.2|10*3/uL"
]
messages.append(SEG_DELIM.join(msg1))

# Message 2: BMP
msg2 = [
    "MSH|^~\\&|LAB|HOSP|EHR|HOSP|202401150915||ORU^R01|MSG002|P|2.5.1",
    "PID|1||PAT10002||Johnson^Robert",
    "OBR|1|||BMP",
    "OBX|1|NM|NA||140|mmol/L"
]
messages.append(SEG_DELIM.join(msg2))

# Message 3: Lipid
msg3 = [
    "MSH|^~\\&|LAB|HOSP|EHR|HOSP|202401151000||ORU^R01|MSG003|P|2.5.1",
    "PID|1||PAT10003||Garcia^Maria",
    "OBR|1|||LIPID",
    "OBX|1|NM|CHOL||195|mg/dL"
]
messages.append(SEG_DELIM.join(msg3))

# Message 4: Urine
msg4 = [
    "MSH|^~\\&|LAB|HOSP|EHR|HOSP|202401151030||ORU^R01|MSG004|P|2.5.1",
    "PID|1||PAT10004||Williams^James",
    "OBR|1|||UA",
    "OBX|1|NM|PH||6.0|"
]
messages.append(SEG_DELIM.join(msg4))

# Message 5: A1C
msg5 = [
    "MSH|^~\\&|LAB|HOSP|EHR|HOSP|202401151100||ORU^R01|MSG005|P|2.5.1",
    "PID|1||PAT10005||Brown^Susan",
    "OBR|1|||A1C",
    "OBX|1|NM|A1C||5.8|%"
]
messages.append(SEG_DELIM.join(msg5))

# Join with newlines for the file (batch file format often implies MSH starts on new line)
# Some systems use \r\n between messages
batch_content = "\r\n".join(messages)

with open("/home/ga/hl7_input/lab_batch_20240115.hl7", "w") as f:
    f.write(batch_content)
PYTHON_SCRIPT

python3 /tmp/build_batch.py

# CRITICAL: Prepare container state
# NextGen Connect runs in a container. We need to create the directories INSIDE the container.
echo "Preparing container directories..."
docker exec nextgen-connect mkdir -p /var/hl7_input
docker exec nextgen-connect mkdir -p /var/hl7_output
docker exec nextgen-connect chmod 777 /var/hl7_output

# Copy the batch file into the container
docker cp /home/ga/hl7_input/lab_batch_20240115.hl7 nextgen-connect:/var/hl7_input/
docker exec nextgen-connect chmod 666 /var/hl7_input/lab_batch_20240115.hl7

# Ensure Firefox is open to the landing page
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'https://localhost:8443' &"
    sleep 5
fi

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="