#!/bin/bash
echo "=== Exporting Cross-Channel Token Cache Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Prepare the functional test script
# This script runs INSIDE the container/environment to test the channels locally
cat > /tmp/test_channels.py << 'EOF'
import socket
import time
import os
import glob
import json
import sys

RESULTS = {
    "token_manager_listening": False,
    "data_sender_listening": False,
    "cycle_a_passed": False,
    "cycle_b_passed": False,
    "output_files_created": 0,
    "errors": []
}

TOKEN_PORT = 6661
DATA_PORT = 6662
OUTPUT_DIR = "/tmp/authenticated_output"

def send_tcp(host, port, data):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(3)
            s.connect((host, port))
            s.sendall(data.encode('utf-8'))
            # For MLLP, we might expect an ACK, but we just need to send for now
            try:
                s.recv(1024)
            except socket.timeout:
                pass
        return True
    except Exception as e:
        return False

def check_port(port):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(1)
            return s.connect_ex(('localhost', port)) == 0
    except:
        return False

def get_latest_file(directory):
    files = list(filter(os.path.isfile, glob.glob(directory + "/*")))
    if not files:
        return None
    files.sort(key=lambda x: os.path.getmtime(x))
    return files[-1]

def read_file(filepath):
    try:
        with open(filepath, 'r') as f:
            return f.read()
    except:
        return ""

def mllp_wrap(message):
    # Wrap in MLLP: <VT> message <FS><CR>
    return f"\x0b{message}\x1c\r"

# 1. Check ports
RESULTS["token_manager_listening"] = check_port(TOKEN_PORT)
RESULTS["data_sender_listening"] = check_port(DATA_PORT)

if not RESULTS["token_manager_listening"] or not RESULTS["data_sender_listening"]:
    RESULTS["errors"].append(f"Ports not listening. 6661={RESULTS['token_manager_listening']}, 6662={RESULTS['data_sender_listening']}")
    print(json.dumps(RESULTS))
    sys.exit(0)

# 2. Cycle A: Set Token A -> Send Msg A -> Verify
token_a = "TOKEN_ALPHA_123"
json_payload = json.dumps({"access_token": token_a})
hl7_payload_a = "MSH|^~\\&|SEND|APP|REC|APP|20240101||ADT^A01|MSG001|P|2.3\rEVN|A01|20240101"

print(f"Executing Cycle A with token: {token_a}")
send_tcp('localhost', TOKEN_PORT, json_payload)
time.sleep(2) # Wait for processing

# Clear old files to ensure we catch new one
old_files = set(glob.glob(OUTPUT_DIR + "/*"))

send_tcp('localhost', DATA_PORT, mllp_wrap(hl7_payload_a))
time.sleep(2)

new_files = set(glob.glob(OUTPUT_DIR + "/*")) - old_files
if new_files:
    latest = list(new_files)[0]
    content = read_file(latest)
    if f"Authorization: Bearer {token_a}" in content:
        RESULTS["cycle_a_passed"] = True
    else:
        RESULTS["errors"].append(f"Cycle A failed: Expected header with {token_a} not found in {latest}")
else:
    RESULTS["errors"].append("Cycle A failed: No output file created")

# 3. Cycle B: Update Token -> Send Msg B -> Verify (Dynamic Check)
token_b = "TOKEN_BRAVO_999"
json_payload_b = json.dumps({"access_token": token_b})
hl7_payload_b = "MSH|^~\\&|SEND|APP|REC|APP|20240102||ADT^A01|MSG002|P|2.3\rEVN|A01|20240102"

print(f"Executing Cycle B with token: {token_b}")
send_tcp('localhost', TOKEN_PORT, json_payload_b)
time.sleep(2)

# Snapshot files again
old_files_b = set(glob.glob(OUTPUT_DIR + "/*"))

send_tcp('localhost', DATA_PORT, mllp_wrap(hl7_payload_b))
time.sleep(2)

new_files_b = set(glob.glob(OUTPUT_DIR + "/*")) - old_files_b
if new_files_b:
    latest_b = list(new_files_b)[0]
    content_b = read_file(latest_b)
    if f"Authorization: Bearer {token_b}" in content_b:
        RESULTS["cycle_b_passed"] = True
    else:
        RESULTS["errors"].append(f"Cycle B failed: Expected header with {token_b} not found in {latest_b}")
else:
    RESULTS["errors"].append("Cycle B failed: No output file created")

RESULTS["output_files_created"] = len(glob.glob(OUTPUT_DIR + "/*"))

print(json.dumps(RESULTS))
EOF

# Run the python test script
echo "Running functional tests..."
python3 /tmp/test_channels.py > /tmp/functional_test_result.json 2>/dev/null || echo '{"error": "Script failed"}' > /tmp/functional_test_result.json

# Check channel count via DB
FINAL_CHANNEL_COUNT=$(get_channel_count)
INITIAL_CHANNEL_COUNT=$(cat /tmp/initial_channel_count 2>/dev/null || echo "0")

# Collect results
# We embed the functional test JSON inside the main result JSON
FUNCTIONAL_JSON=$(cat /tmp/functional_test_result.json)

# Create final JSON
cat > /tmp/final_result_temp.json << EOF
{
    "initial_channel_count": $INITIAL_CHANNEL_COUNT,
    "final_channel_count": $FINAL_CHANNEL_COUNT,
    "functional_tests": $FUNCTIONAL_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location with permissions
write_result_json "/tmp/task_result.json" "$(cat /tmp/final_result_temp.json)"

echo "Result Export Complete:"
cat /tmp/task_result.json