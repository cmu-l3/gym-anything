#!/bin/bash
# Setup script for Image Asset Format Audit task
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Image Asset Format Audit Task ==="

# 1. Kill any existing Screaming Frog instances
kill_screamingfrog ga
sleep 1

# 2. Record task start time (for anti-gaming)
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch
echo "[$(date -Iseconds)] Task setup started" > /tmp/setup_timing.log

# 3. Clear previous crawl data to ensure fresh start
echo "Clearing previous crawl data..."
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/*.seospider 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/recent_crawls.xml 2>/dev/null || true
fi

# 4. Prepare export and report directories
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
mkdir -p "$EXPORT_DIR"
mkdir -p "$REPORTS_DIR"
chown -R ga:ga /home/ga/Documents/SEO/ 2>/dev/null || true

# 5. Clear old files
rm -f "$EXPORT_DIR"/*.csv 2>/dev/null || true
rm -f "$REPORTS_DIR"/*.txt 2>/dev/null || true

# 6. Launch Screaming Frog
echo "Launching Screaming Frog SEO Spider..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

# 7. Wait for process
if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

# 8. Wait for window and full initialization
if ! wait_for_window "Screaming Frog\|SEO Spider" 45; then
    echo "WARNING: Screaming Frog window may not be visible yet"
fi

echo "Waiting for Screaming Frog to fully initialize..."
wait_for_sf_ready 60

# 9. Stabilization and Focus
sleep 5
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    echo "Focused Screaming Frog window: $wid"
fi

# 10. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Target: https://books.toscrape.com/"
echo "Instructions:"
echo "1. Crawl the site."
echo "2. Export Image details to $EXPORT_DIR/image_inventory.csv"
echo "3. Write analysis report to $REPORTS_DIR/image_optimization_strategy.txt"