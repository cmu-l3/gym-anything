#!/bin/bash
echo "=== Setting up normalize_audit_ack task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Create documents directory
mkdir -p /home/ga/documents

# Create Sample HL7 ADT Message
cat > /home/ga/documents/sample_adt.hl7 <<EOF
MSH|^~\\&|EPIC|HOSPITAL|LIS|LAB|$(date +%Y%m%d%H%M%S)||ADT^A01|MSG00001|P|2.5.1
EVN|A01|$(date +%Y%m%d%H%M%S)
PID|1||100001^^^MRN||SMITH^JOHN^J||19800101|M|||123 MAIN ST^^ATLANTA^GA^30303
PV1|1|I|NORTH^101^1||||1234^DOC^ADMITTING||||||||||||||||||||||||||||||||||||$(date +%Y%m%d%H%M%S)
EOF
chown ga:ga /home/ga/documents/sample_adt.hl7
chmod 644 /home/ga/documents/sample_adt.hl7

# Create the Mock Legacy LIS Script (Python)
# This script listens on 6662 and returns ACKs with MISSING status text
cat > /usr/local/bin/mock_lis_server.py <<'PYTHON_EOF'
import socket
import re
import signal
import sys
import time

def signal_handler(sig, frame):
    sys.exit(0)

signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)

HOST = '0.0.0.0'
PORT = 6662
SB = b'\x0b'
EB = b'\x1c'
CR = b'\x0d'

print(f"Starting Mock LIS on {PORT}...")

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((HOST, PORT))
    s.listen()
    while True:
        conn, addr = s.accept()
        with conn:
            print(f"Connected by {addr}")
            data = b""
            while True:
                chunk = conn.recv(1024)
                if not chunk:
                    break
                data += chunk
                if EB in data and CR in data:
                    break
            
            if not data:
                continue

            # Extract Message Control ID (MSH-10)
            try:
                msg_str = data.decode('utf-8', errors='ignore')
                # Remove framing
                msg_str = msg_str.strip('\x0b\x1c\x0d')
                segments = msg_str.split('\r')
                msh_fields = segments[0].split('|')
                
                # MSH-10 is at index 9 (0-based split)
                ctrl_id = msh_fields[9] if len(msh_fields) > 9 else "UNKNOWN"
                
                # Determine ACK code (simulate occasional errors if ControlID starts with ERR)
                ack_code = "AE" if "ERR" in ctrl_id else "AA"
                
                # Construct Defective ACK (Missing text in MSA-3)
                # Format: MSH|^~\&|LIS|LAB|SendingApp|SendingFac|Date||ACK|ID|P|2.5.1
                #         MSA|AA|CtrlID|
                
                timestamp = time.strftime("%Y%m%d%H%M%S")
                ack_msg = f"MSH|^~\\&|LIS|LAB|EPIC|HOSPITAL|{timestamp}||ACK|ACK{timestamp}|P|2.5.1\rMSA|{ack_code}|{ctrl_id}|"
                
                response = SB + ack_msg.encode('utf-8') + EB + CR
                conn.sendall(response)
                print(f"Sent defective ACK for {ctrl_id}: {ack_msg}")
            except Exception as e:
                print(f"Error processing message: {e}")

PYTHON_EOF

chmod +x /usr/local/bin/mock_lis_server.py

# Start the mock server in background
nohup python3 /usr/local/bin/mock_lis_server.py > /var/log/mock_lis.log 2>&1 &
echo "Mock LIS started (PID $!)"

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure log file doesn't exist yet
rm -f /home/ga/ack_audit.log

echo "=== Setup complete ==="