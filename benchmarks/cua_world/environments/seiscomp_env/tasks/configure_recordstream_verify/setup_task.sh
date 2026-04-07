#!/bin/bash
echo "=== Setting up configure_recordstream_verify task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Ensure services are running
systemctl start mariadb 2>/dev/null || true
ensure_scmaster_running

# 2. Ensure clean state for the task
GLOBAL_CFG="$SEISCOMP_ROOT/etc/global.cfg"

# Remove existing recordstream line if present
if grep -qi "^recordstream" "$GLOBAL_CFG" 2>/dev/null; then
    sed -i '/^recordstream/I d' "$GLOBAL_CFG"
    echo "Removed existing recordstream line from global.cfg"
fi

# Record initial mtime of global.cfg
stat -c %Y "$GLOBAL_CFG" > /tmp/initial_cfg_mtime.txt 2>/dev/null || echo "0" > /tmp/initial_cfg_mtime.txt

# Ensure output files do not exist yet
rm -f /home/ga/inventory_listing.txt
rm -f /home/ga/extracted_waveforms.mseed

# Verify SDS archive contains data (so the task is possible)
SDS_ROOT="$SEISCOMP_ROOT/var/lib/archive"
SDS_FILE_COUNT=$(find "$SDS_ROOT" -name "*.D.*" -type f 2>/dev/null | wc -l)
if [ "$SDS_FILE_COUNT" -eq 0 ]; then
    echo "ERROR: No waveform files in SDS archive! Task cannot proceed."
    exit 1
fi
echo "SDS archive confirmed with $SDS_FILE_COUNT files."

# 3. Prepare the workspace for the user
# Kill any existing terminal to start fresh
killall gnome-terminal-server 2>/dev/null || true
sleep 1

# Launch maximized terminal as user 'ga'
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority gnome-terminal --maximize -- bash -c 'echo \"=== SeisComP Environment Ready ===\"; echo \"SEISCOMP_ROOT=\$SEISCOMP_ROOT\"; echo \"\"; echo \"Task: Configure recordstream, verify inventory, extract waveforms.\"; echo \"You can begin your work here.\"; echo \"\"; exec bash'" &

# Wait for terminal window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Terminal"; then
        echo "Terminal window detected"
        break
    fi
    sleep 1
done

# Focus terminal
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Allow UI to stabilize
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="