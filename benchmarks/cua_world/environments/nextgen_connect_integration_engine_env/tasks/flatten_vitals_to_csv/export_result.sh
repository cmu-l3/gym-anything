#!/bin/bash
echo "=== Exporting flatten_vitals_to_csv results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/tmp/research_data/vitals.csv"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check if channel is listening on port 6661
LISTENING="false"
if netstat -tuln | grep -q ":6661 "; then
    LISTENING="true"
fi

# 2. Functional Test: Send synthetic messages and verify output
# We will use python to generate messages, send them, and verify the file content
# This runs INSIDE the container to ensure connectivity

cat > /tmp/verify_logic.py << 'EOF'
import socket
import time
import os
import csv
import sys

# Define test cases
# (Message, Expected CSV Line)
test_messages = [
    # Case 1: All vitals present + extra noise
    (
        "MSH|^~\\&|APP|FAC|REC|FAC|202401010000||ORU^R01|TEST001|P|2.5\r"
        "PID|1||PT1001^^^MRN||TEST^ONE\r"
        "OBR|1|||VITALS|||202401011200\r"
        "OBX|1|NM|8867-4^HR||75|bpm\r"
        "OBX|2|NM|8480-6^SYS||115|mm[Hg]\r"
        "OBX|3|NM|8462-4^DIA||75|mm[Hg]\r"
        "OBX|4|NM|2708-6^SPO2||99|%\r"
        "OBX|5|NM|5555-5^NOISE||12|units\r",
        "PT1001,202401011200,75,115,75,99"
    ),
    # Case 2: Missing BP (Sparsity check)
    (
        "MSH|^~\\&|APP|FAC|REC|FAC|202401010000||ORU^R01|TEST002|P|2.5\r"
        "PID|1||PT1002^^^MRN||TEST^TWO\r"
        "OBR|1|||VITALS|||202401011300\r"
        "OBX|1|NM|8867-4^HR||82|bpm\r"
        "OBX|2|NM|2708-6^SPO2||95|%\r",
        "PT1002,202401011300,82,,,95"
    ),
    # Case 3: Mixed order and empty values
    (
        "MSH|^~\\&|APP|FAC|REC|FAC|202401010000||ORU^R01|TEST003|P|2.5\r"
        "PID|1||PT1003^^^MRN||TEST^THREE\r"
        "OBR|1|||VITALS|||202401011400\r"
        "OBX|1|NM|2708-6^SPO2||98|%\r"
        "OBX|2|NM|8462-4^DIA||80|mm[Hg]\r"
        "OBX|3|NM|8480-6^SYS||130|mm[Hg]\r"
        "OBX|4|NM|8867-4^HR||60|bpm\r",
        "PT1003,202401011400,60,130,80,98"
    )
]

def send_mllp(host, port, message):
    try:
        # Wrap in MLLP: <VT> message <FS><CR>
        # VT = 0x0b, FS = 0x1c, CR = 0x0d
        mllp_msg = b'\x0b' + message.encode('utf-8') + b'\x1c\x0d'
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(2)
            s.connect((host, port))
            s.sendall(mllp_msg)
            # Wait for ACK (optional, but good practice)
            try:
                s.recv(1024)
            except:
                pass
        return True
    except Exception as e:
        print(f"Failed to send message: {e}")
        return False

# Clear output file if it exists to isolate test results
output_path = "/tmp/research_data/vitals.csv"
if os.path.exists(output_path):
    try:
        os.remove(output_path)
    except:
        pass
    # Re-create directory if needed
    os.makedirs(os.path.dirname(output_path), exist_ok=True)

# Send messages
messages_sent = 0
for msg, expected in test_messages:
    if send_mllp('localhost', 6661, msg):
        messages_sent += 1
        time.sleep(0.5) # Give Mirth a moment to process

print(f"Sent {messages_sent} test messages")

# Give Mirth time to flush to disk
time.sleep(2)

# Verify Output
lines_found = 0
correct_lines = 0
content_feedback = []

if os.path.exists(output_path):
    try:
        with open(output_path, 'r') as f:
            lines = [l.strip() for l in f.readlines() if l.strip()]
            lines_found = len(lines)
            
            # Simple check: Check if expected strings are in the file
            # Note: We rely on exact string match because we control the input
            for _, expected in test_messages:
                if expected in lines:
                    correct_lines += 1
                else:
                    content_feedback.append(f"Missing expected line: {expected}")
    except Exception as e:
        content_feedback.append(f"Error reading file: {e}")
else:
    content_feedback.append("Output file not created")

import json
result = {
    "listening": True,
    "messages_sent": messages_sent,
    "file_exists": os.path.exists(output_path),
    "lines_found": lines_found,
    "correct_lines": correct_lines,
    "content_feedback": content_feedback
}

with open("/tmp/verification_results.json", "w") as f:
    json.dump(result, f)

EOF

# Run verification logic
TEST_RESULT_JSON="{}"
if [ "$LISTENING" = "true" ]; then
    echo "Port 6661 is open. Running functional tests..."
    python3 /tmp/verify_logic.py
    if [ -f /tmp/verification_results.json ]; then
        TEST_RESULT_JSON=$(cat /tmp/verification_results.json)
    fi
else
    echo "Port 6661 is NOT open."
    TEST_RESULT_JSON='{"listening": false, "messages_sent": 0, "file_exists": false, "lines_found": 0, "correct_lines": 0, "content_feedback": ["Port 6661 not listening"]}'
fi

# Get channel status
CHANNEL_COUNT=$(get_channel_count)
# We can try to get the specific channel status via API if we knew the ID, but getting count is a good proxy

# Create final JSON output
FINAL_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$FINAL_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $(date +%s),
    "channel_count": $CHANNEL_COUNT,
    "test_results": $TEST_RESULT_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$FINAL_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$FINAL_JSON"

echo "=== Export complete ==="
cat /tmp/task_result.json