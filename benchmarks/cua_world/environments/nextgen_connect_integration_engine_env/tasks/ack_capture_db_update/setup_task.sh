#!/bin/bash
echo "=== Setting up ACK Capture Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Start Lab Simulator (Python script)
echo "Starting Lab Simulator..."
cat > /home/ga/lab_simulator.py << 'EOF'
import socket
import time
import sys
import signal

HOST = '0.0.0.0'
PORT = 6670

def create_ack(msg_data):
    try:
        msg_str = msg_data.decode('utf-8', errors='ignore')
        # Find MSH segment
        msh = ""
        for line in msg_str.split('\r'):
            if line.startswith('MSH'):
                msh = line
                break
        
        if not msh:
            return None
            
        fields = msh.split('|')
        # MSH-10 is at index 9 (0-based)
        if len(fields) < 10:
            return None
            
        msg_control_id = fields[9]
        
        # Generate ACK with Reference ID in MSA-3
        lab_ref = f"LAB-REF-{msg_control_id}"
        timestamp = time.strftime("%Y%m%d%H%M%S")
        
        # Construct ACK message
        ack = f"MSH|^~\\&|LAB_SIM|LAB|SENDER|FACILITY|{timestamp}||ACK|ACK{msg_control_id}|P|2.3\r"
        ack += f"MSA|AA|{msg_control_id}|{lab_ref}\r"
        
        return b'\x0b' + ack.encode('utf-8') + b'\x1c\x0d'
    except Exception as e:
        print(f"Error creating ACK: {e}")
        return None

def run_server():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        server.bind((HOST, PORT))
        server.listen(5)
        print(f"Lab Simulator listening on {PORT}")
    except Exception as e:
        print(f"Failed to bind: {e}")
        return

    while True:
        try:
            client, addr = server.accept()
            data = client.recv(4096)
            if data:
                response = create_ack(data)
                if response:
                    client.sendall(response)
            client.close()
        except Exception as e:
            print(f"Connection error: {e}")

if __name__ == '__main__':
    run_server()
EOF

# Kill any existing simulator and start new one
pkill -f lab_simulator.py || true
nohup python3 /home/ga/lab_simulator.py > /tmp/lab_sim.log 2>&1 &
echo $! > /tmp/lab_sim.pid

# 2. Setup Database
echo "Setting up Database table..."
# Wait for postgres to be ready if needed (usually handled by env setup)
docker exec nextgen-postgres psql -U postgres -d mirthdb -c "
DROP TABLE IF EXISTS lab_orders;
CREATE TABLE lab_orders (
    order_control_id VARCHAR(50) PRIMARY KEY,
    patient_name VARCHAR(100),
    lab_reference_number VARCHAR(100),
    status VARCHAR(20) DEFAULT 'NEW'
);
INSERT INTO lab_orders (order_control_id, patient_name) VALUES ('ORD-001', 'Doe^John');
INSERT INTO lab_orders (order_control_id, patient_name) VALUES ('ORD-002', 'Smith^Jane');
"

# 3. Create Sample Data
echo "Creating sample HL7 file..."
mkdir -p /home/ga/assets
# Create raw file first
cat > /home/ga/assets/sample_order.raw << 'EOF'
MSH|^~\&|HIS|HOSPITAL|LAB|QUEST|202403151000||ORM^O01|ORD-001|P|2.3
PID|1||12345^^^MRN||Doe^John||19800101|M
ORC|NW|ORD-001|||||1^once^^^^202403151000|||123^Dr^Smith
OBR|1|ORD-001||CMP^Comprehensive Metabolic Panel
EOF

# Convert to HL7 format (CR delimiters)
sed 's/$/\r/' /home/ga/assets/sample_order.raw | tr -d '\n' > /home/ga/assets/sample_order.hl7
chown ga:ga /home/ga/assets/sample_order.hl7

# 4. Open Terminal with Instructions
DISPLAY=:1 gnome-terminal --geometry=120x35+70+30 -- bash -c '
echo "============================================"
echo " NextGen Connect - ACK Capture & DB Update"
echo "============================================"
echo ""
echo "GOAL: Forward orders to Lab Simulator, capture ACK Reference ID,"
echo "      and update the local database."
echo ""
echo "Source: TCP Listener on Port 6661"
echo "Destination 1: TCP Sender to localhost:6670 (Lab Simulator)"
echo "   -> Simulator returns ACK with Reference ID in MSA-3"
echo "Destination 2: Database Writer (update lab_orders table)"
echo ""
echo "Sample HL7 File: /home/ga/assets/sample_order.hl7"
echo "   (Control ID: ORD-001)"
echo ""
echo "Database Info (Internal Docker Network):"
echo "   URL: jdbc:postgresql://nextgen-postgres:5432/mirthdb"
echo "   User/Pass: postgres / postgres"
echo "   Table: lab_orders (update col: lab_reference_number)"
echo ""
echo "============================================"
echo ""
exec bash
' 2>/dev/null &

# Record start time
date +%s > /tmp/task_start_time.txt
# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="