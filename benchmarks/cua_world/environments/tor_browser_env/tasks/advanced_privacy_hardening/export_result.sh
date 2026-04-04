#!/bin/bash
# export_result.sh for advanced_privacy_hardening task
# Reads prefs.js to check all required privacy hardening settings

echo "=== Exporting advanced_privacy_hardening results ==="

TASK_NAME="advanced_privacy_hardening"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

# Find Tor Browser profile
PROFILE_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Browser/profile.default"
do
    if [ -d "$candidate" ]; then
        PROFILE_DIR="$candidate"
        echo "Using profile: $PROFILE_DIR"
        break
    fi
done

PREFS_FILE="$PROFILE_DIR/prefs.js"

# Check 1: Security level (slider value = 4 for Safest)
SECURITY_SLIDER=1
SECURITY_LEVEL="standard"
if [ -f "$PREFS_FILE" ]; then
    SLIDER_VAL=$(grep "browser.security_level.security_slider" "$PREFS_FILE" 2>/dev/null | grep -oP '[0-9]+' | tail -1 || echo "1")
    if [ -n "$SLIDER_VAL" ]; then
        SECURITY_SLIDER=$SLIDER_VAL
    fi
    case "$SECURITY_SLIDER" in
        1) SECURITY_LEVEL="standard" ;;
        2) SECURITY_LEVEL="safer" ;;
        4) SECURITY_LEVEL="safest" ;;
        *) SECURITY_LEVEL="unknown" ;;
    esac
fi
echo "Security slider: $SECURITY_SLIDER ($SECURITY_LEVEL)"

# Check 2: HTTPS-Only Mode
HTTPS_ONLY_ENABLED="false"
if [ -f "$PREFS_FILE" ]; then
    if grep -q 'dom\.security\.https_only_mode.*true' "$PREFS_FILE" 2>/dev/null; then
        HTTPS_ONLY_ENABLED="true"
    fi
fi
echo "HTTPS-Only Mode: $HTTPS_ONLY_ENABLED"

# Check 3: network.prefetch-next = false
PREFETCH_DISABLED="false"
if [ -f "$PREFS_FILE" ]; then
    if grep -q 'network\.prefetch-next.*false' "$PREFS_FILE" 2>/dev/null; then
        PREFETCH_DISABLED="true"
    fi
fi
echo "Prefetch disabled: $PREFETCH_DISABLED"

# Check 4: browser.sessionstore.privacy_level = 2
SESSIONSTORE_LEVEL=-1
if [ -f "$PREFS_FILE" ]; then
    SS_VAL=$(grep "browser.sessionstore.privacy_level" "$PREFS_FILE" 2>/dev/null | grep -oP '[0-9]+' | tail -1 || echo "-1")
    if [ -n "$SS_VAL" ]; then
        SESSIONSTORE_LEVEL=$SS_VAL
    fi
fi
echo "Sessionstore privacy level: $SESSIONSTORE_LEVEL"

# Check 5: network.http.speculative-parallel-limit = 0
SPECULATIVE_LIMIT=-1
if [ -f "$PREFS_FILE" ]; then
    SP_VAL=$(grep "network.http.speculative-parallel-limit" "$PREFS_FILE" 2>/dev/null | grep -oP '[0-9]+' | tail -1 || echo "-1")
    if [ -n "$SP_VAL" ]; then
        SPECULATIVE_LIMIT=$SP_VAL
    fi
fi
echo "Speculative parallel limit: $SPECULATIVE_LIMIT"

# Check 6: Never remember history
# This can be stored as places.history.enabled=false OR browser.privatebrowsing.autostart=true
HISTORY_NEVER_SAVED="false"
if [ -f "$PREFS_FILE" ]; then
    if grep -q 'places\.history\.enabled.*false' "$PREFS_FILE" 2>/dev/null; then
        HISTORY_NEVER_SAVED="true"
    elif grep -q 'browser\.privatebrowsing\.autostart.*true' "$PREFS_FILE" 2>/dev/null; then
        HISTORY_NEVER_SAVED="true"
    fi
fi
echo "History never saved: $HISTORY_NEVER_SAVED"

# Check if Tor Browser is still running
TOR_RUNNING="false"
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" > /dev/null; then
    TOR_RUNNING="true"
fi

# Profile file exists check
PREFS_EXISTS="false"
if [ -f "$PREFS_FILE" ]; then
    PREFS_EXISTS="true"
fi

# Write result JSON
cat > /tmp/${TASK_NAME}_result.json << EOF
{
    "task": "$TASK_NAME",
    "prefs_file_exists": $PREFS_EXISTS,
    "security_slider": $SECURITY_SLIDER,
    "security_level": "$SECURITY_LEVEL",
    "https_only_enabled": $HTTPS_ONLY_ENABLED,
    "prefetch_disabled": $PREFETCH_DISABLED,
    "sessionstore_privacy_level": $SESSIONSTORE_LEVEL,
    "speculative_parallel_limit": $SPECULATIVE_LIMIT,
    "history_never_saved": $HISTORY_NEVER_SAVED,
    "tor_browser_running": $TOR_RUNNING,
    "task_start": $(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/${TASK_NAME}_result.json
