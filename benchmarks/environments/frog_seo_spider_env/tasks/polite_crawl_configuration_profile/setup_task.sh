#!/bin/bash
# Setup script for Polite Crawl Configuration Profile task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Polite Crawl Configuration Task ==="

# Kill any existing Screaming Frog instances
kill_screamingfrog ga
sleep 1

# Record task start time
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch

# Clear previous crawl data/configs to ensure fresh state
echo "Clearing previous data..."
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/*.seospider 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/spider.config 2>/dev/null || true
fi

# Create required directories
mkdir -p "/home/ga/Documents/SEO/configs"
mkdir -p "/home/ga/Documents/SEO/reports"
mkdir -p "/home/ga/Documents/SEO/exports"
chown -R ga:ga "/home/ga/Documents/SEO/"

# Clear specific target files if they exist (from previous runs)
rm -f "/home/ga/Documents/SEO/configs/polite_profile.seospiderconfig"
rm -f "/home/ga/Documents/SEO/exports/polite_crawl_data.csv"
rm -f "/home/ga/Documents/SEO/reports/speed_settings.png"
rm -f "/home/ga/Documents/SEO/reports/ua_settings.png"

# Setup default configuration again (since we cleared it)
# We want the agent to start from default, not a pre-configured polite state
/workspace/scripts/setup_screamingfrog.sh > /dev/null 2>&1

# Launch Screaming Frog
echo "Launching Screaming Frog SEO Spider..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

# Wait for process to start
if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

# Wait for main window
if ! wait_for_window "Screaming Frog\|SEO Spider" 45; then
    echo "WARNING: Screaming Frog window may not be visible yet"
fi

sleep 5

# Handle EULA dialog if present
echo "Checking for EULA dialog..."
eula_window=$(su - ga -c "DISPLAY=:1 xdotool search --name 'License Agreement' 2>/dev/null | head -1")
if [ -n "$eula_window" ]; then
    echo "EULA dialog detected, accepting..."
    su - ga -c "DISPLAY=:1 xdotool windowactivate --sync $eula_window 2>/dev/null" || true
    sleep 1
    su - ga -c "DISPLAY=:1 xdotool key Return" || true
    sleep 3
fi

# Wait for SF to fully initialize
echo "Waiting for Screaming Frog to fully initialize..."
wait_for_sf_ready 60

# Additional stabilization
sleep 2

# Focus Screaming Frog window
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Task ready."