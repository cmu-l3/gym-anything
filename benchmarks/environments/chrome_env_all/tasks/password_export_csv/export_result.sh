#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Password Export Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Capture active tab URL via CDP
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
fi

# Close Chrome gracefully to ensure any pending exports complete
echo "Closing Chrome to finalize any pending exports..."
pkill -f "google-chrome" || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Create verification directory
VERIFY_DIR="/tmp/password_export_verification"
mkdir -p "$VERIFY_DIR"

# Look for exported CSV files in Downloads folder
DOWNLOADS_DIR="/home/ga/Downloads"
echo "Searching for password export CSV in Downloads folder..."

# Find CSV files created in the last 5 minutes
FOUND_CSV=0
if [ -d "$DOWNLOADS_DIR" ]; then
    echo "Contents of Downloads folder:"
    ls -lah "$DOWNLOADS_DIR" || true
    
    # Look for CSV files with common password export patterns
    for pattern in "*password*.csv" "*chrome*.csv" "*.csv"; do
        for csvfile in "$DOWNLOADS_DIR"/$pattern 2>/dev/null; do
            if [ -f "$csvfile" ]; then
                # Check if file was created recently (last 10 minutes)
                if [ -n "$(find "$csvfile" -mmin -10 2>/dev/null)" ]; then
                    CSV_NAME=$(basename "$csvfile")
                    echo "✓ Found recent CSV file: $CSV_NAME"
                    cp "$csvfile" "$VERIFY_DIR/"
                    echo "$CSV_NAME" >> "$VERIFY_DIR/csv_files_found.txt"
                    FOUND_CSV=1
                fi
            fi
        done
    done
fi

if [ $FOUND_CSV -eq 0 ]; then
    echo "⚠ No CSV files found in Downloads folder"
    echo "none" > "$VERIFY_DIR/csv_files_found.txt"
fi

# Also record metadata about the export
echo "Task completion timestamp: $(date -Iseconds)" > "$VERIFY_DIR/export_metadata.txt"
echo "Downloads directory: $DOWNLOADS_DIR" >> "$VERIFY_DIR/export_metadata.txt"
echo "CSV files found: $FOUND_CSV" >> "$VERIFY_DIR/export_metadata.txt"

# Copy verification data to standard temp location
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files available at: $VERIFY_DIR"