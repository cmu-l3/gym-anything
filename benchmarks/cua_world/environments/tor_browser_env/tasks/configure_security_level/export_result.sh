#!/bin/bash
# export_result.sh - Post-task hook for configure_security_level task
# Exports security settings for verification

echo "=== Exporting configure_security_level task results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# Get initial security level
INITIAL_SECURITY_LEVEL=$(cat /tmp/initial_security_level 2>/dev/null || echo "standard")

# Find Tor Browser profile directory
PROFILE_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Browser/profile.default"
do
    if [ -d "$candidate" ]; then
        PROFILE_DIR="$candidate"
        echo "Using Tor Browser profile: $PROFILE_DIR"
        break
    fi
done

PREFS_FILE="$PROFILE_DIR/prefs.js"

# Initialize result variables
CURRENT_SECURITY_LEVEL="standard"
SECURITY_LEVEL_CHANGED="false"
PREFS_FILE_EXISTS="false"
SECURITY_SLIDER_VALUE=1

if [ -n "$PROFILE_DIR" ] && [ -f "$PREFS_FILE" ]; then
    PREFS_FILE_EXISTS="true"

    # Read current security level from prefs.js
    # Tor Browser uses: browser.security_level.security_slider
    # Values: 1=standard, 2=safer, 4=safest
    SLIDER_VALUE=$(grep -oP 'user_pref\("browser\.security_level\.security_slider"[^)]*,\s*\K[0-9]+' "$PREFS_FILE" 2>/dev/null || echo "")

    if [ -z "$SLIDER_VALUE" ]; then
        # Try alternative pattern
        SLIDER_VALUE=$(grep "browser.security_level.security_slider" "$PREFS_FILE" 2>/dev/null | grep -oP '[0-9]+' | tail -1 || echo "1")
    fi

    if [ -z "$SLIDER_VALUE" ]; then
        SLIDER_VALUE=1
    fi

    SECURITY_SLIDER_VALUE=$SLIDER_VALUE

    case "$SLIDER_VALUE" in
        1) CURRENT_SECURITY_LEVEL="standard" ;;
        2) CURRENT_SECURITY_LEVEL="safer" ;;
        4) CURRENT_SECURITY_LEVEL="safest" ;;
        *) CURRENT_SECURITY_LEVEL="unknown" ;;
    esac

    echo "Current security slider value: $SLIDER_VALUE"
    echo "Current security level: $CURRENT_SECURITY_LEVEL"

    # Check if security level was changed
    if [ "$CURRENT_SECURITY_LEVEL" != "$INITIAL_SECURITY_LEVEL" ]; then
        SECURITY_LEVEL_CHANGED="true"
        echo "Security level was changed from '$INITIAL_SECURITY_LEVEL' to '$CURRENT_SECURITY_LEVEL'"
    else
        echo "Security level was NOT changed (still '$CURRENT_SECURITY_LEVEL')"
    fi

    # Also check for related preferences that change with security level
    # When security increases, these are typically set:
    # - javascript.options.baselinejit = false (safest)
    # - media.peerconnection.enabled = false
    # - svg.disabled = true (safest)

    JAVASCRIPT_RESTRICTED=$(grep -q 'javascript.options.baselinejit.*false' "$PREFS_FILE" 2>/dev/null && echo "true" || echo "false")
    WEBRTC_DISABLED=$(grep -q 'media.peerconnection.enabled.*false' "$PREFS_FILE" 2>/dev/null && echo "true" || echo "false")
    SVG_DISABLED=$(grep -q 'svg.disabled.*true' "$PREFS_FILE" 2>/dev/null && echo "true" || echo "false")
else
    echo "WARNING: prefs.js not found at $PREFS_FILE"
fi

# Check Tor Browser window for visual confirmation
TOR_BROWSER_RUNNING="false"
TOR_WINDOW_TITLE=""
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" > /dev/null; then
    TOR_BROWSER_RUNNING="true"
    TOR_WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | cut -d' ' -f5-)
fi

# Escape special characters for JSON
escape_json() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    echo "$str"
}

TOR_WINDOW_TITLE_ESCAPED=$(escape_json "$TOR_WINDOW_TITLE")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_security_level": "$INITIAL_SECURITY_LEVEL",
    "current_security_level": "$CURRENT_SECURITY_LEVEL",
    "security_slider_value": $SECURITY_SLIDER_VALUE,
    "security_level_changed": $SECURITY_LEVEL_CHANGED,
    "prefs_file_exists": $PREFS_FILE_EXISTS,
    "javascript_restricted": $JAVASCRIPT_RESTRICTED,
    "webrtc_disabled": $WEBRTC_DISABLED,
    "svg_disabled": $SVG_DISABLED,
    "tor_browser_running": $TOR_BROWSER_RUNNING,
    "tor_window_title": "$TOR_WINDOW_TITLE_ESCAPED",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Result exported to /tmp/task_result.json ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="
