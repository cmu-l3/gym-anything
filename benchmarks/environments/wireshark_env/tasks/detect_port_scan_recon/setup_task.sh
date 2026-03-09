#!/bin/bash
set -euo pipefail

echo "=== Setting up Port Scan Reconnaissance task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Install nmap for realistic traffic generation if not present
if ! command -v nmap &> /dev/null; then
    echo "Installing nmap..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -q && apt-get install -y -q nmap 2>/dev/null || true
fi

# Configuration
CAPTURE_DIR="/home/ga/Documents/captures"
CAPTURE_FILE="$CAPTURE_DIR/recon_investigation.pcapng"
mkdir -p "$CAPTURE_DIR"

# Clean up previous runs
rm -f "$CAPTURE_FILE" /home/ga/Documents/scan_forensic_report.txt 2>/dev/null || true
rm -f /tmp/ground_truth.json 2>/dev/null || true

# Set up virtual interfaces for realistic IPs
# We use loopback aliases to simulate distinct hosts
SCANNER_IP="192.168.50.10"
TARGET_IP="192.168.50.20"

ip addr add $SCANNER_IP/24 dev lo 2>/dev/null || true
ip addr add $TARGET_IP/24 dev lo 2>/dev/null || true

# Start services on Target to simulate OPEN ports
# We'll use python to listen on a few specific ports
echo "Starting target services..."
python3 -c "
import socket, threading, time, http.server, socketserver

# HTTP on 8080 (Background traffic target)
def run_http():
    handler = http.server.SimpleHTTPRequestHandler
    httpd = socketserver.TCPServer(('$TARGET_IP', 8080), handler)
    httpd.serve_forever()

# Dummy listeners for other open ports
def run_dummy(port):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('$TARGET_IP', port))
    s.listen(1)
    while True:
        try:
            conn, addr = s.accept()
            conn.close()
        except: break

threading.Thread(target=run_http, daemon=True).start()
for p in [22, 53, 443]:
    threading.Thread(target=run_dummy, args=(p,), daemon=True).start()

# Keep alive
while True: time.sleep(1)
" &
SERVICES_PID=$!
sleep 2

# Start packet capture
echo "Starting packet capture..."
# Capture on loopback, filter for our specific IPs
tcpdump -i lo -w "$CAPTURE_FILE" "host $SCANNER_IP or host $TARGET_IP" -s 0 &
TCPDUMP_PID=$!
sleep 2

# 1. Generate legitimate background traffic (HTTP)
echo "Generating background traffic..."
for i in {1..5}; do
    curl -s --interface "$SCANNER_IP" "http://$TARGET_IP:8080/" > /dev/null || true
    sleep 0.2
done

# 2. Generate Port Scan (SYN Scan)
echo "Executing SYN scan..."
# Scan range 1-100 plus the known open ports
# -sS = SYN scan, -P0 = treat hosts as online, -n = no DNS
# We scan specific range to keep packet count manageable but realistic
sudo nmap -sS -p 1-100,443,8080 -n -P0 -e lo -S "$SCANNER_IP" "$TARGET_IP" --max-retries 1 --min-rate 100 > /dev/null 2>&1 || true

sleep 1

# 3. More background traffic
for i in {1..3}; do
    curl -s --interface "$SCANNER_IP" "http://$TARGET_IP:8080/" > /dev/null || true
    sleep 0.2
done

# Stop capture and cleanup
sleep 2
kill "$TCPDUMP_PID" 2>/dev/null || true
kill "$SERVICES_PID" 2>/dev/null || true
wait "$TCPDUMP_PID" 2>/dev/null || true

# Set permissions
chown ga:ga "$CAPTURE_FILE"
chmod 644 "$CAPTURE_FILE"

# --- COMPUTE GROUND TRUTH ---
echo "Computing ground truth..."

# 1. Count unique ports probed (SYN packets from scanner)
TOTAL_PORTS=$(tshark -r "$CAPTURE_FILE" -Y "ip.src==$SCANNER_IP && tcp.flags.syn==1 && tcp.flags.ack==0" -T fields -e tcp.dstport 2>/dev/null | sort -u | wc -l)

# 2. Identify Open Ports (SYN-ACK from target)
OPEN_PORTS=$(tshark -r "$CAPTURE_FILE" -Y "ip.src==$TARGET_IP && tcp.flags.syn==1 && tcp.flags.ack==1" -T fields -e tcp.srcport 2>/dev/null | sort -n -u | tr '\n' ',' | sed 's/,$//')

# 3. Identify Closed Ports (RST from target in response to SYN)
# Note: Filter ensures we count RSTs sent by target
CLOSED_COUNT=$(tshark -r "$CAPTURE_FILE" -Y "ip.src==$TARGET_IP && tcp.flags.reset==1" -T fields -e tcp.srcport 2>/dev/null | sort -u | wc -l)

# Save ground truth to JSON
cat > /tmp/ground_truth.json << EOF
{
    "scanner_ip": "$SCANNER_IP",
    "target_ip": "$TARGET_IP",
    "scan_type": "SYN",
    "total_ports_probed": $TOTAL_PORTS,
    "open_ports": "$OPEN_PORTS",
    "closed_ports_count": $CLOSED_COUNT,
    "background_protocol": "HTTP"
}
EOF

echo "Ground Truth Generated:"
cat /tmp/ground_truth.json

# --- LAUNCH WIRESHARK ---
echo "Launching Wireshark..."
su - ga -c "DISPLAY=:1 wireshark '$CAPTURE_FILE' &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "wireshark"; then
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="