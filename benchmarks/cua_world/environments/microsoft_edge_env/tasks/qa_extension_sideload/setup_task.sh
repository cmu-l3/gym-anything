#!/bin/bash
set -e

echo "=== Setting up QA Extension Sideload Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# 1. Kill existing Edge instances
echo "Killing Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# 2. Create the dummy extension
EXT_DIR="/home/ga/Documents/BugReporter_v2"
mkdir -p "$EXT_DIR"

# Create manifest.json (Manifest V3)
cat > "$EXT_DIR/manifest.json" <<EOF
{
  "name": "Bug Reporter Internal",
  "version": "2.1.0",
  "manifest_version": 3,
  "description": "Internal tool for logging QA defects.",
  "action": {
    "default_popup": "popup.html",
    "default_icon": "icon.png"
  },
  "permissions": ["activeTab"]
}
EOF

# Create popup.html
cat > "$EXT_DIR/popup.html" <<EOF
<!DOCTYPE html>
<html>
<body style="width: 200px; padding: 10px;">
  <h3>Bug Reporter</h3>
  <p>Status: Ready</p>
  <button>Log Defect</button>
</body>
</html>
EOF

# Create a red icon using ImageMagick (convert) or Python
# Environment has imagemagick installed per spec
if command -v convert >/dev/null 2>&1; then
    convert -size 48x48 xc:red "$EXT_DIR/icon.png"
else
    # Python fallback
    python3 -c "from PIL import Image; Image.new('RGB', (48, 48), color='red').save('$EXT_DIR/icon.png')"
fi

chown -R ga:ga "/home/ga/Documents"

# 3. Ensure clean initial state for Preferences (no dev mode, no extensions)
PREFS_DIR="/home/ga/.config/microsoft-edge/Default"
mkdir -p "$PREFS_DIR"
PREFS_FILE="$PREFS_DIR/Preferences"

if [ -f "$PREFS_FILE" ]; then
    # Reset extensions settings in Preferences
    python3 <<PYEOF
import json, os
try:
    with open('$PREFS_FILE', 'r') as f:
        data = json.load(f)
    
    # Disable dev mode
    if 'extensions' in data and 'ui' in data['extensions']:
        data['extensions']['ui']['developer_mode'] = False
    
    # Remove our extension if present (cleanup from previous runs)
    if 'extensions' in data and 'settings' in data['extensions']:
        keys_to_remove = []
        for k, v in data['extensions']['settings'].items():
            if v.get('path') == '$EXT_DIR':
                keys_to_remove.append(k)
        for k in keys_to_remove:
            del data['extensions']['settings'][k]

    with open('$PREFS_FILE', 'w') as f:
        json.dump(data, f)
except Exception as e:
    print(f"Error resetting prefs: {e}")
PYEOF
    chown ga:ga "$PREFS_FILE"
fi

# 4. Launch Edge
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    about:blank > /tmp/edge.log 2>&1 &"

# Wait for Edge window
TIMEOUT=30
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "edge|microsoft"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# Maximize
DISPLAY=:1 wmctrl -r "Microsoft Edge" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="