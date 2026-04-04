#!/bin/bash
# Setup script for SMTP Forensic Analysis task
echo "=== Setting up SMTP Forensic Analysis ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

# Clean previous task state
rm -f /tmp/task_result.json /tmp/ground_truth_* /tmp/initial_* /tmp/task_start_*

PCAP="/home/ga/Documents/captures/smtp.pcap"

# Verify PCAP exists
if [ ! -f "$PCAP" ]; then
    echo "ERROR: $PCAP not found!"
    exit 1
fi

# Remove any previous output file (baseline: agent must create it fresh)
rm -f /home/ga/Documents/captures/smtp_forensic_report.txt

# --- Compute ground truth using tshark ---

# Sender email (MAIL FROM parameter)
GT_SENDER=$(tshark -r "$PCAP" -Y "smtp.req.command == \"MAIL\"" -T fields -e smtp.req.parameter 2>/dev/null | head -1 | tr -d '[:space:]')
echo "$GT_SENDER" > /tmp/ground_truth_smtp_sender

# Recipient email (RCPT TO parameter)
GT_RECIPIENT=$(tshark -r "$PCAP" -Y "smtp.req.command == \"RCPT\"" -T fields -e smtp.req.parameter 2>/dev/null | head -1 | tr -d '[:space:]')
echo "$GT_RECIPIENT" > /tmp/ground_truth_smtp_recipient

# Subject line — extract from the TCP stream
GT_SUBJECT=$(tshark -r "$PCAP" -q -z "follow,tcp,ascii,0" 2>/dev/null | grep -i "^Subject:" | head -1 | sed 's/^[Ss]ubject:[[:space:]]*//')
echo "$GT_SUBJECT" > /tmp/ground_truth_smtp_subject

# Server banner (220 greeting line)
GT_BANNER=$(tshark -r "$PCAP" -Y "smtp.response.code == 220" -T fields -e smtp.rsp.parameter 2>/dev/null | head -1)
echo "$GT_BANNER" > /tmp/ground_truth_smtp_banner

# Total SMTP packets
GT_SMTP_COUNT=$(tshark -r "$PCAP" -Y "smtp" 2>/dev/null | wc -l)
echo "$GT_SMTP_COUNT" > /tmp/ground_truth_smtp_count

# Record timestamp
date +%s > /tmp/task_start_timestamp

echo "Ground truth computed:"
echo "  Sender: $GT_SENDER"
echo "  Recipient: $GT_RECIPIENT"
echo "  Subject: $GT_SUBJECT"
echo "  Banner: $GT_BANNER"
echo "  SMTP packets: $GT_SMTP_COUNT"

# Launch Wireshark with the PCAP
pkill -f wireshark 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 wireshark '$PCAP' > /tmp/wireshark_task.log 2>&1 &"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
