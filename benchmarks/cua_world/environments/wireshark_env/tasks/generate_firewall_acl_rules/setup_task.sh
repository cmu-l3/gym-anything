#!/bin/bash
set -e

echo "=== Setting up Firewall ACL Rules task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Prepare Environment
PCAP_PATH="/home/ga/Documents/captures/smtp.pcap"

# Verify PCAP exists
if [ ! -f "$PCAP_PATH" ]; then
    echo "ERROR: $PCAP_PATH not found."
    exit 1
fi

# 2. Cleanup previous artifacts
rm -f /home/ga/Documents/cisco_block_rule.txt
rm -f /home/ga/Documents/iptables_block_rule.txt
rm -f /tmp/task_result.json

# 3. Establish Ground Truth
# The Client IP is the one sending HELO or EHLO
# We extract the source IP of the first HELO/EHLO packet
GROUND_TRUTH_IP=$(tshark -r "$PCAP_PATH" -Y "smtp.req.command == 'HELO' || smtp.req.command == 'EHLO'" -T fields -e ip.src | head -1)

if [ -z "$GROUND_TRUTH_IP" ]; then
    # Fallback: Sender of first TCP SYN (Client initiates connection)
    GROUND_TRUTH_IP=$(tshark -r "$PCAP_PATH" -Y "tcp.flags.syn==1 && tcp.flags.ack==0" -T fields -e ip.src | head -1)
fi

echo "Ground Truth Client IP: $GROUND_TRUTH_IP"
echo "$GROUND_TRUTH_IP" > /tmp/ground_truth_ip.txt

# 4. Start Wireshark
echo "Starting Wireshark..."
su - ga -c "DISPLAY=:1 wireshark '$PCAP_PATH' > /dev/null 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Wireshark"; then
        echo "Wireshark window detected."
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Wireshark" 2>/dev/null || true

# 5. Record Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 6. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="