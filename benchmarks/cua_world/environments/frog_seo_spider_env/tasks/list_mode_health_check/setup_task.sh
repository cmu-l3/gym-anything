#!/bin/bash
# Setup script for List Mode Health Check task

source /workspace/scripts/task_utils.sh

echo "=== Setting up List Mode Health Check Task ==="

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

# Create required directories
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
mkdir -p "$EXPORT_DIR"
mkdir -p "$REPORTS_DIR"
chown -R ga:ga /home/ga/Documents/SEO/ 2>/dev/null || true

# Clear old exports and reports
rm -f "$EXPORT_DIR"/*.csv 2>/dev/null || true
rm -f "$REPORTS_DIR"/landing_page_health.txt 2>/dev/null || true

# Create the URL list file
URL_LIST_FILE="/home/ga/Documents/SEO/landing_pages.txt"
echo "Creating URL list file at $URL_LIST_FILE..."

cat > "$URL_LIST_FILE" << EOF
https://books.toscrape.com/
https://books.toscrape.com/catalogue/category/books/travel_2/index.html
https://books.toscrape.com/catalogue/category/books/mystery_3/index.html
https://books.toscrape.com/catalogue/category/books/historical-fiction_4/index.html
https://books.toscrape.com/catalogue/category/books/sequential-art_5/index.html
https://books.toscrape.com/catalogue/category/books/classics_6/index.html
https://books.toscrape.com/catalogue/category/books/philosophy_7/index.html
https://books.toscrape.com/catalogue/category/books/romance_8/index.html
https://books.toscrape.com/catalogue/category/books/womens-fiction_9/index.html
https://books.toscrape.com/catalogue/category/books/fiction_10/index.html
https://books.toscrape.com/catalogue/category/books/childrens_11/index.html
https://books.toscrape.com/catalogue/category/books/nonfiction_13/index.html
https://books.toscrape.com/catalogue/a-light-in-the-attic_1000/index.html
https://books.toscrape.com/catalogue/tipping-the-velvet_999/index.html
https://books.toscrape.com/catalogue/soumission_998/index.html
https://books.toscrape.com/catalogue/sharp-objects_997/index.html
https://books.toscrape.com/catalogue/sapiens-a-brief-history-of-humankind_996/index.html
https://books.toscrape.com/catalogue/the-requiem-red_995/index.html
https://books.toscrape.com/catalogue/the-dirty-little-secrets-of-getting-your-dream-job_994/index.html
https://books.toscrape.com/catalogue/the-coming-woman-a-novel-based-on-the-life-of-the-infamous-feminist-victoria-woodhull_993/index.html
EOF

chown ga:ga "$URL_LIST_FILE"
chmod 644 "$URL_LIST_FILE"

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
sleep 5

# Focus Screaming Frog window
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    echo "Focused Screaming Frog window: $wid"
fi

sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== List Mode Health Check Setup Complete ==="
echo ""
echo "TASK INSTRUCTIONS:"
echo "  1. Switch Mode to 'List'"
echo "  2. Upload URL list from: $URL_LIST_FILE"
echo "  3. Start Analysis"
echo "  4. Export Internal HTML results to ~/Documents/SEO/exports/"
echo "  5. Write summary report to ~/Documents/SEO/reports/landing_page_health.txt"