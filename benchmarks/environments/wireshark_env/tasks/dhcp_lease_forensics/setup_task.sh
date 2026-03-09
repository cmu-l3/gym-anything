#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up DHCP Lease Forensics task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up previous runs
rm -rf /var/lib/wireshark_ground_truth
rm -f /home/ga/Documents/captures/dhcp_analysis_report.txt

# Ensure capture directory exists
mkdir -p /home/ga/Documents/captures

# Download DHCP sample capture
DHCP_PCAP="/home/ga/Documents/captures/dhcp.pcap"
echo "Downloading DHCP sample capture..."

# Try official sources
wget -q --timeout=30 -O "$DHCP_PCAP" \
    "https://wiki.wireshark.org/uploads/__moin_import__/attachments/SampleCaptures/dhcp.pcap" 2>/dev/null || \
wget -q --timeout=30 -O "$DHCP_PCAP" \
    "https://gitlab.com/wireshark/wireshark/-/wikis/uploads/__moin_import__/attachments/SampleCaptures/dhcp.pcap" 2>/dev/null

# Validate download
if [ ! -s "$DHCP_PCAP" ]; then
    echo "ERROR: Failed to download dhcp.pcap"
    # Fallback to creating a dummy file if network fails (prevent crash, but task will be broken)
    # In a real env, we'd expect the network to work or the file to be pre-baked.
    exit 1
fi

chown ga:ga "$DHCP_PCAP"
chmod 644 "$DHCP_PCAP"

# ------------------------------------------------------------------
# GENERATE GROUND TRUTH (Hidden from agent)
# ------------------------------------------------------------------
GT_DIR="/var/lib/wireshark_ground_truth"
mkdir -p "$GT_DIR"

echo "Generating ground truth..."

# 1. Total DHCP packets
tshark -r "$DHCP_PCAP" -Y "dhcp || bootp" 2>/dev/null | wc -l > "$GT_DIR/total_packets.txt"

# 2. Transaction IDs (hex)
tshark -r "$DHCP_PCAP" -Y "dhcp || bootp" -T fields -e dhcp.id 2>/dev/null | sort -u > "$GT_DIR/transaction_ids.txt"

# 3. Client MAC Addresses
tshark -r "$DHCP_PCAP" -Y "dhcp || bootp" -T fields -e dhcp.hw.mac_addr 2>/dev/null | sort -u > "$GT_DIR/client_macs.txt"

# 4. Assigned IPs (yiaddr from Offers/Acks)
# We look at field 'dhcp.ip.your' (Your (Client) IP address)
tshark -r "$DHCP_PCAP" -Y "dhcp || bootp" -T fields -e dhcp.ip.your 2>/dev/null | sort -u | grep -v "0.0.0.0" | grep -v "^$" > "$GT_DIR/assigned_ips.txt" || true

# 5. DHCP Server IPs (Option 54)
tshark -r "$DHCP_PCAP" -Y "dhcp || bootp" -T fields -e dhcp.option.dhcp_server_id 2>/dev/null | sort -u | grep -v "^$" > "$GT_DIR/server_ips.txt" || true

# 6. Options (Subnet, Router, DNS) - just getting unique values present
tshark -r "$DHCP_PCAP" -Y "dhcp || bootp" -T fields -e dhcp.option.subnet_mask 2>/dev/null | sort -u | grep -v "^$" > "$GT_DIR/subnet_masks.txt" || true
tshark -r "$DHCP_PCAP" -Y "dhcp || bootp" -T fields -e dhcp.option.router 2>/dev/null | sort -u | grep -v "^$" > "$GT_DIR/routers.txt" || true
tshark -r "$DHCP_PCAP" -Y "dhcp || bootp" -T fields -e dhcp.option.domain_name_server 2>/dev/null | sort -u | grep -v "^$" > "$GT_DIR/dns_servers.txt" || true

# Secure the ground truth
chmod -R 700 "$GT_DIR"
chown -R root:root "$GT_DIR"

# ------------------------------------------------------------------
# LAUNCH WIRESHARK
# ------------------------------------------------------------------
echo "Launching Wireshark..."
su - ga -c "DISPLAY=:1 wireshark '$DHCP_PCAP' &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Wireshark"; then
        echo "Wireshark started."
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="