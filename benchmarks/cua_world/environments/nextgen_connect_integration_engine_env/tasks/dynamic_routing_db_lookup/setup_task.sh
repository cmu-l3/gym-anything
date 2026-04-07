#!/bin/bash
echo "=== Setting up dynamic_routing_db_lookup task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Setup Database Table
echo "Setting up 'clinic_routes' table in PostgreSQL..."
docker exec nextgen-postgres psql -U postgres -d mirthdb -c "
DROP TABLE IF EXISTS clinic_routes;
CREATE TABLE clinic_routes (
    facility_id VARCHAR(50) PRIMARY KEY,
    host VARCHAR(100),
    port INT
);
INSERT INTO clinic_routes (facility_id, host, port) VALUES ('CLINIC_A', 'localhost', 6671);
INSERT INTO clinic_routes (facility_id, host, port) VALUES ('CLINIC_B', 'localhost', 6672);
" 2>/dev/null

# 2. Start Dummy TCP Listeners (Simulated Clinics)
# Create a python script to act as the destination servers
cat > /tmp/clinic_simulators.py << 'EOF'
import socket
import threading
import time
import sys

def run_server(name, port, logfile):
    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        server_socket.bind(('0.0.0.0', port))
        server_socket.listen(5)
        print(f"{name} listening on {port}")
        
        # Write header to log
        with open(logfile, 'w') as f:
            f.write(f"--- {name} Log Started ---\n")
            
        while True:
            try:
                client_socket, addr = server_socket.accept()
                data = client_socket.recv(8192)
                if data:
                    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
                    msg = data.decode('utf-8', errors='ignore')
                    with open(logfile, 'a') as f:
                        f.write(f"[{timestamp}] RECEIVED: {msg}\n")
                client_socket.close()
            except Exception as e:
                print(f"Connection error in {name}: {e}")
                
    except Exception as e:
        print(f"Failed to start {name}: {e}")

if __name__ == "__main__":
    # Start listeners in background threads
    t1 = threading.Thread(target=run_server, args=("CLINIC_A", 6671, "/tmp/received_6671.log"))
    t2 = threading.Thread(target=run_server, args=("CLINIC_B", 6672, "/tmp/received_6672.log"))
    
    t1.daemon = True
    t2.daemon = True
    
    t1.start()
    t2.start()
    
    # Keep main thread alive
    while True:
        time.sleep(1)
EOF

# Kill any existing instances and start the simulators
pkill -f "clinic_simulators.py" 2>/dev/null || true
nohup python3 /tmp/clinic_simulators.py > /tmp/simulators.log 2>&1 &
echo "Started Clinic Simulators on ports 6671 and 6672"

# 3. Create Sample Messages
cat > /home/ga/msg_clinic_a.hl7 << 'EOF'
MSH|^~\&|LAB|REF_LAB|EHR|CLINIC_A|202501011000||ORU^R01|MSG001|P|2.3
PID|1||12345^^^MR||DOE^JOHN||19800101|M
OBX|1|NM|GLU^Glucose||105|mg/dL|70-100|H||F
EOF

cat > /home/ga/msg_clinic_b.hl7 << 'EOF'
MSH|^~\&|LAB|REF_LAB|EHR|CLINIC_B|202501011005||ORU^R01|MSG002|P|2.3
PID|1||67890^^^MR||SMITH^JANE||19850505|F
OBX|1|NM|GLU^Glucose||95|mg/dL|70-100|N||F
EOF

chown ga:ga /home/ga/msg_clinic_a.hl7 /home/ga/msg_clinic_b.hl7
chmod 644 /home/ga/msg_clinic_a.hl7 /home/ga/msg_clinic_b.hl7

# 4. Record Initial State
INITIAL_CHANNEL_COUNT=$(get_channel_count)
echo "$INITIAL_CHANNEL_COUNT" > /tmp/initial_channel_count.txt
date +%s > /tmp/task_start_time.txt

# 5. Open Terminal for Agent
DISPLAY=:1 gnome-terminal --geometry=100x30+50+50 -- bash -c '
echo "======================================================="
echo " NextGen Connect - Dynamic Routing Task"
echo "======================================================="
echo "GOAL: Route messages dynamically based on Database Lookup"
echo ""
echo "1. Create Channel: 'Dynamic_Clinic_Router'"
echo "2. Source: TCP Listener on port 6661"
echo "3. Routing Logic: "
echo "   - Read MSH-6 (Receiving Facility)"
echo "   - Query DB table 'clinic_routes' for host/port"
echo "   - Send to that host/port"
echo ""
echo "Database Connection:"
echo "   jdbc:postgresql://nextgen-postgres:5432/mirthdb"
echo "   User: postgres, Pass: postgres"
echo ""
echo "Sample Messages:"
echo "   /home/ga/msg_clinic_a.hl7 (Target: CLINIC_A -> 6671)"
echo "   /home/ga/msg_clinic_b.hl7 (Target: CLINIC_B -> 6672)"
echo ""
echo "Tools: curl, nc, python3"
echo "======================================================="
exec bash
' 2>/dev/null &

sleep 2
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

echo "=== Task setup complete ==="