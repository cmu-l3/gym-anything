#!/bin/bash
set -e

echo "=== Setting up VoIP Call Quality Analysis task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean previous artifacts
rm -f /home/ga/Documents/voip_report.txt 2>/dev/null || true
rm -f /tmp/voip_ground_truth.json 2>/dev/null || true

# Prepare PCAP file
PCAP_DIR="/home/ga/Documents/captures"
VOIP_FILE="$PCAP_DIR/SIP_CALL_RTP_G711"
mkdir -p "$PCAP_DIR"

if [ ! -s "$VOIP_FILE" ]; then
    echo "Downloading VoIP sample capture..."
    # Try multiple mirrors
    wget -q --timeout=30 -O "$VOIP_FILE" \
        "https://wiki.wireshark.org/uploads/__moin_import__/attachments/SampleCaptures/SIP_CALL_RTP_G711" 2>/dev/null || \
    wget -q --timeout=30 -O "$VOIP_FILE" \
        "https://gitlab.com/wireshark/wireshark/-/wikis/uploads/__moin_import__/attachments/SampleCaptures/SIP_CALL_RTP_G711" 2>/dev/null || true
fi

if [ ! -s "$VOIP_FILE" ]; then
    echo "ERROR: Failed to download VoIP capture file"
    exit 1
fi

chmod 644 "$VOIP_FILE"

# --- COMPUTE GROUND TRUTH ---
echo "Computing ground truth..."

# 1. SIP Packet Count
GT_SIP_COUNT=$(tshark -r "$VOIP_FILE" -Y "sip" 2>/dev/null | wc -l)

# 2. RTP Packet Count
GT_RTP_COUNT=$(tshark -r "$VOIP_FILE" -Y "rtp" 2>/dev/null | wc -l)

# 3. SIP Methods (sorted, comma separated)
GT_SIP_METHODS=$(tshark -r "$VOIP_FILE" -Y "sip.Request-Line" -T fields -e sip.Method 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//')

# 4. Caller (From User in first INVITE)
GT_CALLER=$(tshark -r "$VOIP_FILE" -Y "sip.Method == INVITE" -T fields -e sip.from.user 2>/dev/null | head -1)

# 5. Callee (To User in first INVITE)
GT_CALLEE=$(tshark -r "$VOIP_FILE" -Y "sip.Method == INVITE" -T fields -e sip.to.user 2>/dev/null | head -1)

# 6. Codec (Try SDP first, then RTP payload type)
# Look for SDP media format (e.g., PCMU/8000)
GT_CODEC=$(tshark -r "$VOIP_FILE" -Y "sdp.media.media == audio" -T fields -e sdp.media.format 2>/dev/null | head -1)
# If numeric (payload type), try to map it or just use payload type
if [[ "$GT_CODEC" =~ ^[0-9]+$ ]]; then
    PT="$GT_CODEC"
    if [ "$PT" -eq 0 ]; then GT_CODEC="PCMU (G.711u)";
    elif [ "$PT" -eq 8 ]; then GT_CODEC="PCMA (G.711a)";
    elif [ "$PT" -eq 18 ]; then GT_CODEC="G.729";
    else GT_CODEC="Payload Type $PT"; fi
fi
# Fallback: check RTP payload type directly
if [ -z "$GT_CODEC" ]; then
    PT=$(tshark -r "$VOIP_FILE" -Y "rtp" -T fields -e rtp.p_type 2>/dev/null | head -1)
    GT_CODEC="Payload Type $PT"
fi

# 7. Number of RTP Streams
# Use tshark statistics
GT_RTP_STREAMS=$(tshark -r "$VOIP_FILE" -q -z rtp,streams 2>/dev/null | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | wc -l)

# 8. SIP Response Codes
GT_RESPONSE_CODES=$(tshark -r "$VOIP_FILE" -Y "sip.Status-Line" -T fields -e sip.Status-Code 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//')

# Save Ground Truth to JSON using Python for safety
cat << EOF > /tmp/gt_gen.py
import json
data = {
    "sip_count": $GT_SIP_COUNT,
    "rtp_count": $GT_RTP_COUNT,
    "sip_methods": "$GT_SIP_METHODS",
    "caller": "$GT_CALLER",
    "callee": "$GT_CALLEE",
    "codec": "$GT_CODEC",
    "rtp_streams": $GT_RTP_STREAMS,
    "response_codes": "$GT_RESPONSE_CODES"
}
with open('/tmp/voip_ground_truth.json', 'w') as f:
    json.dump(data, f)
EOF
python3 /tmp/gt_gen.py
rm -f /tmp/gt_gen.py

echo "Ground truth computed:"
cat /tmp/voip_ground_truth.json

# --- LAUNCH WIRESHARK ---
echo "Launching Wireshark..."
# Kill any existing instances
pkill -f wireshark 2>/dev/null || true

# Launch with file
su - ga -c "DISPLAY=:1 wireshark '$VOIP_FILE' > /dev/null 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Wireshark"; then
        echo "Wireshark window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Wireshark" 2>/dev/null || true

# Dismiss "Software Update" or other dialogs if they appear
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="