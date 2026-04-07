#!/bin/bash
# setup_task.sh - Pre-task hook for configure_auto_translation
# Ensures Edge is clean and translation settings are reset (not set to auto-translate Spanish)

set -e

echo "=== Setting up Configure Auto-Translation Task ==="

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 1. Kill any running Edge instances to release locks on Preferences
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# 2. Cleanup previous outputs
rm -f "/home/ga/Desktop/spain_transport_report.pdf"

# 3. Reset Translation Preferences
# We need to ensure 'es' is NOT in 'always_translate_languages' or 'translate_whitelists'
PREFS_FILE="/home/ga/.config/microsoft-edge/Default/Preferences"
mkdir -p "$(dirname "$PREFS_FILE")"

if [ -f "$PREFS_FILE" ]; then
    echo "Resetting translation preferences..."
    python3 -c "
import json
import os
import sys

try:
    with open('$PREFS_FILE', 'r') as f:
        data = json.load(f)
    
    # Ensure translate section exists
    if 'translate' not in data:
        data['translate'] = {}
    
    # Clear auto-translate lists for Spanish
    # Edge uses 'translate_whitelists': {'es': 'en'} for always translate
    if 'translate_whitelists' in data['translate']:
        whitelists = data['translate']['translate_whitelists']
        if 'es' in whitelists:
            del whitelists['es']
    
    # Also check 'always_translate_languages' (older versions)
    if 'always_translate_languages' in data['translate']:
        langs = data['translate']['always_translate_languages']
        if 'es' in langs:
            langs.remove('es')

    # Ensure translation feature is ENABLED generally, so the prompt appears
    data['translate']['enabled'] = True

    with open('$PREFS_FILE', 'w') as f:
        json.dump(data, f)
    print('Preferences reset successfully')
except Exception as e:
    print(f'Error resetting preferences: {e}', file=sys.stderr)
"
else
    # Create minimal preferences if missing
    echo "Creating minimal preferences..."
    cat > "$PREFS_FILE" << EOF
{
  "translate": {
    "enabled": true,
    "translate_whitelists": {}
  }
}
EOF
fi

# Fix ownership
chown -R ga:ga "/home/ga/.config/microsoft-edge"

# 4. Launch Edge to a blank page
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    about:blank > /tmp/edge_launch.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "edge|microsoft"; then
        echo "Edge window detected"
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Capture initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="