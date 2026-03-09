#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Night Mode Audio Result ==="

USER_HOME="/home/ga"
CONFIG_DIR="$USER_HOME/.config/vlc"
VLC_RC="$CONFIG_DIR/vlcrc"
EXPORT_DIR="/tmp"

# Close VLC to ensure config is saved
if is_vlc_running; then
    echo "[INFO] Closing VLC to save configuration..."
    
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    
    # Close gracefully
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "[WARN] VLC still running, force closing..."
        kill_vlc ga
        sleep 1
    fi
fi

# Give VLC time to write config
sleep 1

# Parse VLC configuration for audio filter settings
echo "[INFO] Reading VLC configuration..."

AUDIO_FILTER=""
COMPRESSOR_ENABLED="false"
NORMALIZER_ENABLED="false"
CONFIG_FOUND="false"

if [[ -f "$VLC_RC" ]]; then
    CONFIG_FOUND="true"
    echo "[INFO] VLC config found: $VLC_RC"
    
    # Extract audio-filter setting
    if grep -q "^audio-filter=" "$VLC_RC"; then
        AUDIO_FILTER=$(grep "^audio-filter=" "$VLC_RC" | cut -d= -f2 | head -1)
        echo "[INFO] audio-filter setting: '$AUDIO_FILTER'"
    fi
    
    # Check for compressor in audio-filter
    if echo "$AUDIO_FILTER" | grep -qi "compressor"; then
        COMPRESSOR_ENABLED="true"
        echo "[INFO] ✓ Compressor found in audio-filter"
    fi
    
    # Check for normalizer in audio-filter (various possible names)
    if echo "$AUDIO_FILTER" | grep -Ei "(norm|normaliz)"; then
        NORMALIZER_ENABLED="true"
        echo "[INFO] ✓ Normalizer found in audio-filter"
    fi
    
    # Alternative check: look for individual module settings
    if [[ "$COMPRESSOR_ENABLED" == "false" ]]; then
        if grep -q "compressor" "$VLC_RC"; then
            COMPRESSOR_ENABLED="true"
            echo "[INFO] ✓ Compressor config found"
        fi
    fi
    
    if [[ "$NORMALIZER_ENABLED" == "false" ]]; then
        if grep -Ei "(norm-|normalizer)" "$VLC_RC" | grep -v "^#" > /dev/null; then
            NORMALIZER_ENABLED="true"
            echo "[INFO] ✓ Normalizer config found"
        fi
    fi
    
    # Copy vlcrc for detailed verification
    cp "$VLC_RC" "$EXPORT_DIR/vlcrc_export.txt"
    
else
    echo "[WARN] VLC config file not found: $VLC_RC"
fi

# Write JSON result file for verifier
cat > "$EXPORT_DIR/vlc_night_mode_result.json" <<EOF
{
    "audio_filter": "$AUDIO_FILTER",
    "compressor_enabled": $COMPRESSOR_ENABLED,
    "normalizer_enabled": $NORMALIZER_ENABLED,
    "config_found": $CONFIG_FOUND,
    "config_path": "$VLC_RC"
}
EOF

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  EXPORT RESULTS"
echo "════════════════════════════════════════════════════════════"
cat "$EXPORT_DIR/vlc_night_mode_result.json"
echo "════════════════════════════════════════════════════════════"
echo ""

# Create completion marker
echo "$(date)" > "$EXPORT_DIR/vlc_night_mode_completed.txt"
echo "Night mode audio configuration task completed" >> "$EXPORT_DIR/vlc_night_mode_completed.txt"
echo "Compressor: $COMPRESSOR_ENABLED" >> "$EXPORT_DIR/vlc_night_mode_completed.txt"
echo "Normalizer: $NORMALIZER_ENABLED" >> "$EXPORT_DIR/vlc_night_mode_completed.txt"

echo "[SUCCESS] Export complete"
echo "[INFO] Result file: $EXPORT_DIR/vlc_night_mode_result.json"
echo "[INFO] Completion marker: $EXPORT_DIR/vlc_night_mode_completed.txt"

exit 0