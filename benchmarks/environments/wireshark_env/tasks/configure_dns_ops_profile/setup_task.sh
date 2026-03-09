#!/bin/bash
set -e
echo "=== Setting up Configure DNS Ops Profile task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure clean state: Remove DNS_Ops profile if it exists from previous runs
PROFILE_DIR="/home/ga/.config/wireshark/profiles/DNS_Ops"
if [ -d "$PROFILE_DIR" ]; then
    echo "Removing stale DNS_Ops profile..."
    rm -rf "$PROFILE_DIR"
fi

# Remove stale screenshot
rm -f /home/ga/Documents/dns_ops_view.png 2>/dev/null || true

# Ensure Wireshark config dir exists
mkdir -p /home/ga/.config/wireshark/profiles

# Open Wireshark with dns.cap
# We open it in the default profile first
PCAP_FILE="/home/ga/Documents/captures/dns.cap"

if [ ! -f "$PCAP_FILE" ]; then
    echo "ERROR: PCAP file not found: $PCAP_FILE"
    exit 1
fi

echo "Starting Wireshark..."
if ! pgrep -f "wireshark" > /dev/null; then
    su - ga -c "DISPLAY=:1 wireshark '$PCAP_FILE' > /dev/null 2>&1 &"
    sleep 5
fi

# Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Wireshark"; then
        echo "Wireshark window detected"
        DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="