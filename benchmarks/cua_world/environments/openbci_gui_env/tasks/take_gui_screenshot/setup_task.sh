#!/bin/bash
echo "=== Setting up take_gui_screenshot task ==="

source /workspace/utils/openbci_utils.sh || true

# Kill any running instance first
kill_openbci

# Enable Expert Mode via the settings JSON file (avoids UI clicking).
# OpenBCI reads this on startup and activates Expert Mode if set to "ON".
# Create the file if it doesn't exist for robustness.
SETTINGS_FILE="/home/ga/Documents/OpenBCI_GUI/Settings/GuiWideSettings.json"
mkdir -p "$(dirname "$SETTINGS_FILE")"
python3 -c "
import json, os
path = '$SETTINGS_FILE'
if os.path.exists(path):
    with open(path) as f:
        data = json.load(f)
else:
    data = {}
data['expertMode'] = 'ON'
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
print('Expert Mode set to ON in GuiWideSettings.json')
" || echo "Could not update GuiWideSettings.json"

# Remove any pre-existing screenshots to detect NEW ones
rm -f /home/ga/Documents/OpenBCI_GUI/Screenshots/OpenBCI-*.jpg 2>/dev/null || true
rm -f /home/ga/Documents/OpenBCI_GUI/Screenshots/OpenBCI-*.png 2>/dev/null || true

# Record the screenshot count BEFORE task starts (for verification)
mkdir -p /home/ga/Documents/OpenBCI_GUI/Screenshots/
BEFORE_COUNT=$(find /home/ga/Documents/OpenBCI_GUI/Screenshots/ \( -name "OpenBCI-*.jpg" -o -name "OpenBCI-*.png" \) 2>/dev/null | wc -l)
rm -f /tmp/openbci_screenshot_count_before.txt 2>/dev/null || true
echo "$BEFORE_COUNT" > /tmp/openbci_screenshot_count_before.txt
chmod 644 /tmp/openbci_screenshot_count_before.txt 2>/dev/null || true
echo "Screenshots before task: $BEFORE_COUNT"

# Launch OpenBCI GUI and start a Synthetic session with Expert Mode active
launch_openbci_synthetic

echo "=== Task setup complete ==="
echo "GUI is running in Synthetic mode with Expert Mode active (expertMode=ON in settings)"
echo "Agent should click on the data visualization area and press lowercase 'm' to save a screenshot"
echo "Screenshots are saved to ~/Documents/OpenBCI_GUI/Screenshots/ as .jpg files"
