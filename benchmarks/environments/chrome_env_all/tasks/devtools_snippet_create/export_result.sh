#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome DevTools Snippet Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture final page title via CDP (to check if snippet was executed)
echo "Capturing final page title via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs_final.json 2>/dev/null; then
    FINAL_TITLE=$(jq -r '[.[] | select(.type == "page")][0].title // ""' /tmp/chrome_tabs_final.json)
    echo "Final page title: $FINAL_TITLE"
    echo "$FINAL_TITLE" > /tmp/final_page_title.txt
    
    # Also capture the URL for context
    FINAL_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs_final.json)
    echo "Final URL: $FINAL_URL"
    echo "$FINAL_URL" > /tmp/final_page_url.txt
else
    echo "⚠ Warning: Could not capture CDP information"
    echo "unknown" > /tmp/final_page_title.txt
fi

# Take a screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Try to capture console logs if available (check if Console API logged anything)
# This is complex via CDP, so we'll skip for now

# Store current timestamp
date +%s > /tmp/task_end_timestamp.txt

# Now close Chrome to ensure all DevTools data is persisted to disk
echo "Closing Chrome to save DevTools state..."
pkill -f "google-chrome" || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 2
fi

# Export Chrome profile directories for snippet verification
echo "Exporting Chrome profile data for verification..."

# Primary profile location
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
# Alternative location
CHROME_PROFILE_ALT="/home/ga/.config/google-chrome/Default"

# Try to find and copy snippet-related files
# Snippets can be stored in multiple locations depending on Chrome version

# Location 1: IndexedDB (most common for newer Chrome)
INDEXEDDB_DIR="$CHROME_PROFILE/IndexedDB"
if [ -d "$INDEXEDDB_DIR" ]; then
    echo "Found IndexedDB directory, copying..."
    mkdir -p /tmp/chrome_indexeddb/
    cp -r "$INDEXEDDB_DIR"/* /tmp/chrome_indexeddb/ 2>/dev/null || true
    echo "✓ IndexedDB copied to /tmp/chrome_indexeddb/"
else
    echo "⚠ IndexedDB directory not found at: $INDEXEDDB_DIR"
    # Try alternative location
    INDEXEDDB_DIR="$CHROME_PROFILE_ALT/IndexedDB"
    if [ -d "$INDEXEDDB_DIR" ]; then
        mkdir -p /tmp/chrome_indexeddb/
        cp -r "$INDEXEDDB_DIR"/* /tmp/chrome_indexeddb/ 2>/dev/null || true
        echo "✓ IndexedDB copied from alternative location"
    fi
fi

# Location 2: File System (older Chrome versions or workspace storage)
FILE_SYSTEM_DIR="$CHROME_PROFILE/File System"
if [ -d "$FILE_SYSTEM_DIR" ]; then
    echo "Found File System directory, copying..."
    mkdir -p /tmp/chrome_filesystem/
    cp -r "$FILE_SYSTEM_DIR"/* /tmp/chrome_filesystem/ 2>/dev/null || true
    echo "✓ File System copied to /tmp/chrome_filesystem/"
fi

# Location 3: Local Storage (may contain DevTools settings)
LOCAL_STORAGE_DIR="$CHROME_PROFILE/Local Storage"
if [ -d "$LOCAL_STORAGE_DIR" ]; then
    echo "Found Local Storage directory, copying..."
    mkdir -p /tmp/chrome_localstorage/
    cp -r "$LOCAL_STORAGE_DIR"/* /tmp/chrome_localstorage/ 2>/dev/null || true
    echo "✓ Local Storage copied to /tmp/chrome_localstorage/"
fi

# Location 4: Preferences file (may contain DevTools settings)
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences.json
    echo "✓ Preferences exported to /tmp/chrome_preferences.json"
elif [ -f "$CHROME_PROFILE_ALT/Preferences" ]; then
    cp "$CHROME_PROFILE_ALT/Preferences" /tmp/chrome_preferences.json
    echo "✓ Preferences exported from alternative location"
else
    echo "⚠ Warning: Preferences file not found"
fi

# Create a manifest of all files copied
echo "Creating file manifest..."
find /tmp/chrome_indexeddb /tmp/chrome_filesystem /tmp/chrome_localstorage -type f 2>/dev/null | head -50 > /tmp/chrome_files_manifest.txt || true

# Try to search for snippet-related content in text files
echo "Searching for snippet evidence..."
grep -r "PageTitleChanger" /tmp/chrome_* 2>/dev/null | head -5 > /tmp/snippet_search_results.txt || true
grep -r "Modified by DevTools Snippet" /tmp/chrome_* 2>/dev/null | head -5 >> /tmp/snippet_search_results.txt || true

echo "✅ Export complete"
echo "Exported data:"
echo "  - Final page title: $(cat /tmp/final_page_title.txt 2>/dev/null || echo 'unknown')"
echo "  - IndexedDB: /tmp/chrome_indexeddb/"
echo "  - File System: /tmp/chrome_filesystem/"
echo "  - Local Storage: /tmp/chrome_localstorage/"
echo "  - Preferences: /tmp/chrome_preferences.json"