#!/bin/bash
set -e

echo "=== Setting up configure_coloring_rules task ==="

# 1. Clean up previous run artifacts
rm -f /home/ga/Documents/rst_frame_number.txt
rm -f /home/ga/Documents/colored_packets.png
rm -f /tmp/task_result.json
rm -f /tmp/ground_truth_*

# 2. Reset Wireshark coloring rules to default/empty to ensure a clean start
# We back up existing if needed, but for the task env we usually want a clean slate
mkdir -p /home/ga/.config/wireshark
# Create a basic default coloring rules file or empty one
cat > /home/ga/.config/wireshark/coloringrules << EOF
# Coloring Rules
EOF
chown -R ga:ga /home/ga/.config/wireshark

# 3. Calculate Ground Truth using tshark
# Find the frame number of the first packet where tcp.flags.reset == 1
PCAP_FILE="/home/ga/Documents/captures/200722_tcp_anon.pcapng"

if [ ! -f "$PCAP_FILE" ]; then
    echo "ERROR: PCAP file not found at $PCAP_FILE"
    exit 1
fi

FIRST_RST_FRAME=$(tshark -r "$PCAP_FILE" -Y "tcp.flags.reset == 1" -T fields -e frame.number -c 1 2>/dev/null)
echo "$FIRST_RST_FRAME" > /tmp/ground_truth_rst_frame.txt
echo "Ground Truth: First RST packet is frame #$FIRST_RST_FRAME"

# 4. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 5. Launch Wireshark
# We launch it so the agent sees it immediately, but the agent might close/reopen it
echo "Launching Wireshark..."
su - ga -c "DISPLAY=:1 wireshark '$PCAP_FILE' > /dev/null 2>&1 &"

# Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Wireshark"; then
        echo "Wireshark window found."
        DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# 6. Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="