#!/bin/bash
echo "=== Setting up export_multi_format_wfs task ==="

source /workspace/scripts/task_utils.sh

# Create export directory
mkdir -p /home/ga/exports
rm -f /home/ga/exports/*
chown ga:ga /home/ga/exports

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure GeoServer is running and accessible
echo "Waiting for GeoServer..."
verify_geoserver_ready 60

# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/geoserver/web/' &"
    sleep 5
fi

# Wait for Firefox window
wait_for_window "firefox\|mozilla" 30

# Focus Firefox
focus_firefox
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="