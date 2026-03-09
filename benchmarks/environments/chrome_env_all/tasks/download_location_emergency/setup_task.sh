#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Download Location Emergency Reconfiguration Task Setup ==="
echo "Task: Change download location to secondary storage due to disk space constraints"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Wait for environment to be ready
sleep 2

# Create the secondary storage directory structure (simulating external drive/different partition)
echo "Creating secondary storage location..."
SECONDARY_STORAGE="/home/ga/secondary_storage"
DOWNLOADS_DIR="$SECONDARY_STORAGE/downloads"

# Create directories with proper ownership
mkdir -p "$DOWNLOADS_DIR"
chown -R ga:ga "$SECONDARY_STORAGE"
chmod 755 "$SECONDARY_STORAGE"
chmod 755 "$DOWNLOADS_DIR"

if [ -d "$DOWNLOADS_DIR" ]; then
    echo "✓ Secondary storage location created: $DOWNLOADS_DIR"
    ls -la "$SECONDARY_STORAGE"
else
    echo "✗ Failed to create secondary storage location"
    exit 1
fi

# Create a README file in secondary storage to make it feel realistic
cat > "$SECONDARY_STORAGE/README.txt" << 'EOF'
SECONDARY STORAGE DRIVE
=======================
This directory simulates an external hard drive or secondary partition
with more available space for large downloads.

Mount point: /home/ga/secondary_storage/
Use this location when primary disk is running low on space.
EOF

chown ga:ga "$SECONDARY_STORAGE/README.txt"
echo "✓ Secondary storage environment configured"

# Ensure Chrome is properly focused and ready
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
    sleep 5
else
    echo "Chrome is already running"
fi

# Wait for Chrome to be fully ready
sleep 2

# IMPORTANT: Click at center to select desktop (multi-desktop environments)
# This ensures we're on the first desktop where Chrome is running
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Chrome window using wmctrl
export DISPLAY=:1
wid=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | head -1 | awk '{print $1}')
if [ -z "$wid" ]; then
    echo "Warning: Could not find Chrome window"
else
    echo "Focusing Chrome window: $wid"
    wmctrl -i -a $wid || true
    sleep 1
fi

# Navigate to the starting URL (Google homepage as neutral starting point)
echo "Navigating to: https://www.google.com"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://www.google.com'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    
    # Get current download location for debugging
    CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        CURRENT_DL=$(jq -r '.download.default_directory // "/home/ga/Downloads"' "$CHROME_PROFILE/Preferences" 2>/dev/null || echo "/home/ga/Downloads")
        echo "✓ Current download location: $CURRENT_DL"
    fi
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Display task context to agent (simulating urgency)
echo ""
echo "=========================================="
echo "EMERGENCY: Primary disk partition low on space!"
echo "Current download location: /home/ga/Downloads"
echo "Required action: Change to secondary storage"
echo "Target location: $DOWNLOADS_DIR"
echo "=========================================="
echo ""

echo "=== Setup complete ==="
echo "Chrome is ready. Agent should:"
echo "  1. Navigate to chrome://settings or use menu: Settings"
echo "  2. Go to Downloads section"
echo "  3. Click 'Change' button next to Location"
echo "  4. Navigate to and select: $DOWNLOADS_DIR"
echo "  5. Confirm the selection"