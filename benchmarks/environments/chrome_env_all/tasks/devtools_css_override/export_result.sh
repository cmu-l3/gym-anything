#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome DevTools CSS Override Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq imagemagick || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create verification directory
VERIFY_DIR="/tmp/devtools_verification"
mkdir -p "$VERIFY_DIR"

# Capture final screenshot
echo "Capturing final screenshot..."
su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/devtools_after.png" 2>/dev/null || true
if [ -f "$VERIFY_DIR/devtools_after.png" ]; then
    echo "✓ Final screenshot saved"
    ls -lh "$VERIFY_DIR/devtools_after.png"
else
    echo "⚠ Warning: Could not capture final screenshot"
fi

# Copy initial screenshot to verification directory
if [ -f "/tmp/devtools_before.png" ]; then
    cp /tmp/devtools_before.png "$VERIFY_DIR/" 2>/dev/null || true
    echo "✓ Initial screenshot copied to verification directory"
fi

# Capture active tab information via CDP
echo "Capturing active tab URL and title via CDP..."
if curl -s http://localhost:9222/json > "$VERIFY_DIR/chrome_tabs.json" 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' "$VERIFY_DIR/chrome_tabs.json")
    ACTIVE_TITLE=$(jq -r '[.[] | select(.type == "page")][0].title // ""' "$VERIFY_DIR/chrome_tabs.json")
    echo "Active URL: $ACTIVE_URL"
    echo "Active Title: $ACTIVE_TITLE"
    echo "$ACTIVE_URL" > "$VERIFY_DIR/final_url.txt"
    echo "$ACTIVE_TITLE" > "$VERIFY_DIR/final_title.txt"
else
    echo "⚠ Warning: Failed to capture CDP information"
    echo "" > "$VERIFY_DIR/final_url.txt"
    echo "" > "$VERIFY_DIR/final_title.txt"
fi

# Try to capture computed styles via CDP (advanced - may require websocket)
# This is optional and may not work in all environments
echo "Attempting to capture element styles..."
# For simplicity, we'll rely on visual verification
# Advanced CDP websocket queries would go here in a production system

# Capture a focused screenshot of just the heading area
echo "Capturing heading region screenshot..."
su - ga -c "DISPLAY=:1 import -window root -crop 800x300+260+340 $VERIFY_DIR/heading_region.png" 2>/dev/null || true
if [ -f "$VERIFY_DIR/heading_region.png" ]; then
    echo "✓ Heading region screenshot saved"
else
    echo "⚠ Could not capture heading region (will use full screenshot)"
fi

# Save timestamp for verification
date +%s > "$VERIFY_DIR/export_timestamp.txt"

# Create a summary file
cat > "$VERIFY_DIR/export_summary.txt" << EOF
DevTools CSS Override Task Export Summary
==========================================
Export timestamp: $(date)
Final URL: $(cat "$VERIFY_DIR/final_url.txt" 2>/dev/null || echo "unknown")
Final title: $(cat "$VERIFY_DIR/final_title.txt" 2>/dev/null || echo "unknown")

Files captured:
- Before screenshot: $([ -f "$VERIFY_DIR/devtools_before.png" ] && echo "✓" || echo "✗")
- After screenshot: $([ -f "$VERIFY_DIR/devtools_after.png" ] && echo "✓" || echo "✗")
- Heading region: $([ -f "$VERIFY_DIR/heading_region.png" ] && echo "✓" || echo "✗")
- CDP data: $([ -f "$VERIFY_DIR/chrome_tabs.json" ] && echo "✓" || echo "✗")
EOF

cat "$VERIFY_DIR/export_summary.txt"

echo "✅ Export complete"
echo "Verification files stored in: $VERIFY_DIR"