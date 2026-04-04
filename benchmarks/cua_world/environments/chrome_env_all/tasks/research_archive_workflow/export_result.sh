#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Research Archive Workflow Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure any pending operations complete
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 2

# Create verification directory
VERIFY_DIR="/tmp/research_archive_verification"
mkdir -p "$VERIFY_DIR"

# Capture active tab URL via CDP for verification
echo "Capturing active tab information via CDP..."
if curl -s http://localhost:9222/json > "$VERIFY_DIR/chrome_tabs.json" 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' "$VERIFY_DIR/chrome_tabs.json")
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > "$VERIFY_DIR/final_url.txt"
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved"
fi

# Gracefully close Chrome to ensure all data is saved to disk
echo "Closing Chrome to save bookmarks and preferences..."
pkill -f "google-chrome" || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Chrome Bookmarks file
echo "Exporting Chrome Bookmarks..."
CHROME_PROFILE_PRIMARY="/home/ga/.config/google-chrome-cdp/Default"
CHROME_PROFILE_ALT="/home/ga/.config/google-chrome/Default"

if [ -f "$CHROME_PROFILE_PRIMARY/Bookmarks" ]; then
    cp "$CHROME_PROFILE_PRIMARY/Bookmarks" "$VERIFY_DIR/Bookmarks.json"
    echo "✓ Bookmarks exported from primary location"
elif [ -f "$CHROME_PROFILE_ALT/Bookmarks" ]; then
    cp "$CHROME_PROFILE_ALT/Bookmarks" "$VERIFY_DIR/Bookmarks.json"
    echo "✓ Bookmarks exported from alternative location"
else
    echo "⚠ Warning: Bookmarks file not found"
    touch "$VERIFY_DIR/Bookmarks.json"
fi

# Export Chrome Preferences (contains Reading List data)
echo "Exporting Chrome Preferences..."
if [ -f "$CHROME_PROFILE_PRIMARY/Preferences" ]; then
    cp "$CHROME_PROFILE_PRIMARY/Preferences" "$VERIFY_DIR/Preferences.json"
    echo "✓ Preferences exported from primary location"
elif [ -f "$CHROME_PROFILE_ALT/Preferences" ]; then
    cp "$CHROME_PROFILE_ALT/Preferences" "$VERIFY_DIR/Preferences.json"
    echo "✓ Preferences exported from alternative location"
else
    echo "⚠ Warning: Preferences file not found"
    touch "$VERIFY_DIR/Preferences.json"
fi

# Look for generated PDF in Downloads
DOWNLOADS_DIR="/home/ga/Downloads"
echo "Searching for PDF files in Downloads..."

# Find PDFs created in the last 10 minutes
RECENT_PDFS=$(find "$DOWNLOADS_DIR" -name "*.pdf" -type f -mmin -10 2>/dev/null || true)

if [ -n "$RECENT_PDFS" ]; then
    echo "✓ Found recent PDF(s):"
    echo "$RECENT_PDFS" | while read -r pdf_path; do
        pdf_name=$(basename "$pdf_path")
        echo "  - $pdf_name ($(stat -f%z "$pdf_path" 2>/dev/null || stat -c%s "$pdf_path" 2>/dev/null) bytes)"
        # Copy PDF to verification directory
        cp "$pdf_path" "$VERIFY_DIR/" 2>/dev/null || true
    done
    
    # Save list of PDF filenames
    echo "$RECENT_PDFS" | while read -r pdf_path; do basename "$pdf_path"; done > "$VERIFY_DIR/pdf_files.txt"
else
    echo "⚠ No recent PDF files found"
    touch "$VERIFY_DIR/pdf_files.txt"
fi

# List all Downloads contents for debugging
echo "Downloads directory contents:"
ls -lah "$DOWNLOADS_DIR" 2>/dev/null || echo "Could not list Downloads directory"

# Copy all verification data to standard /tmp location
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files prepared in: $VERIFY_DIR"
echo "Files exported: Bookmarks, Preferences, PDFs, screenshots"