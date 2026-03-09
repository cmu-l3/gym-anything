#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Tab Search Navigation Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create export directory
EXPORT_DIR="/tmp/tab_search_task"
mkdir -p "$EXPORT_DIR"

# Capture all tabs information via CDP
echo "Capturing all tabs information via CDP..."
if curl -s http://localhost:9222/json > "$EXPORT_DIR/all_tabs.json" 2>/dev/null; then
    echo "✓ Successfully captured CDP tab information"
    
    # Filter to only page-type tabs (not background pages, extensions, etc.)
    jq '[.[] | select(.type == "page")]' "$EXPORT_DIR/all_tabs.json" > "$EXPORT_DIR/page_tabs.json"
    
    TAB_COUNT=$(jq 'length' "$EXPORT_DIR/page_tabs.json")
    echo "✓ Found $TAB_COUNT page tab(s)"
    
    # Identify the active/focused tab (first in list is typically active)
    jq '.[0]' "$EXPORT_DIR/page_tabs.json" > "$EXPORT_DIR/active_tab.json"
    
    ACTIVE_URL=$(jq -r '.url // "unknown"' "$EXPORT_DIR/active_tab.json")
    ACTIVE_TITLE=$(jq -r '.title // "unknown"' "$EXPORT_DIR/active_tab.json")
    
    echo "Active tab:"
    echo "  URL: $ACTIVE_URL"
    echo "  Title: $ACTIVE_TITLE"
    
    # Save active tab info in simple text format
    echo "$ACTIVE_URL" > "$EXPORT_DIR/active_url.txt"
    echo "$ACTIVE_TITLE" > "$EXPORT_DIR/active_title.txt"
    
    # List all tabs for debugging
    echo "All tabs:"
    jq -r '.[] | "  [\(.url | .[0:60])]... - \(.title | .[0:50])..."' "$EXPORT_DIR/page_tabs.json" || true
    
else
    echo "⚠ Warning: Failed to capture CDP information"
    # Create empty files to prevent verification errors
    echo "[]" > "$EXPORT_DIR/page_tabs.json"
    echo "{}" > "$EXPORT_DIR/active_tab.json"
    echo "unknown" > "$EXPORT_DIR/active_url.txt"
    echo "unknown" > "$EXPORT_DIR/active_title.txt"
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $EXPORT_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to $EXPORT_DIR/final_screenshot.png"
fi

# Copy target info to export directory for verification
if [ -f /tmp/tab_search_task/target_url.txt ]; then
    cp /tmp/tab_search_task/target_url.txt "$EXPORT_DIR/target_url.txt" || true
fi
if [ -f /tmp/tab_search_task/target_keywords.txt ]; then
    cp /tmp/tab_search_task/target_keywords.txt "$EXPORT_DIR/target_keywords.txt" || true
fi

echo "✅ Export complete"
echo "Verification data saved to: $EXPORT_DIR"