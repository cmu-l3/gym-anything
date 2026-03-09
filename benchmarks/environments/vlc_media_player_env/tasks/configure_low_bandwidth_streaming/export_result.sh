#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Configure Low-Bandwidth Streaming Result ==="

VLC_CONFIG_FILE="/home/ga/.config/vlc/vlcrc"

# Check if config file exists and copy it
if [ -f "$VLC_CONFIG_FILE" ]; then
    echo "✅ VLC config file found"
    cp "$VLC_CONFIG_FILE" /tmp/vlc_network_config.txt
    
    # Extract and display network-caching value
    if grep -q "^network-caching=" "$VLC_CONFIG_FILE"; then
        CACHE_VALUE=$(grep "^network-caching=" "$VLC_CONFIG_FILE" | cut -d= -f2)
        echo "Current network-caching value: ${CACHE_VALUE}ms"
    else
        echo "⚠️ network-caching parameter not found in config"
    fi
    
    # Show relevant config sections for debugging
    echo ""
    echo "=== Relevant Config Sections ==="
    grep -E "^(network-caching|file-caching|live-caching|disc-caching)=" "$VLC_CONFIG_FILE" || echo "No caching parameters found"
    echo "================================"
else
    echo "⚠️ VLC config file not found: $VLC_CONFIG_FILE"
    echo "Settings may not have been saved."
fi

# Close VLC gracefully
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    
    # Close via Ctrl+Q
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Verify VLC closed
    if is_vlc_running; then
        echo "⚠️ VLC still running, forcing kill..."
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date -Iseconds)" > /tmp/vlc_low_bandwidth_completed.txt
echo "Task: configure_low_bandwidth_streaming@1" >> /tmp/vlc_low_bandwidth_completed.txt
echo "Config file: $VLC_CONFIG_FILE" >> /tmp/vlc_low_bandwidth_completed.txt

# Create a JSON result for easier parsing
CACHE_VALUE="0"
PARAM_EXISTS="false"

if [ -f "$VLC_CONFIG_FILE" ]; then
    if grep -q "^network-caching=" "$VLC_CONFIG_FILE"; then
        CACHE_VALUE=$(grep "^network-caching=" "$VLC_CONFIG_FILE" | cut -d= -f2 | head -1)
        PARAM_EXISTS="true"
    fi
fi

cat > /tmp/vlc_network_config_result.json <<EOF
{
    "network_caching_ms": $CACHE_VALUE,
    "parameter_exists": $PARAM_EXISTS,
    "config_file_exists": $([ -f "$VLC_CONFIG_FILE" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "✅ Config exported to /tmp/vlc_network_config.txt"
echo "✅ Result JSON saved to /tmp/vlc_network_config_result.json"
cat /tmp/vlc_network_config_result.json

echo "=== Export Complete ==="