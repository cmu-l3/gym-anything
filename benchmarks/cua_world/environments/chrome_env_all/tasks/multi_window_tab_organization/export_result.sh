#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Multi-Window Tab Organization Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq wmctrl xdotool || true

export DISPLAY=:1

# Capture window count
echo "Counting Chrome windows..."
WINDOW_COUNT=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | wc -l)
echo "✓ Found $WINDOW_COUNT Chrome window(s)"
echo "$WINDOW_COUNT" > /tmp/chrome_window_count.txt

# List all Chrome windows with their IDs and titles
echo "Listing Chrome windows..."
wmctrl -l | grep -i 'Google Chrome\|Chromium' > /tmp/chrome_windows_list.txt || echo "" > /tmp/chrome_windows_list.txt
cat /tmp/chrome_windows_list.txt

# Capture all tabs via CDP
echo "Capturing all tabs information via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_all_tabs.json 2>/dev/null; then
    echo "✓ Successfully captured CDP tab information"
    
    # Filter to only page-type tabs (not background pages, extensions, etc.)
    jq '[.[] | select(.type == "page")]' /tmp/chrome_all_tabs.json > /tmp/chrome_page_tabs.json
    
    TAB_COUNT=$(jq 'length' /tmp/chrome_page_tabs.json)
    echo "✓ Found $TAB_COUNT page tab(s)"
    
    # Extract URLs for easy verification
    jq -r '.[] | .url' /tmp/chrome_page_tabs.json > /tmp/tab_urls.txt
    
    echo "Tab URLs:"
    cat /tmp/tab_urls.txt
    
    # Extract titles for additional verification
    jq -r '.[] | .title' /tmp/chrome_page_tabs.json > /tmp/tab_titles.txt
else
    echo "⚠ Warning: Failed to capture CDP information"
    echo "0" > /tmp/chrome_window_count.txt
    echo "[]" > /tmp/chrome_page_tabs.json
    touch /tmp/tab_urls.txt
    touch /tmp/tab_titles.txt
fi

# Attempt to capture information about each window separately
# This is a best-effort approach to identify tab distribution
echo "Attempting to identify window-tab relationships..."

# Get all Chrome window IDs
WINDOW_IDS=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | awk '{print $1}')
WINDOW_ARRAY=($WINDOW_IDS)

if [ ${#WINDOW_ARRAY[@]} -eq 2 ]; then
    echo "Found exactly 2 windows, attempting to identify their tabs..."
    
    # Focus first window and capture its title
    wmctrl -i -a "${WINDOW_ARRAY[0]}" 2>/dev/null || true
    sleep 1
    WINDOW1_TITLE=$(xdotool getactivewindow getwindowname 2>/dev/null || echo "")
    echo "Window 1 title: $WINDOW1_TITLE"
    echo "$WINDOW1_TITLE" > /tmp/window1_title.txt
    
    # Focus second window and capture its title
    wmctrl -i -a "${WINDOW_ARRAY[1]}" 2>/dev/null || true
    sleep 1
    WINDOW2_TITLE=$(xdotool getactivewindow getwindowname 2>/dev/null || echo "")
    echo "Window 2 title: $WINDOW2_TITLE"
    echo "$WINDOW2_TITLE" > /tmp/window2_title.txt
else
    echo "Window count is not 2, skipping window-specific identification"
    echo "" > /tmp/window1_title.txt
    echo "" > /tmp/window2_title.txt
fi

# Take final screenshots of both windows if exactly 2 exist
if [ ${#WINDOW_ARRAY[@]} -eq 2 ]; then
    if command -v import &> /dev/null; then
        wmctrl -i -a "${WINDOW_ARRAY[0]}" 2>/dev/null || true
        sleep 0.5
        su - ga -c "DISPLAY=:1 import -window root /tmp/window1_screenshot.png" 2>/dev/null || true
        
        wmctrl -i -a "${WINDOW_ARRAY[1]}" 2>/dev/null || true
        sleep 0.5
        su - ga -c "DISPLAY=:1 import -window root /tmp/window2_screenshot.png" 2>/dev/null || true
        
        echo "Screenshots saved for both windows"
    fi
fi

# Create a summary file for verification
cat > /tmp/multi_window_summary.json << EOF
{
  "window_count": $WINDOW_COUNT,
  "tab_count": $(jq 'length' /tmp/chrome_page_tabs.json 2>/dev/null || echo 0),
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo "✅ Export complete"
echo "Summary: $WINDOW_COUNT window(s), $(jq 'length' /tmp/chrome_page_tabs.json 2>/dev/null || echo 0) tab(s)"