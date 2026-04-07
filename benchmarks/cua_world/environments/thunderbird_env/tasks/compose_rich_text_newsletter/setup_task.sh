#!/bin/bash
echo "=== Setting up compose_rich_text_newsletter task ==="

# Record task start time (for anti-gaming validation)
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Create asset directory
ASSET_DIR="/home/ga/Documents/CompanyAssets"
mkdir -p "$ASSET_DIR"

# Download a real logo (Mozilla logo from Wikimedia Commons)
# Fallback to a valid base64 1x1 PNG if network fails
LOGO_URL="https://upload.wikimedia.org/wikipedia/commons/thumb/d/d1/Mozilla_logo_2017.svg/512px-Mozilla_logo_2017.svg.png"
curl -sfL "$LOGO_URL" -o "$ASSET_DIR/header_logo.png" || python3 -c "
import base64
with open('$ASSET_DIR/header_logo.png', 'wb') as f:
    f.write(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='))
"

# Fix permissions
chown -R ga:ga "$ASSET_DIR"

# Ensure Thunderbird is running
start_thunderbird

# Wait for Thunderbird window to appear
wait_for_thunderbird_window 30

# Maximize the window for full agent visibility
sleep 3
maximize_thunderbird

# Focus main window
wid=$(get_thunderbird_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Take initial screenshot showing the initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="