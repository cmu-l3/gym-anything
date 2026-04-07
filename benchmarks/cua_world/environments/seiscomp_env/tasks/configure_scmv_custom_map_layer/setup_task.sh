#!/bin/bash
echo "=== Setting up configure_scmv_custom_map_layer task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time

# 1. Ensure services are running
ensure_scmaster_running

# 2. Clean up any previous state
echo "Cleaning up previous state..."
rm -rf /home/ga/.seiscomp/bna/noto_zone.bna
rm -f /home/ga/scmv_layer_verification.png

# Ensure the bna directory exists
mkdir -p /home/ga/.seiscomp/bna
chown -R ga:ga /home/ga/.seiscomp/bna

# Backup and clear scmv.cfg if it exists
if [ -f /home/ga/.seiscomp/scmv.cfg ]; then
    mv /home/ga/.seiscomp/scmv.cfg /home/ga/.seiscomp/scmv.cfg.bak
fi
touch /home/ga/.seiscomp/scmv.cfg
chown ga:ga /home/ga/.seiscomp/scmv.cfg

# 3. Kill any existing scmv instances
kill_seiscomp_gui scmv

# 4. Take initial screenshot
echo "Capturing initial state..."
sleep 1
take_screenshot /tmp/task_initial.png

# Verify screenshot
if [ -f /tmp/task_initial.png ]; then
    echo "Initial screenshot captured."
else
    echo "WARNING: Could not capture initial screenshot."
fi

echo "=== Task setup complete ==="