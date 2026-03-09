#!/bin/bash
set -e

echo "=== Setting up follow_tcp_stream task ==="

# Clean up any leftover temp files from previous tasks
rm -f /tmp/initial_* /tmp/ground_truth_* /tmp/task_result.json /tmp/task_end.png 2>/dev/null || true

PCAP_FILE="/home/ga/Documents/captures/smtp.pcap"

if [ ! -s "$PCAP_FILE" ]; then
    echo "ERROR: SMTP PCAP file not found or empty at $PCAP_FILE"
    exit 1
fi

# Compute ground truth: extract TCP stream content using tshark
echo "Computing ground truth TCP stream..."
TOTAL_PACKETS=$(tshark -r "$PCAP_FILE" 2>/dev/null | wc -l)
SMTP_PACKETS=$(tshark -r "$PCAP_FILE" -Y "smtp" 2>/dev/null | wc -l)

# Extract the first TCP stream (stream index 0) content
tshark -r "$PCAP_FILE" -q -z "follow,tcp,ascii,0" 2>/dev/null > /tmp/ground_truth_stream.txt

# Check for SMTP keywords in the stream
HAS_EHLO=$(grep -ci "EHLO\|HELO" /tmp/ground_truth_stream.txt 2>/dev/null || echo "0")
HAS_MAIL_FROM=$(grep -ci "MAIL FROM" /tmp/ground_truth_stream.txt 2>/dev/null || echo "0")
HAS_RCPT_TO=$(grep -ci "RCPT TO" /tmp/ground_truth_stream.txt 2>/dev/null || echo "0")
HAS_DATA=$(grep -ci "^DATA" /tmp/ground_truth_stream.txt 2>/dev/null || echo "0")

echo "$TOTAL_PACKETS" > /tmp/initial_total_packets
echo "$SMTP_PACKETS" > /tmp/initial_smtp_packets

echo "Ground truth: $TOTAL_PACKETS total packets, $SMTP_PACKETS SMTP packets"
echo "SMTP indicators: EHLO=$HAS_EHLO, MAIL_FROM=$HAS_MAIL_FROM, RCPT_TO=$HAS_RCPT_TO, DATA=$HAS_DATA"

# Store SMTP keyword presence
cat > /tmp/ground_truth_smtp_markers.json << EOF
{
    "has_ehlo": $([ "$HAS_EHLO" -gt 0 ] && echo "true" || echo "false"),
    "has_mail_from": $([ "$HAS_MAIL_FROM" -gt 0 ] && echo "true" || echo "false"),
    "has_rcpt_to": $([ "$HAS_RCPT_TO" -gt 0 ] && echo "true" || echo "false"),
    "has_data": $([ "$HAS_DATA" -gt 0 ] && echo "true" || echo "false")
}
EOF

# Remove any previous output
rm -f /home/ga/Documents/captures/smtp_stream.txt 2>/dev/null || true

# Open Wireshark with the SMTP capture
echo "Opening Wireshark with smtp.pcap..."
su - ga -c "DISPLAY=:1 wireshark /home/ga/Documents/captures/smtp.pcap > /tmp/wireshark_task.log 2>&1 &"

sleep 5

echo "=== Task setup complete ==="
