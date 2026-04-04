#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up SMTP Email Forensics task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

PCAP_FILE="/home/ga/Documents/captures/smtp.pcap"
GROUND_TRUTH_DIR="/tmp/.smtp_ground_truth"

# Verify smtp.pcap exists
if [ ! -s "$PCAP_FILE" ]; then
    echo "ERROR: smtp.pcap is missing or empty!"
    exit 1
fi

# Remove any previous report file (clean state)
rm -f /home/ga/Documents/smtp_report.txt 2>/dev/null || true
rm -rf "$GROUND_TRUTH_DIR" 2>/dev/null || true
mkdir -p "$GROUND_TRUTH_DIR"

# ---- Compute ground truth values using tshark (Hidden from agent) ----
echo "Computing ground truth..."

# 1. Total packets
TOTAL_PACKETS=$(tshark -r "$PCAP_FILE" 2>/dev/null | wc -l)
echo "$TOTAL_PACKETS" > "$GROUND_TRUTH_DIR/total_packets"

# 2. SMTP packets
SMTP_PACKETS=$(tshark -r "$PCAP_FILE" -Y "smtp" 2>/dev/null | wc -l)
echo "$SMTP_PACKETS" > "$GROUND_TRUTH_DIR/smtp_packets"

# 3. Sender (MAIL FROM)
# Extract parameter, clean it up (remove 'FROM:', '<', '>', whitespace)
SENDER_RAW=$(tshark -r "$PCAP_FILE" -Y "smtp.req.command == \"MAIL\"" -T fields -e smtp.req.parameter 2>/dev/null | head -1)
SENDER=$(echo "$SENDER_RAW" | sed 's/FROM://gi; s/[<>]//g; s/^[[:space:]]*//; s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')
echo "$SENDER" > "$GROUND_TRUTH_DIR/sender"

# 4. Recipient (RCPT TO)
RCPT_RAW=$(tshark -r "$PCAP_FILE" -Y "smtp.req.command == \"RCPT\"" -T fields -e smtp.req.parameter 2>/dev/null | head -1)
RECIPIENT=$(echo "$RCPT_RAW" | sed 's/TO://gi; s/[<>]//g; s/^[[:space:]]*//; s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')
echo "$RECIPIENT" > "$GROUND_TRUTH_DIR/recipient"

# 5. SMTP Server IP (Sends 220 greeting)
SERVER_IP=$(tshark -r "$PCAP_FILE" -Y "smtp.response.code == 220" -T fields -e ip.src 2>/dev/null | head -1)
echo "$SERVER_IP" > "$GROUND_TRUTH_DIR/smtp_server_ip"

# 6. SMTP Client IP (Receives 220 greeting / Sends EHLO)
CLIENT_IP=$(tshark -r "$PCAP_FILE" -Y "smtp.response.code == 220" -T fields -e ip.dst 2>/dev/null | head -1)
echo "$CLIENT_IP" > "$GROUND_TRUTH_DIR/smtp_client_ip"

# Debug output to log (not visible to agent during normal run)
echo "Ground Truth Calculated:"
grep "" "$GROUND_TRUTH_DIR"/*

# ---- Launch Wireshark ----
# Kill any existing Wireshark instances
pkill -f wireshark 2>/dev/null || true
sleep 1

echo "Launching Wireshark..."
su - ga -c "DISPLAY=:1 wireshark '$PCAP_FILE' > /dev/null 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "wireshark"; then
        echo "Wireshark started."
        break
    fi
    sleep 1
done
sleep 2

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss any startup dialogs (like software update or lua error)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="