#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Enhance Lecture Audio Result ==="

# Try to query equalizer settings from VLC RC interface
EQUALIZER_RUNTIME=""
RUNTIME_CAPTURED="false"

if is_vlc_running; then
    echo "Querying VLC RC interface for equalizer settings..."

    # VLC RC interface may have aconfig command to query settings
    # Try to get audio filter status
    RC_OUTPUT=$(echo "aconfig" | nc -w 2 localhost 9999 2>/dev/null || echo "")

    if [ -n "$RC_OUTPUT" ]; then
        # Try to extract equalizer information from RC output
        if echo "$RC_OUTPUT" | grep -qi "equalizer"; then
            RUNTIME_CAPTURED="true"
            echo "✅ Equalizer detected as active in VLC runtime"
        fi
    fi

    # Alternative: check status
    STATUS_OUTPUT=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    if [ -n "$STATUS_OUTPUT" ]; then
        if echo "$STATUS_OUTPUT" | grep -qi "equalizer"; then
            RUNTIME_CAPTURED="true"
            echo "✅ Equalizer mentioned in VLC status"
        fi
    fi
fi

# Close VLC gracefully
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Give VLC time to write config
sleep 1

# Copy VLC config file to /tmp for verification
VLC_RC="/home/ga/.config/vlc/vlcrc"
OUTPUT_DIR="/tmp/vlc_equalizer_result_$$"
mkdir -p "$OUTPUT_DIR"

if [ -f "$VLC_RC" ]; then
    cp "$VLC_RC" "$OUTPUT_DIR/vlcrc"
    echo "✅ VLC config copied to $OUTPUT_DIR/vlcrc"
    
    # Extract equalizer-specific settings to separate file for easier parsing
    grep "equalizer" "$VLC_RC" > "$OUTPUT_DIR/equalizer_settings.txt" 2>/dev/null || echo "# No equalizer settings found" > "$OUTPUT_DIR/equalizer_settings.txt"
    
    # Extract audio-filter settings
    grep "audio-filter" "$VLC_RC" >> "$OUTPUT_DIR/equalizer_settings.txt" 2>/dev/null || true
    
    echo "Equalizer settings extracted:"
    cat "$OUTPUT_DIR/equalizer_settings.txt"
else
    echo "⚠️ VLC config file not found at $VLC_RC"
    echo "# Config not found" > "$OUTPUT_DIR/equalizer_settings.txt"
fi

# Copy the main config to standard location for verifier
cp "$OUTPUT_DIR/vlcrc" /tmp/vlc_equalizer_vlcrc 2>/dev/null || echo "# Config not available" > /tmp/vlc_equalizer_vlcrc
cp "$OUTPUT_DIR/equalizer_settings.txt" /tmp/vlc_equalizer_settings.txt

# Create result JSON with metadata
cat > /tmp/vlc_equalizer_result.json <<EOF
{
    "runtime_captured": $RUNTIME_CAPTURED,
    "config_file": "/tmp/vlc_equalizer_vlcrc",
    "settings_file": "/tmp/vlc_equalizer_settings.txt",
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "✅ Equalizer result saved to /tmp/vlc_equalizer_result.json"
cat /tmp/vlc_equalizer_result.json

# Create completion marker
echo "$(date)" > /tmp/vlc_equalizer_completed.txt
echo "Enhance lecture audio task completed" >> /tmp/vlc_equalizer_completed.txt

# Cleanup temporary directory
rm -rf "$OUTPUT_DIR"

echo "=== Export Complete ==="