#!/bin/bash
set -e
echo "=== Setting up capinfos_forensic_profiling task ==="

# Source shared utilities if available
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure capture files exist
CAPTURES_DIR="/home/ga/Documents/captures"
REQUIRED_FILES=("http.cap" "dns.cap" "telnet-cooked.pcap" "200722_tcp_anon.pcapng" "smtp.pcap")
MISSING=0

echo "Verifying capture files..."
for f in "${REQUIRED_FILES[@]}"; do
    if [ ! -s "$CAPTURES_DIR/$f" ]; then
        echo "ERROR: Missing or empty capture file: $f"
        MISSING=$((MISSING + 1))
    else
        echo "  Found: $f ($(stat -c%s "$CAPTURES_DIR/$f") bytes)"
    fi
done

if [ "$MISSING" -gt 0 ]; then
    echo "WARNING: $MISSING capture files missing. Task may not work correctly."
fi

# Remove any previous report to ensure clean state
rm -f /home/ga/Documents/forensic_report.json 2>/dev/null || true

# Open a terminal window for the agent (Forensic Analyst persona)
echo "Opening terminal..."
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --maximize --working-directory=/home/ga/Documents/captures" 2>/dev/null || \
    su - ga -c "DISPLAY=:1 xterm -maximized -e 'cd /home/ga/Documents/captures; bash'" 2>/dev/null || true
    sleep 2
fi

# Ensure terminal is focused
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || \
DISPLAY=:1 wmctrl -a "xterm" 2>/dev/null || true

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="