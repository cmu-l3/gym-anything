#!/bin/bash
set -euo pipefail

echo "=== Exporting Commercial Fishing Bridge Task Result ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Gracefully close Chrome to flush all data (Preferences, Local State, Web Data) to disk
echo "Closing Chrome to flush data to disk..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3

# Force kill if still running
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# Extract Custom Search Engines from Web Data SQLite database
# Modern Chrome stores custom search engines in the 'keywords' table of 'Web Data'
WEB_DATA_PATH="/home/ga/.config/google-chrome/Default/Web Data"
if [ -f "$WEB_DATA_PATH" ]; then
    echo "Extracting custom search engines from Web Data..."
    sqlite3 "$WEB_DATA_PATH" "SELECT short_name, keyword, url FROM keywords;" > /tmp/chrome_search_engines.txt 2>/dev/null || echo "Failed to query Web Data" > /tmp/chrome_search_engines.txt
else
    echo "Web Data database not found." > /tmp/chrome_search_engines.txt
fi

chmod 666 /tmp/chrome_search_engines.txt

echo "=== Export Complete ==="