#!/bin/bash
# Setup script for Insecure Form Security Audit task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Insecure Form Security Audit Task ==="

# Kill any existing Screaming Frog instances
kill_screamingfrog ga
sleep 1

# Record task start time
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch
echo "[$(date -Iseconds)] Task setup started" > /tmp/setup_timing.log

# Clear previous crawl data to ensure clean state
echo "Clearing previous crawl data..."
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/*.seospider 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/recent_crawls.xml 2>/dev/null || true
fi

# Create export directory
EXPORT_DIR="/home/ga/Documents/SEO/exports"
mkdir -p "$EXPORT_DIR"
chown -R ga:ga /home/ga/Documents/SEO/ 2>/dev/null || true

# Clear old exports
rm -f "$EXPORT_DIR"/*.csv 2>/dev/null || true

# Record initial file count
ls -1 "$EXPORT_DIR"/*.csv 2>/dev/null | wc -l > /tmp/initial_export_count

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

echo "=== Insecure Form Security Audit Setup Complete ==="
echo ""
echo "TASK INSTRUCTIONS:"
echo "  1. Crawl https://crawler-test.com/"
echo "  2. Go to the 'Security' tab"
echo "  3. Filter for 'Form on HTTP' or similar insecure form issues"
echo "  4. Export the results to ~/Documents/SEO/exports/"