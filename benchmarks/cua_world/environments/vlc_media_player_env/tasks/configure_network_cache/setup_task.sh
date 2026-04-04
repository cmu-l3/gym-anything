#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure Network Cache Task ==="

# Kill any existing VLC instances
kill_vlc ga

sleep 1

# Ensure VLC config directory exists
VLC_CONFIG_DIR="/home/ga/.config/vlc"
VLC_RC="${VLC_CONFIG_DIR}/vlcrc"

mkdir -p "${VLC_CONFIG_DIR}"

# Reset VLC config to defaults with LOW cache values (simulating the problem state)
echo "Resetting VLC configuration to default (low) cache values..."
cat > "${VLC_RC}" << 'EOF'
# VLC preferences - Default configuration with low cache
[core]
# Default cache values (insufficient for network files)
network-caching=300
file-caching=300
disc-caching=300
live-caching=300

# Other default settings
audio-volume=256
loop=0
repeat=0

[qt]
qt-privacy-ask=0
qt-continue=0
qt-start-minimized=0

[video]
snapshot-path=/home/ga/Pictures/vlc
snapshot-format=png
video-on-top=0
EOF

chown -R ga:ga "${VLC_CONFIG_DIR}"
chmod 644 "${VLC_RC}"

echo "✅ VLC configuration reset to default (low) cache values"
echo "   network-caching=300 (insufficient for smooth network playback)"

# Create simulated NAS directory structure for context
MEDIA_DIR="/home/ga/Videos"
NAS_DIR="${MEDIA_DIR}/nas_mount"
mkdir -p "${NAS_DIR}"

# Create a README explaining the scenario
cat > "${NAS_DIR}/README.txt" << 'EOF'
SCENARIO: Network Attached Storage (NAS) Mount Point
====================================================

This directory simulates a network-attached storage (NAS) drive containing
high-bitrate 4K video files. 

PROBLEM:
When playing files from this location, VLC stutters constantly because
the default network cache (300ms) is too small to buffer enough data.

SOLUTION:
Increase VLC's network cache buffer in Advanced Preferences:
- Tools → Preferences → Show settings: All
- Input / Codecs → Advanced
- Network caching (ms): Set to 1500-3000ms

WHY THIS MATTERS:
Proper cache configuration eliminates playback stuttering for:
- High-bitrate 4K/8K video from NAS drives
- Network shares (SMB/CIFS, NFS)
- Streaming from personal media servers
- Any network-based media playback
EOF

chown -R ga:ga "${NAS_DIR}"

# Create a simulated high-bitrate video file (for context/realism)
# Using a shorter duration to save space and time
if [ ! -f "${NAS_DIR}/4k_documentary.mkv" ]; then
    echo "Creating test video file (simulating high-bitrate NAS content)..."
    cd "${NAS_DIR}"
    
    # Generate a short test video with high bitrate
    ffmpeg -f lavfi -i testsrc=duration=10:size=1920x1080:rate=30 \
           -f lavfi -i sine=frequency=1000:duration=10 \
           -c:v libx264 -b:v 15M -c:a aac -b:a 192k \
           4k_documentary.mkv -y 2>/dev/null || {
        echo "⚠️  Warning: Could not create test video (ffmpeg may not be available)"
    }
    
    chown ga:ga 4k_documentary.mkv 2>/dev/null || true
fi

# Create desktop instruction file for the agent
cat > "/home/ga/Desktop/NETWORK_CACHE_TASK.txt" << 'EOF'
═══════════════════════════════════════════════════════════════
  VLC TASK: Configure Network Cache for Smooth Playback
═══════════════════════════════════════════════════════════════

PROBLEM:
--------
Video playback from network drives is stuttering constantly.
Current VLC cache setting: 300ms (default - TOO LOW)

SYMPTOMS:
- Video freezes every 3-5 seconds
- Playback jumps forward after freeze
- Audio may skip or desync
- Happens with high-bitrate files from NAS/network shares

YOUR TASK:
----------
Configure VLC to increase the network cache buffer.

STEP-BY-STEP SOLUTION:
----------------------
1. Open VLC Preferences
   - Menu: Tools → Preferences
   - Or press: Ctrl+P

2. Switch to Advanced Settings
   - At the BOTTOM LEFT of preferences window
   - Click the "All" radio button (not "Simple")
   - This reveals all advanced options

3. Navigate to Network Caching Settings
   - In the left sidebar, expand: "Input / Codecs"
   - Click on: "Advanced" (under Input / Codecs)
   - Look for: "Caching" section

4. Modify Network Caching Value
   - Find parameter: "Network caching (ms)"
     (May also be labeled "Caching value for network resources")
   - Current value: 300
   - Change to: 2000 (recommended)
   - Acceptable range: 1500-3000ms

5. Save Settings
   - Click "Save" button at bottom
   - Settings will persist in ~/.config/vlc/vlcrc

VERIFICATION:
-------------
After saving, the network-caching value in VLC config should be
increased to 1500-3000ms for optimal performance.

WHY THESE VALUES?
-----------------
- 300ms (default): Too small for high-bitrate network files
- 1500-3000ms: Optimal balance (smooth playback, minimal delay)
- 5000ms+: Works but causes longer initial buffering
- 10000ms+: Excessive, causes very long startup delays

TECHNICAL DETAILS:
------------------
Cache buffer stores video data ahead of current playback position.
When network/drive is momentarily slow, VLC plays from buffer instead
of freezing. Larger cache = more tolerance for network delays.

Good luck!
EOF

chown ga:ga "/home/ga/Desktop/NETWORK_CACHE_TASK.txt"

# Launch VLC (empty, so agent can navigate to preferences)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_network_cache_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_network_cache_task.log 2>/dev/null || true
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    echo "✅ VLC window focused (ID: $wid)"
fi

sleep 1

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Configure Network Cache Task Setup Complete"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "📋 TASK SUMMARY:"
echo "   • VLC is running with default (low) cache settings"
echo "   • Current network-caching: 300ms (insufficient)"
echo "   • Target: Increase to 1500-3000ms (optimal range)"
echo ""
echo "💡 AGENT INSTRUCTIONS:"
echo "   1. Open Preferences: Tools → Preferences (Ctrl+P)"
echo "   2. Switch to 'All' settings (bottom-left radio button)"
echo "   3. Navigate: Input / Codecs → Advanced"
echo "   4. Find: 'Network caching (ms)' parameter"
echo "   5. Change value from 300 to 2000 (or 1500-3000 range)"
echo "   6. Click 'Save' to persist settings"
echo ""
echo "📁 Config file: ${VLC_RC}"
echo "📖 Instructions: /home/ga/Desktop/NETWORK_CACHE_TASK.txt"
echo ""
echo "═══════════════════════════════════════════════════════════════"