#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Apply Effects Result ==="

# Query VLC RC interface for effects settings
EFFECTS_FOUND="{}"
EFFECTS_COUNT=0
RUNTIME_CAPTURED="false"

if is_vlc_running; then
    echo "Querying VLC RC interface for effects..."

    # Query status from RC interface which includes video filter info
    RC_OUTPUT=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")

    if [ -n "$RC_OUTPUT" ]; then
        # Parse RC output for video effects/filters
        EFFECTS_JSON=""

        # Check for brightness/contrast settings
        BRIGHTNESS=$(echo "$RC_OUTPUT" | grep -oP 'brightness:\s*\K[\d.]+' || echo "")
        CONTRAST=$(echo "$RC_OUTPUT" | grep -oP 'contrast:\s*\K[\d.]+' || echo "")
        SATURATION=$(echo "$RC_OUTPUT" | grep -oP 'saturation:\s*\K[\d.]+' || echo "")
        GAMMA=$(echo "$RC_OUTPUT" | grep -oP 'gamma:\s*\K[\d.]+' || echo "")

        # Build effects JSON
        if [ -n "$BRIGHTNESS" ]; then
            EFFECTS_JSON="${EFFECTS_JSON}\"brightness\": \"${BRIGHTNESS}\""
            EFFECTS_COUNT=$((EFFECTS_COUNT + 1))
        fi

        if [ -n "$CONTRAST" ]; then
            [ -n "$EFFECTS_JSON" ] && EFFECTS_JSON="${EFFECTS_JSON},"
            EFFECTS_JSON="${EFFECTS_JSON}\"contrast\": \"${CONTRAST}\""
            EFFECTS_COUNT=$((EFFECTS_COUNT + 1))
        fi

        if [ -n "$SATURATION" ]; then
            [ -n "$EFFECTS_JSON" ] && EFFECTS_JSON="${EFFECTS_JSON},"
            EFFECTS_JSON="${EFFECTS_JSON}\"saturation\": \"${SATURATION}\""
            EFFECTS_COUNT=$((EFFECTS_COUNT + 1))
        fi

        if [ -n "$GAMMA" ]; then
            [ -n "$EFFECTS_JSON" ] && EFFECTS_JSON="${EFFECTS_JSON},"
            EFFECTS_JSON="${EFFECTS_JSON}\"gamma\": \"${GAMMA}\""
            EFFECTS_COUNT=$((EFFECTS_COUNT + 1))
        fi

        if [ -n "$EFFECTS_JSON" ]; then
            EFFECTS_FOUND="{${EFFECTS_JSON}}"
            RUNTIME_CAPTURED="true"
            echo "✅ Captured effects from VLC RC: $EFFECTS_COUNT effects"
        else
            echo "⚠️ No effects found in RC output"
        fi
    else
        echo "⚠️ Could not query RC interface"
    fi
fi

# Close VLC
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Fallback: Read VLC config if RC query failed
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ "$RUNTIME_CAPTURED" = "false" ] && [ -f "$VLC_RC" ]; then
    echo "Fallback to reading effects from vlcrc..."
    EFFECTS_JSON=""

    for effect in brightness contrast saturation gamma hue adjust-enabled video-filter; do
        if grep -q "^${effect}=" "$VLC_RC"; then
            VALUE=$(grep "^${effect}=" "$VLC_RC" | cut -d= -f2 | head -1)
            [ -n "$EFFECTS_JSON" ] && EFFECTS_JSON="${EFFECTS_JSON},"
            EFFECTS_JSON="${EFFECTS_JSON}\"${effect}\": \"${VALUE}\""
            EFFECTS_COUNT=$((EFFECTS_COUNT + 1))
        fi
    done

    if [ -n "$EFFECTS_JSON" ]; then
        EFFECTS_FOUND="{${EFFECTS_JSON}}"
    fi
    echo "Found $EFFECTS_COUNT effect settings from vlcrc"
fi

# Write JSON result file
cat > /tmp/vlc_effects_result.json <<EOF
{
    "effects": $EFFECTS_FOUND,
    "effects_count": $EFFECTS_COUNT,
    "runtime_captured": $RUNTIME_CAPTURED,
    "source": "$([ "$RUNTIME_CAPTURED" = "true" ] && echo "rc" || echo "vlcrc")"
}
EOF

echo "✅ Effects result saved to /tmp/vlc_effects_result.json"
cat /tmp/vlc_effects_result.json

echo "$(date)" > /tmp/vlc_effects_completed.txt

echo "=== Export Complete ==="
