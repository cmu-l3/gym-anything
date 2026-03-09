#!/bin/bash
set -e

echo "=== Setting up BitTorrent Forensics Task ==="

# 1. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Prepare Data
# We use the standard BitTorrent sample from Wireshark wiki
SOURCE_URL="https://wiki.wireshark.org/uploads/__moin_import__/attachments/SampleCaptures/BITTORRENT.pcap"
DEST_DIR="/home/ga/Documents/captures"
TARGET_FILE="$DEST_DIR/suspicious_activity.pcap"

mkdir -p "$DEST_DIR"

# Check if we need to download (reuse if exists from env setup to save bandwidth)
# We look for the standard name first, then download if missing
if [ -f "$DEST_DIR/BITTORRENT.pcap" ]; then
    echo "Using existing BITTORRENT.pcap..."
    cp "$DEST_DIR/BITTORRENT.pcap" "$TARGET_FILE"
else
    echo "Downloading BitTorrent sample capture..."
    wget -q -O "$TARGET_FILE" "$SOURCE_URL" || \
    wget -q -O "$TARGET_FILE" "https://gitlab.com/wireshark/wireshark/-/wikis/uploads/SampleCaptures/BITTORRENT.pcap"
fi

# Ensure permissions
chown ga:ga "$TARGET_FILE"
chmod 644 "$TARGET_FILE"

# 3. Clean previous artifacts
rm -f /home/ga/Documents/p2p_forensic_report.txt
rm -f /tmp/task_result.json

# 4. Start Wireshark (Maximized, no file loaded initially to force agent to open it)
echo "Starting Wireshark..."
if ! pgrep -f "wireshark" > /dev/null; then
    su - ga -c "DISPLAY=:1 wireshark &"
    sleep 5
fi

# Wait for window
for i in {1..10}; do
    if DISPLAY=:1 wmctrl -l | grep -i "wireshark"; then
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Wireshark" 2>/dev/null || true

# 5. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="