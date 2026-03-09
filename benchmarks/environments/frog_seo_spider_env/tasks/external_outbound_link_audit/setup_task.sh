#!/bin/bash
# Setup script for External Outbound Link Audit

source /workspace/scripts/task_utils.sh

echo "=== Setting up External Outbound Link Audit Task ==="

# 1. Kill existing instances
kill_screamingfrog ga
sleep 1

# 2. Record task start time (Critical for anti-gaming)
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch
echo "[$(date -Iseconds)] Task setup started" > /tmp/setup_timing.log

# 3. Clean up previous data to ensure a fresh start
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/*.seospider 2>/dev/null || true
    echo "Cleared Screaming Frog cache"
fi

# 4. Prepare directories and clean old exports
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
mkdir -p "$EXPORT_DIR"
mkdir -p "$REPORTS_DIR"
chown -R ga:ga /home/ga/Documents/SEO/ 2>/dev/null || true

# Remove old files so we can detect new ones easily
rm -f "$EXPORT_DIR"/*.csv 2>/dev/null || true
rm -f "$REPORTS_DIR"/*.txt 2>/dev/null || true

# 5. Launch Screaming Frog
echo "Launching Screaming Frog SEO Spider..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

# 6. Wait for application to be ready
if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

if ! wait_for_window "Screaming Frog\|SEO Spider" 45; then
    echo "WARNING: Screaming Frog window may not be visible"
fi

# Handle potential EULA
sleep 5
eula_window=$(su - ga -c "DISPLAY=:1 xdotool search --name 'License Agreement' 2>/dev/null | head -1")
if [ -n "$eula_window" ]; then
    echo "EULA detected, accepting..."
    su - ga -c "DISPLAY=:1 xdotool windowactivate --sync $eula_window 2>/dev/null" || true
    sleep 1
    su - ga -c "DISPLAY=:1 xdotool key Return" || true
    sleep 3
fi

echo "Waiting for Screaming Frog to fully initialize..."
wait_for_sf_ready 60
echo "[$(date -Iseconds)] SF ready" >> /tmp/setup_timing.log

# 7. Focus window and take initial screenshot
sleep 5
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Task: External Outbound Link Audit"
echo "Target: https://crawler-test.com/"