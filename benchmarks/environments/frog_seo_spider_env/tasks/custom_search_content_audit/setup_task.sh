#!/bin/bash
# Setup script for Custom Search Content Audit task
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Custom Search Content Audit Task ==="

# 1. Kill any existing instances
kill_screamingfrog ga
sleep 1

# 2. Record task start time for anti-gaming verification
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch
echo "[$(date -Iseconds)] Task setup started" > /tmp/setup_timing.log

# 3. Clear previous data to ensure fresh state
echo "Clearing previous crawl data..."
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/*.seospider 2>/dev/null || true
    rm -f "$SF_DATA_DIR"/recent_crawls.xml 2>/dev/null || true
fi

# 4. Prepare directories and clean old outputs
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
mkdir -p "$EXPORT_DIR"
mkdir -p "$REPORTS_DIR"
chown -R ga:ga /home/ga/Documents/SEO/ 2>/dev/null || true

# Remove potential target files to ensure we verify NEW work
rm -f "$EXPORT_DIR/custom_search_results.csv" 2>/dev/null || true
rm -f "$REPORTS_DIR/content_quality_report.txt" 2>/dev/null || true

# 5. Launch Screaming Frog
echo "Launching Screaming Frog SEO Spider..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

# 6. Wait for process
if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

# 7. Wait for window
if ! wait_for_window "Screaming Frog\|SEO Spider" 45; then
    echo "WARNING: Screaming Frog window may not be visible yet"
fi

sleep 5

# 8. Handle EULA (if needed)
eula_window=$(su - ga -c "DISPLAY=:1 xdotool search --name 'License Agreement' 2>/dev/null | head -1")
if [ -n "$eula_window" ]; then
    echo "EULA dialog detected, accepting..."
    su - ga -c "DISPLAY=:1 xdotool windowactivate --sync $eula_window 2>/dev/null" || true
    sleep 1
    su - ga -c "DISPLAY=:1 xdotool key Return" || true
    sleep 3
fi

# 9. Wait for full readiness
echo "Waiting for Screaming Frog to fully initialize..."
wait_for_sf_ready 60

# 10. Final UI stabilization
sleep 5
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    echo "Focused Screaming Frog window: $wid"
fi

# 11. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Target: https://books.toscrape.com/"
echo "Required Rules:"
echo "  1. 'Buy Button' (Contains 'Add to basket')"
echo "  2. 'Availability' (Contains 'In stock')"
echo "  3. 'Price Format' (Regex '£[0-9]+\.[0-9]{2}')"