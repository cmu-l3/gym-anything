#!/bin/bash
set -e
echo "=== Setting up customize_columns_and_export_csv task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure target file exists
PCAP_FILE="/home/ga/Documents/captures/http.cap"
if [ ! -f "$PCAP_FILE" ]; then
    echo "ERROR: $PCAP_FILE not found!"
    exit 1
fi

# Reset Wireshark preferences to ensure default columns
# Default columns: No., Time, Source, Destination, Protocol, Length, Info
mkdir -p /home/ga/.config/wireshark
cat > /home/ga/.config/wireshark/preferences << 'EOF'
# Standard preferences
gui.update.enabled: FALSE
gui.ask_unsaved: FALSE
# Ensure default column format
gui.column.format: 
	"No.", "%m",
	"Time", "%t",
	"Source", "%s",
	"Destination", "%d",
	"Protocol", "%p",
	"Length", "%L",
	"Info", "%i"
EOF
chown -R ga:ga /home/ga/.config/wireshark

# Remove any previous output file
rm -f /home/ga/Documents/captures/http_activity_log.csv

# Open Wireshark with the capture file
echo "Starting Wireshark..."
su - ga -c "DISPLAY=:1 wireshark '$PCAP_FILE' > /dev/null 2>&1 &"

# Wait for Wireshark window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Wireshark"; then
        echo "Wireshark window detected"
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Wireshark" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="