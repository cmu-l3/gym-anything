#!/bin/bash
set -e

echo "=== Setting up configure_name_resolution_forensics task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

PCAP_FILE="/home/ga/Documents/captures/smtp.pcap"

# Verify PCAP exists
if [ ! -s "$PCAP_FILE" ]; then
    echo "ERROR: SMTP PCAP file not found at $PCAP_FILE"
    exit 1
fi

# Clean up previous run artifacts
rm -f /home/ga/Documents/captures/smtp_resolved.txt
# Back up existing hosts file if it exists, or ensure directory exists
mkdir -p /home/ga/.config/wireshark
if [ -f /home/ga/.config/wireshark/hosts ]; then
    mv /home/ga/.config/wireshark/hosts /home/ga/.config/wireshark/hosts.bak
fi
# Create empty hosts file to ensure clean state
echo "# Wireshark hosts file" > /home/ga/.config/wireshark/hosts
chown -R ga:ga /home/ga/.config/wireshark

# ------------------------------------------------------------------
# CALCULATE GROUND TRUTH
# ------------------------------------------------------------------
# We need to know which IP is the client and which is the server.
# Server sends 220 Service Ready.
SERVER_IP=$(tshark -r "$PCAP_FILE" -Y "smtp.response.code == 220" -T fields -e ip.src -c 1 2>/dev/null)

# Client sends EHLO or HELO.
CLIENT_IP=$(tshark -r "$PCAP_FILE" -Y "smtp.req.command == 'EHLO' || smtp.req.command == 'HELO'" -T fields -e ip.src -c 1 2>/dev/null)

# Save ground truth for the verifier (hidden from agent)
cat > /tmp/ground_truth_ips.json << EOF
{
    "server_ip": "$SERVER_IP",
    "client_ip": "$CLIENT_IP"
}
EOF

echo "Ground Truth Calculated: Server=$SERVER_IP, Client=$CLIENT_IP"

# ------------------------------------------------------------------
# START WIRESHARK
# ------------------------------------------------------------------
echo "Starting Wireshark..."
if ! pgrep -f "wireshark" > /dev/null; then
    su - ga -c "DISPLAY=:1 wireshark $PCAP_FILE > /dev/null 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "wireshark" > /dev/null; then
            break
        fi
        sleep 1
    done
fi

# Maximize window
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Wireshark" 2>/dev/null || true

# Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="