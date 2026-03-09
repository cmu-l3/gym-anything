#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Tab Audio Control Task Export: tab_audio_mute@1 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# IMPORTANT: Do NOT close Chrome - we need to verify live tab audio states
# The mute state is only available while Chrome is running

# Capture all tabs via CDP with detailed information
echo "Capturing detailed tab information via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_all_tabs_raw.json 2>/dev/null; then
    echo "✓ Successfully captured raw CDP tab information"
    
    # Filter to only page-type tabs and extract relevant fields
    jq '[.[] | select(.type == "page") | {
        id: .id,
        url: .url,
        title: .title,
        type: .type,
        audible: .audible // false,
        muted: .muted // false
    }]' /tmp/chrome_all_tabs_raw.json > /tmp/chrome_tabs_audio_state.json
    
    TAB_COUNT=$(jq 'length' /tmp/chrome_tabs_audio_state.json)
    echo "✓ Found $TAB_COUNT page tab(s)"
    
    # Create human-readable summary
    echo "" > /tmp/tab_audio_summary.txt
    echo "Tab Audio State Summary" >> /tmp/tab_audio_summary.txt
    echo "======================" >> /tmp/tab_audio_summary.txt
    jq -r '.[] | "URL: \(.url)\nTitle: \(.title)\nAudible: \(.audible)\nMuted: \(.muted)\n---"' /tmp/chrome_tabs_audio_state.json >> /tmp/tab_audio_summary.txt
    
    echo ""
    echo "Tab states:"
    cat /tmp/tab_audio_summary.txt
else
    echo "⚠ Warning: Failed to capture CDP information"
    # Create empty files to prevent verification errors
    echo "[]" > /tmp/chrome_tabs_audio_state.json
    touch /tmp/tab_audio_summary.txt
fi

# Also capture browser history for supplementary verification
echo "Capturing browser history..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/History" ]; then
    cp "$CHROME_PROFILE/History" /tmp/chrome_history.db 2>/dev/null || true
else
    # Try alternative profile location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/History" ]; then
        cp "$ALT_PROFILE/History" /tmp/chrome_history.db 2>/dev/null || true
    fi
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/audio_task_final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/audio_task_final_screenshot.png"
fi

# Verify files were created
if [ -f "/tmp/chrome_tabs_audio_state.json" ]; then
    FILE_SIZE=$(stat -f%z "/tmp/chrome_tabs_audio_state.json" 2>/dev/null || stat -c%s "/tmp/chrome_tabs_audio_state.json" 2>/dev/null || echo "0")
    echo "✓ Tab state file created: $FILE_SIZE bytes"
else
    echo "⚠ Warning: Tab state file not created"
fi

echo "✅ Export complete - Chrome remains running for verification"