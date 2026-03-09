#!/bin/bash
# Setup script for HTTPS Security Protocol Audit task
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up HTTPS Security Protocol Audit Task ==="

# 1. Clean environment
kill_screamingfrog ga
sleep 1

# 2. Record start timestamp for anti-gaming verification
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch
echo "[$(date -Iseconds)] Task setup started" > /tmp/setup_timing.log

# 3. Clear previous data to ensure fresh start
echo "Clearing previous crawl data..."
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/*.seospider 2>/dev/null || true
    echo "Cleared Screaming Frog cache"
fi

# 4. Prepare directories and remove old exports
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
mkdir -p "$EXPORT_DIR"
mkdir -p "$REPORTS_DIR"
chown -R ga:ga /home/ga/Documents/SEO/ 2>/dev/null || true

# Remove specific target files if they exist from previous runs
rm -f "$EXPORT_DIR/security_tab_export.csv"
rm -f "$EXPORT_DIR/internal_all_export.csv"
rm -f "$REPORTS_DIR/security_audit_report.txt"

# 5. Launch Screaming Frog
echo "Launching Screaming Frog SEO Spider..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

# 6. Wait for process and window
if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

if ! wait_for_window "Screaming Frog\|SEO Spider" 45; then
    echo "WARNING: Screaming Frog window may not be visible yet"
fi

sleep 5

# 7. Handle EULA if present
eula_window=$(su - ga -c "DISPLAY=:1 xdotool search --name 'License Agreement' 2>/dev/null | head -1")
if [ -n "$eula_window" ]; then
    echo "EULA dialog detected, accepting..."
    su - ga -c "DISPLAY=:1 xdotool windowactivate --sync $eula_window 2>/dev/null" || true
    sleep 1
    su - ga -c "DISPLAY=:1 xdotool key Return" || true
    sleep 3
fi

# 8. Wait for App Ready state
echo "Waiting for Screaming Frog to fully initialize..."
wait_for_sf_ready 60

# 9. Focus window
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# 10. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Target: https://crawler-test.com/"
echo "Outputs required:"
echo "  1. ~/Documents/SEO/exports/security_tab_export.csv"
echo "  2. ~/Documents/SEO/exports/internal_all_export.csv"
echo "  3. ~/Documents/SEO/reports/security_audit_report.txt"