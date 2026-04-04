#!/bin/bash
set -e

echo "=== Setting up RTP Audio Extraction Task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Create captures directory
mkdir -p /home/ga/Documents/captures

# 3. Download the specific VoIP sample data
TARGET_FILE="/home/ga/Documents/captures/sip-rtp-g711.pcap"
echo "Downloading sample capture to $TARGET_FILE..."

# Try multiple mirrors for reliability
download_success=0
urls=(
    "https://wiki.wireshark.org/uploads/__moin_import__/attachments/SampleCaptures/sip-rtp-g711.pcap"
    "https://gitlab.com/wireshark/wireshark/-/wikis/uploads/D4333674681347065963283626211470/sip-rtp-g711.pcap"
    "https://github.com/wireshark/wireshark/raw/master/test/captures/sip-rtp-g711.pcap"
)

for url in "${urls[@]}"; do
    if wget -q --timeout=20 -O "$TARGET_FILE" "$url"; then
        if [ -s "$TARGET_FILE" ]; then
            echo "Download successful from $url"
            download_success=1
            break
        fi
    fi
done

if [ $download_success -eq 0 ]; then
    echo "ERROR: Failed to download sip-rtp-g711.pcap from any source."
    # Create a dummy file if download fails so agent sees something (though task is effectively broken)
    # Ideally, we fail hard, but for stability we ensure file exists
    touch "$TARGET_FILE"
fi

# Set permissions
chown ga:ga "$TARGET_FILE"
chmod 644 "$TARGET_FILE"

# 4. Remove any previous output file to ensure clean state
rm -f /home/ga/Documents/captures/recovered_call.au
rm -f /home/ga/Documents/captures/recovered_call.raw

# 5. Start Wireshark
if ! pgrep -f "wireshark" > /dev/null; then
    echo "Starting Wireshark..."
    su - ga -c "DISPLAY=:1 wireshark &"
    sleep 5
fi

# 6. Window management
# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Wireshark"; then
        break
    fi
    sleep 1
done

# Maximize window (CRITICAL for agent visibility)
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Wireshark" 2>/dev/null || true

# 7. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="