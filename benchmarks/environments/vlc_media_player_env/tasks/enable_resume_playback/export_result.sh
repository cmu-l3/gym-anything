#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Enable Resume Playback Result ==="

# Initialize result variables
RESUME_ENABLED="false"
RESUME_VALUE="0"
CONFIG_FOUND="false"
TEST_DOCUMENTED="false"

# Check VLC configuration file
VLC_CONFIG="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_CONFIG" ]; then
    CONFIG_FOUND="true"
    echo "✅ VLC config file found"
    
    # Extract qt-continue setting
    if grep -q "^qt-continue=" "$VLC_CONFIG"; then
        RESUME_VALUE=$(grep "^qt-continue=" "$VLC_CONFIG" | cut -d= -f2 | head -1)
        echo "Found qt-continue setting: $RESUME_VALUE"
        
        # Check if resume is enabled (1 = ask, 2 = always)
        if [ "$RESUME_VALUE" = "1" ] || [ "$RESUME_VALUE" = "2" ]; then
            RESUME_ENABLED="true"
            echo "✅ Resume playback is ENABLED (qt-continue=$RESUME_VALUE)"
        else
            echo "⚠️ Resume playback is DISABLED (qt-continue=$RESUME_VALUE)"
        fi
    else
        echo "⚠️ qt-continue setting not found in config"
        # Check alternative settings
        if grep -qi "qt.*continue" "$VLC_CONFIG" || grep -qi "resume" "$VLC_CONFIG"; then
            echo "Found resume-related settings in config"
        fi
    fi
    
    # Copy config for verification
    cp "$VLC_CONFIG" /tmp/vlc_resume_vlcrc.txt
    echo "✅ Copied VLC config to /tmp/vlc_resume_vlcrc.txt"
else
    echo "⚠️ VLC config file not found at $VLC_CONFIG"
fi

# Check for optional verification file (if agent documented test)
VERIFICATION_FILE="/home/ga/resume_verification.txt"
if [ -f "$VERIFICATION_FILE" ]; then
    TEST_DOCUMENTED="true"
    echo "✅ Found verification file created by agent"
    cp "$VERIFICATION_FILE" /tmp/vlc_resume_verification.txt
    cat "$VERIFICATION_FILE"
else
    echo "ℹ️ Verification file not found (optional)"
fi

# Check recent VLC usage (media library might show resume info)
if [ -f "/home/ga/.local/share/vlc/ml.xspf" ]; then
    cp /home/ga/.local/share/vlc/ml.xspf /tmp/vlc_resume_ml.xspf 2>/dev/null || true
    echo "ℹ️ Copied media library file"
fi

# Check if there's a Qt interface config (alternative location for resume setting)
QT_CONFIG="/home/ga/.config/vlc/vlc-qt-interface.conf"
if [ -f "$QT_CONFIG" ]; then
    cp "$QT_CONFIG" /tmp/vlc_resume_qt_config.txt 2>/dev/null || true
    if grep -qi "continue\|resume" "$QT_CONFIG"; then
        echo "ℹ️ Found resume-related settings in Qt config"
    fi
fi

# Close VLC if still running
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q || true
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        kill_vlc ga
    fi
fi

# Create structured JSON result
cat > /tmp/vlc_resume_result.json <<EOF
{
    "resume_enabled": $RESUME_ENABLED,
    "resume_value": "$RESUME_VALUE",
    "config_found": $CONFIG_FOUND,
    "test_documented": $TEST_DOCUMENTED,
    "config_path": "$VLC_CONFIG",
    "timestamp": "$(date -u +"%Y-%m-%d %H:%M:%S UTC")"
}
EOF

echo ""
echo "✅ Resume playback result saved to /tmp/vlc_resume_result.json"
cat /tmp/vlc_resume_result.json
echo ""

# Create completion marker
echo "$(date)" > /tmp/vlc_resume_completed.txt
echo "Resume enabled: $RESUME_ENABLED (qt-continue=$RESUME_VALUE)" >> /tmp/vlc_resume_completed.txt
echo "Test documented: $TEST_DOCUMENTED" >> /tmp/vlc_resume_completed.txt

echo "=== Export Complete ==="
echo ""
echo "Summary:"
echo "  Resume Enabled: $RESUME_ENABLED"
echo "  Resume Value: $RESUME_VALUE (0=never, 1=ask, 2=always)"
echo "  Config Found: $CONFIG_FOUND"
echo "  Test Documented: $TEST_DOCUMENTED"