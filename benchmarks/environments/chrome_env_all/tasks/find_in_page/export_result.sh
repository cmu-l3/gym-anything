#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Find in Page Task Export: find_in_page@1 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq imagemagick xdotool wmctrl || true

# Focus Chrome window to ensure proper screenshot
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create verification directory
VERIFY_DIR="/tmp/find_page_verification"
mkdir -p "$VERIFY_DIR"

echo "Capturing find bar state..."

# Wait a moment to ensure find bar is still visible
sleep 1

# Capture full Chrome window screenshot for find bar detection
echo "Taking screenshot of Chrome window..."
su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/find_screenshot.png" 2>/dev/null || true
if [ -f "$VERIFY_DIR/find_screenshot.png" ]; then
    echo "✓ Screenshot captured: find_screenshot.png"
    
    # Also capture just the top portion where find bar appears
    convert "$VERIFY_DIR/find_screenshot.png" -crop 400x150+880+0 "$VERIFY_DIR/find_bar_region.png" 2>/dev/null || true
    echo "✓ Find bar region extracted"
fi

# Capture active tab URL and title via CDP
echo "Capturing active tab information via CDP..."
if curl -s http://localhost:9222/json > "$VERIFY_DIR/chrome_tabs.json" 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' "$VERIFY_DIR/chrome_tabs.json")
    ACTIVE_TITLE=$(jq -r '[.[] | select(.type == "page")][0].title // ""' "$VERIFY_DIR/chrome_tabs.json")
    echo "Active URL: $ACTIVE_URL"
    echo "Active Title: $ACTIVE_TITLE"
    echo "$ACTIVE_URL" > "$VERIFY_DIR/final_url.txt"
    echo "$ACTIVE_TITLE" > "$VERIFY_DIR/final_title.txt"
    echo "✓ CDP information captured"
fi

# Try to capture the HTML content for text verification
echo "Attempting to capture page content..."
ARTICLE_PATH="/home/ga/Documents/climate_article.html"
if [ -f "$ARTICLE_PATH" ]; then
    cp "$ARTICLE_PATH" "$VERIFY_DIR/page_content.html"
    echo "✓ Page content copied for verification"
fi

# Check if find bar might still be open by looking for find-related Chrome processes
# (This is indirect but can provide hints)
CHROME_WINDOWS=$(su - ga -c "DISPLAY=:1 xdotool search --class chrome" 2>/dev/null || true)
echo "Chrome window IDs: $CHROME_WINDOWS" > "$VERIFY_DIR/window_info.txt"

# Create a metadata file with task information
cat > "$VERIFY_DIR/task_metadata.json" << EOF
{
  "task_id": "find_in_page@1",
  "expected_search_term": "climate",
  "expected_min_matches": 3,
  "page_url": "file:///home/ga/Documents/climate_article.html",
  "export_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo "✓ Task metadata created"

# Copy all verification files to standard temp location
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files available at: $VERIFY_DIR"
ls -lh "$VERIFY_DIR"