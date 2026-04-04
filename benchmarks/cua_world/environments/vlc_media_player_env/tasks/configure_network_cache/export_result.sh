#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Configure Network Cache Result ==="

VLC_RC="/home/ga/.config/vlc/vlcrc"
OUTPUT_DIR="/tmp/task_output"

mkdir -p "${OUTPUT_DIR}"

# Log current state
echo "Checking VLC configuration state..."

# Copy VLC configuration file for verification
if [ -f "${VLC_RC}" ]; then
    cp "${VLC_RC}" "${OUTPUT_DIR}/vlcrc"
    echo "✅ VLC config copied: ${OUTPUT_DIR}/vlcrc"
    
    # Log the current network-caching value
    if grep -q "network-caching=" "${VLC_RC}"; then
        CACHE_VALUE=$(grep "^network-caching=" "${VLC_RC}" | cut -d= -f2 | head -1)
        echo "   network-caching value: ${CACHE_VALUE}ms"
    else
        echo "   ⚠️  network-caching parameter not found in config"
    fi
else
    echo "⚠️  WARNING: VLC config not found at ${VLC_RC}"
    # Create empty file so verification doesn't fail on copy
    touch "${OUTPUT_DIR}/vlcrc"
fi

# Export task metadata for verification
cat > "${OUTPUT_DIR}/task_info.json" << EOF
{
    "task_id": "configure_network_cache@1",
    "timestamp": "$(date -Iseconds)",
    "config_file": "${VLC_RC}",
    "config_exists": $([ -f "${VLC_RC}" ] && echo "true" || echo "false"),
    "expected_parameter": "network-caching",
    "default_value": 300,
    "optimal_range": [1500, 3000],
    "acceptable_range": [800, 5000]
}
EOF

echo "✅ Task metadata exported"

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
        echo "Force closing VLC..."
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date)" > "${OUTPUT_DIR}/vlc_network_cache_completed.txt"
echo "Task: configure_network_cache@1" >> "${OUTPUT_DIR}/vlc_network_cache_completed.txt"

# Log final config state for debugging
if [ -f "${OUTPUT_DIR}/vlcrc" ]; then
    echo ""
    echo "═══════════════════════════════════════════════"
    echo "  Network Cache Configuration Summary"
    echo "═══════════════════════════════════════════════"
    
    if grep -q "network-caching=" "${OUTPUT_DIR}/vlcrc"; then
        echo "✅ network-caching parameter found"
        grep "network-caching=" "${OUTPUT_DIR}/vlcrc" | head -1
    else
        echo "⚠️  network-caching parameter NOT found"
    fi
    
    echo "═══════════════════════════════════════════════"
fi

echo ""
echo "✅ Export complete: Task output saved to ${OUTPUT_DIR}"
echo ""