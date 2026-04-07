#!/bin/bash
echo "=== Exporting Custom ACK Task Result ==="

source /workspace/scripts/task_utils.sh

# 1. Python Script to perform the Dynamic Verification
# This script acts as the "Analyzer" sending a test message with a random ID
# and capturing the response.
cat > /tmp/verify_ack.py << 'EOF'
import socket
import uuid
import time
import json
import sys
import os

def create_mllp_message(content):
    return b'\x0b' + content.encode('utf-8') + b'\x1c\x0d'

def parse_mllp_response(sock):
    data = b''
    try:
        # Simple MLLP reader
        while True:
            chunk = sock.recv(1024)
            if not chunk:
                break
            data += chunk
            if b'\x1c\x0d' in data:
                break
    except socket.timeout:
        pass
    
    # Strip MLLP framing
    if data.startswith(b'\x0b'):
        data = data[1:]
    if data.endswith(b'\x1c\x0d'):
        data = data[:-2]
    return data.decode('utf-8', errors='ignore')

def main():
    HOST = '127.0.0.1'
    PORT = 6661
    
    # Generate a unique transaction ID for this test run
    # This prevents the agent from hardcoding "TX-SAMPLE-999"
    test_id = f"TEST-{uuid.uuid4().hex[:8].upper()}"
    
    msg_content = (
        f"MSH|^~\\&|TESTER|APP|NEXTGEN|HOSP|{time.strftime('%Y%m%d%H%M%S')}||ADT^A01|MSG{uuid.uuid4().hex[:4]}|P|2.3\r"
        f"PID|1||1001^^^MRN||TEST^PATIENT\r"
        f"ZID|1|{test_id}|\r"
    )
    
    result = {
        "connected": False,
        "sent_id": test_id,
        "received_response": None,
        "zak_found": False,
        "id_echoed": False,
        "error": None
    }
    
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(5)
    
    try:
        sock.connect((HOST, PORT))
        result["connected"] = True
        
        sock.sendall(create_mllp_message(msg_content))
        response = parse_mllp_response(sock)
        
        result["received_response"] = response
        
        # Analyze response
        if response:
            segments = response.split('\r')
            for seg in segments:
                if seg.startswith('ZAK'):
                    result["zak_found"] = True
                    fields = seg.split('|')
                    if len(fields) > 2 and fields[2] == test_id:
                        result["id_echoed"] = True
                    break
                    
    except ConnectionRefusedError:
        result["error"] = "Connection refused - Channel not listening"
    except Exception as e:
        result["error"] = str(e)
    finally:
        sock.close()
        
    print(json.dumps(result))

if __name__ == "__main__":
    main()
EOF

# 2. Run the verification script
echo "Running dynamic verification..."
# Wait a moment in case the agent just deployed
sleep 2
python3 /tmp/verify_ack.py > /tmp/verification_output.json 2>/dev/null || echo '{"error": "Script failed"}' > /tmp/verification_output.json

# 3. Check for file persistence (the File Writer requirement)
# We expect a file created AFTER the task started
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_OUTPUT_DIR="/home/ga/received_results"
FILE_SAVED="false"
SAVED_FILE_PATH=""

if [ -d "$FILE_OUTPUT_DIR" ]; then
    # Find any file modified after task start
    RECENT_FILE=$(find "$FILE_OUTPUT_DIR" -type f -newermt "@$TASK_START" | head -n 1)
    if [ -n "$RECENT_FILE" ]; then
        FILE_SAVED="true"
        SAVED_FILE_PATH="$RECENT_FILE"
    fi
fi

# 4. Check if channel is deployed via API (Secondary check)
CHANNEL_DEPLOYED="false"
CHANNEL_ID=$(get_channel_id "Analyzer_Gateway")
if [ -n "$CHANNEL_ID" ]; then
    STATUS=$(get_channel_status_api "$CHANNEL_ID")
    if [ "$STATUS" == "STARTED" ]; then
        CHANNEL_DEPLOYED="true"
    fi
fi

# 5. Take final screenshot
take_screenshot /tmp/task_final.png

# 6. Combine all results into final JSON
# We merge the python verification output with the file/channel checks
cat <<EOF > /tmp/task_result.json
{
    "dynamic_verification": $(cat /tmp/verification_output.json),
    "file_persistence": {
        "file_saved": $FILE_SAVED,
        "path": "$SAVED_FILE_PATH"
    },
    "channel_status": {
        "deployed": $CHANNEL_DEPLOYED,
        "channel_id": "$CHANNEL_ID"
    },
    "timestamp": $(date +%s)
}
EOF

# Set permissions so the host can read it
chmod 644 /tmp/task_result.json

echo "=== Export Complete ==="
cat /tmp/task_result.json