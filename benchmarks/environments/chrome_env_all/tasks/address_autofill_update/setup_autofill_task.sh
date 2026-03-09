#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Address Autofill Update Task Setup ==="
echo "Task: Remove old address and add new current address to Chrome autofill"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip uuid-runtime || true

# Wait for environment to be ready
sleep 2

# Determine Chrome profile directory
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ ! -d "/home/ga/.config/google-chrome-cdp" ]; then
    CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
fi

echo "Using Chrome profile: $CHROME_PROFILE"
mkdir -p "$CHROME_PROFILE"

# Check if Chrome is running and stop it to modify preferences
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome is running, stopping it to modify autofill data..."
    pkill -f "google-chrome" || true
    sleep 2
fi

# Backup existing Preferences if they exist
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    echo "Backing up existing Preferences..."
    cp "$CHROME_PROFILE/Preferences" "$CHROME_PROFILE/Preferences.backup_autofill" || true
fi

# Generate a unique GUID for the old address
OLD_ADDRESS_GUID=$(uuidgen 2>/dev/null || echo "00000000-0000-0000-0000-$(date +%s)000001")

# Create or modify Preferences file to inject old address
echo "Injecting old address into Chrome autofill data..."

# Create Python script to safely modify JSON
python3 << 'PYTHON_SCRIPT'
import json
import os
import sys
from datetime import datetime

chrome_profile = os.environ.get('CHROME_PROFILE', '/home/ga/.config/google-chrome/Default')
prefs_path = os.path.join(chrome_profile, 'Preferences')
old_guid = os.environ.get('OLD_ADDRESS_GUID', '00000000-0000-0000-0000-000000000001')

# Load existing preferences or create new structure
if os.path.exists(prefs_path):
    try:
        with open(prefs_path, 'r', encoding='utf-8') as f:
            prefs = json.load(f)
    except:
        prefs = {}
else:
    prefs = {}

# Ensure autofill structure exists
if 'autofill' not in prefs:
    prefs['autofill'] = {}

if 'profile_address_data_manager' not in prefs['autofill']:
    prefs['autofill']['profile_address_data_manager'] = {}

if 'profiles' not in prefs['autofill']['profile_address_data_manager']:
    prefs['autofill']['profile_address_data_manager']['profiles'] = []

# Get current timestamp (Chrome uses microseconds since Windows epoch)
# For simplicity, use a fixed timestamp
timestamp = 13360799510000000

# Create the old address entry
old_address = {
    "guid": old_guid,
    "name": "John Smith",
    "street-address": "742 Evergreen Terrace",
    "city": "Springfield",
    "state": "IL",
    "zip": "62701",
    "country": "US",
    "phone": "555-0100",
    "use_count": 5,
    "use_date": timestamp,
    "modification_date": timestamp
}

# Remove any existing old address (in case of re-runs)
profiles = prefs['autofill']['profile_address_data_manager']['profiles']
profiles = [p for p in profiles if '742 Evergreen Terrace' not in p.get('street-address', '')]

# Add old address
profiles.append(old_address)
prefs['autofill']['profile_address_data_manager']['profiles'] = profiles

# Ensure other required Chrome preference fields exist
if 'profile' not in prefs:
    prefs['profile'] = {}

# Write back to Preferences file
with open(prefs_path, 'w', encoding='utf-8') as f:
    json.dump(prefs, f, indent=2)

print(f"✓ Old address injected successfully: {old_address['street-address']}")
print(f"  GUID: {old_guid}")
print(f"  Total addresses in profile: {len(profiles)}")

PYTHON_SCRIPT

# Set ownership of profile directory
chown -R ga:ga "$CHROME_PROFILE" || true

echo "✓ Old address pre-populated in Chrome autofill data"

# Now start Chrome
echo "Starting Chrome for task..."

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

# Navigate to the starting URL (Google homepage)
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
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Verify old address was injected
echo "Verifying old address in Preferences..."
if grep -q "742 Evergreen Terrace" "$CHROME_PROFILE/Preferences" 2>/dev/null; then
    echo "✓ Old address verified in Preferences file"
else
    echo "⚠ Warning: Old address may not be in Preferences"
fi

echo "=== Setup complete ==="
echo ""
echo "Chrome is ready. Starting state:"
echo "  - Old address: 742 Evergreen Terrace, Springfield, IL 62701"
echo ""
echo "Agent should:"
echo "  1. Navigate to chrome://settings (Ctrl+, or Menu > Settings)"
echo "  2. Go to 'Autofill and passwords' or search for 'addresses'"
echo "  3. Click 'Addresses and more'"
echo "  4. Find and delete '742 Evergreen Terrace' address"
echo "  5. Click 'Add' to create new address"
echo "  6. Enter new address details:"
echo "       Name: Alex Johnson"
echo "       Street: 1640 Riverside Drive, Apt 3B"
echo "       City: Metropolis"
echo "       State: NY"
echo "       ZIP: 10001"
echo "  7. Save the new address"