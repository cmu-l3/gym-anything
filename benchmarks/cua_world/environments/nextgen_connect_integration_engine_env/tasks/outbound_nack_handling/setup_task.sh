#!/bin/bash
echo "=== Setting up outbound_nack_handling task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create the Simulated LIS (NACK Server) script
cat > /tmp/nack_server.py << 'EOF'
import socket
import time
import sys
import signal

HOST = '0.0.0.0'
PORT = 6699

def signal_handler(sig, frame):
    print("Shutting down NACK server...")
    sys.exit(0)

signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)

def create_nack(control_id):
    # HL7 MLLP framing: <VT>msg<FS><CR>
    # VT = \x0b, FS = \x1c, CR = \x0d
    ts = time.strftime("%Y%m%d%H%M%S")
    # MSA-1=AE (Application Error), MSA-3=Error Message
    msg = f"MSH|^~\\&|SIMULATOR|LAB|CONNECT|HOSPITAL|{ts}||ACK|{control_id}|P|2.3\rMSA|AE|{control_id}|Simulated Patient ID Error|"
    return b'\x0b' + msg.encode() + b'\x1c\r'

def start_server():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            s.bind((HOST, PORT))
            s.listen()
            print(f"NACK Server listening on {PORT}...")
        except Exception as e:
            print(f"Error binding to port {PORT}: {e}")
            return

        while True:
            try:
                conn, addr = s.accept()
                with conn:
                    print(f"Connected by {addr}")
                    data = b""
                    while True:
                        chunk = conn.recv(1024)
                        if not chunk: break
                        data += chunk
                        if b'\x1c' in data: # End of MLLP message
                            break
                    
                    if not data:
                        continue

                    # Extract control ID (simple parse)
                    try:
                        msg_text = data.decode(errors='ignore')
                        # Find MSH segment
                        start_idx = msg_text.find("MSH|")
                        if start_idx == -1: continue
                        
                        segments = msg_text[start_idx:].split('\r')
                        msh_fields = segments[0].split('|')
                        # MSH-10 is the Message Control ID
                        if len(msh_fields) >= 10:
                            control_id = msh_fields[9]
                        else:
                            control_id = "MSG001"
                    except:
                        control_id = "MSG001"
                    
                    print(f"Received message {control_id}, sending NACK...")
                    # Send NACK
                    conn.sendall(create_nack(control_id))
            except Exception as e:
                print(f"Connection error: {e}")

if __name__ == "__main__":
    start_server()
EOF

# Kill any existing instance and start the NACK server
pkill -f "nack_server.py" 2>/dev/null || true
nohup python3 /tmp/nack_server.py > /tmp/nack_server.log 2>&1 &
echo "Simulated LIS NACK Server started on port 6699"

# Create a sample ORM message
echo "Creating sample HL7 message..."
TIMESTAMP=$(date +"%Y%m%d%H%M%S")
cat > /home/ga/sample_orm.hl7 << EOF
MSH|^~\&|HIS|HOSPITAL|LIS|LAB|${TIMESTAMP}||ORM^O01|MSG${TIMESTAMP}|P|2.3
PID|1||12345^^^MRN||DOE^JOHN||19800101|M
ORC|NW|ORDER123|||||1^once^^^^|||||||||||||||||
OBR|1|ORDER123||BMP^Basic Metabolic Panel|||${TIMESTAMP}|||||||||DOC1^Doctor^One||||||||F
EOF

chown ga:ga /home/ga/sample_orm.hl7
chmod 644 /home/ga/sample_orm.hl7

# Clear any previous log file
rm -f /home/ga/lab_rejections.log

# Ensure NextGen Connect is ready
wait_for_api 60

# Record initial state
INITIAL_CHANNELS=$(get_channel_count)
echo "$INITIAL_CHANNELS" > /tmp/initial_channel_count.txt

# Open a terminal for the user
DISPLAY=:1 gnome-terminal --geometry=100x30+50+50 -- bash -c '
echo "=== NextGen Connect Task: Outbound NACK Handling ==="
echo ""
echo "Goal: Create channel \"Lab_Order_Sender\""
echo "  1. Source: TCP Listener (Port 6661)"
echo "  2. Destination: TCP Sender (localhost:6699)"
echo "  3. Response Transformer: Handle AE/AR responses"
echo "     - Set Status to ERROR"
echo "     - Log error text to /home/ga/lab_rejections.log"
echo ""
echo "Sample Data: /home/ga/sample_orm.hl7"
echo "API: https://localhost:8443/api (admin/admin)"
echo ""
exec bash
' 2>/dev/null &

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="