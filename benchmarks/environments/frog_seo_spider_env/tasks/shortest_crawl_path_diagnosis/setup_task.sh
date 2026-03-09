#!/bin/bash
# Setup script for Shortest Crawl Path Diagnosis task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Shortest Crawl Path Diagnosis Task ==="

# 1. Kill any existing Screaming Frog instances to ensure fresh start
kill_screamingfrog ga
sleep 1

# 2. Record task start timestamp for anti-gaming (file modification checks)
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch

# 3. Clean up previous task artifacts
echo "Cleaning up previous exports and reports..."
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
mkdir -p "$EXPORT_DIR"
mkdir -p "$REPORTS_DIR"

# Remove specific expected files and any general CSVs to ensure we detect new ones
rm -f "$EXPORT_DIR"/himalayas_path.csv 2>/dev/null || true
rm -f "$REPORTS_DIR"/depth_value.txt 2>/dev/null || true
# Clean internal SF state if possible (optional, but good for "fresh" crawl)
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    rm -rf "$SF_DATA_DIR"/crawl_cache/* 2>/dev/null || true
    rm -rf "$SF_DATA_DIR"/tmp/* 2>/dev/null || true
fi

# 4. Set permissions
chown -R ga:ga /home/ga/Documents/SEO/

# 5. Launch Screaming Frog
echo "Launching Screaming Frog SEO Spider..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

# 6. Wait for application to be ready
if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

echo "Waiting for Screaming Frog UI..."
wait_for_sf_ready 60

# 7. Maximize and focus
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -ir "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 8. Capture initial state screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Target Site: https://books.toscrape.com/"
echo "Target Book: It's Only the Himalayas"
echo "Instructions:"
echo "1. Crawl the site."
echo "2. Find the book URL."
echo "3. Right-click > Export > Crawl Path Report."
echo "4. Save to ~/Documents/SEO/exports/himalayas_path.csv"
echo "5. Write the depth number to ~/Documents/SEO/reports/depth_value.txt"