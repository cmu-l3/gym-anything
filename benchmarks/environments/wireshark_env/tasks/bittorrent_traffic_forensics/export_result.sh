#!/bin/bash
set -e

echo "=== Exporting BitTorrent Forensics Result ==="

# 1. Capture Final Screenshot (Evidence of work)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gather User Output
REPORT_PATH="/home/ga/Documents/p2p_forensic_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_MTIME="0"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | base64 -w 0) # Base64 encode to handle special chars safely in JSON
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH")
fi

# 3. Compute Ground Truth (Dynamic extraction from the PCAP)
# We use tshark to extract the exact values from the file.
# This makes verification robust even if the pcap source changes slightly.
PCAP_PATH="/home/ga/Documents/captures/suspicious_activity.pcap"

# Extract Info Hash (first occurrence in handshake)
GT_INFO_HASH=$(tshark -r "$PCAP_PATH" -Y "bittorrent.info_hash" -T fields -e bittorrent.info_hash -c 1 2>/dev/null || echo "")

# Extract Peer ID (first occurrence)
GT_PEER_ID=$(tshark -r "$PCAP_PATH" -Y "bittorrent.peer_id" -T fields -e bittorrent.peer_id -c 1 2>/dev/null || echo "")

# Extract Client IP (Source IP of the handshake packet)
GT_CLIENT_IP=$(tshark -r "$PCAP_PATH" -Y "bittorrent.info_hash" -T fields -e ip.src -c 1 2>/dev/null || echo "")

# 4. Check Anti-Gaming Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_CREATED_DURING_TASK="false"
if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
    FILE_CREATED_DURING_TASK="true"
fi

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "report_exists": $REPORT_EXISTS,
    "report_content_base64": "$REPORT_CONTENT",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "ground_truth": {
        "info_hash": "$GT_INFO_HASH",
        "peer_id": "$GT_PEER_ID",
        "client_ip": "$GT_CLIENT_IP"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Move to final location (safe permission handling)
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"