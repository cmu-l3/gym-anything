#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Enumerate Codec Support Task ==="

# Kill any existing VLC instances (agent may choose GUI or CLI approach)
kill_vlc ga
sleep 1

# Create output directory structure
echo "Creating output directory..."
mkdir -p /home/ga/Documents/vlc_info
chown -R ga:ga /home/ga/Documents/vlc_info
chmod 755 /home/ga/Documents/vlc_info

# Verify VLC is installed
if ! command -v vlc &> /dev/null; then
    echo "ERROR: VLC not installed"
    exit 1
fi

# Log VLC version for debugging
VLC_VERSION=$(vlc --version 2>&1 | head -1 || echo "Unknown")
echo "VLC version: $VLC_VERSION"
echo "$VLC_VERSION" > /tmp/vlc_version_info.txt

# Verify codec plugin directory exists
CODEC_PLUGIN_DIR="/usr/lib/x86_64-linux-gnu/vlc/plugins/codec"
if [ ! -d "$CODEC_PLUGIN_DIR" ]; then
    echo "⚠️ Standard codec plugin directory not found, checking alternatives..."
    
    # Try alternative paths
    ALT_PATHS=(
        "/usr/lib/vlc/plugins/codec"
        "/usr/local/lib/vlc/plugins/codec"
        "/snap/vlc/current/usr/lib/vlc/plugins/codec"
    )
    
    FOUND_PATH=""
    for path in "${ALT_PATHS[@]}"; do
        if [ -d "$path" ]; then
            FOUND_PATH="$path"
            echo "Found codec plugins at: $path"
            break
        fi
    done
    
    if [ -z "$FOUND_PATH" ]; then
        echo "⚠️ Codec plugin directory not found, but continuing..."
    fi
fi

# Ensure the target file does NOT exist (clean slate)
TARGET_FILE="/home/ga/Documents/vlc_info/codecs_supported.txt"
if [ -f "$TARGET_FILE" ]; then
    echo "Removing existing file: $TARGET_FILE"
    rm -f "$TARGET_FILE"
fi

# Launch a terminal window for the agent (in case they want to use CLI)
echo "Launching terminal for agent..."
su - ga -c "DISPLAY=:1 xfce4-terminal --geometry=100x30+50+50 --working-directory=/home/ga/Documents/vlc_info > /tmp/terminal_launch.log 2>&1 &" || true

# Wait for terminal to appear
sleep 2

# Click on center of screen to select desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 400 click 1" || true
sleep 1

# Focus the terminal window
echo "Focusing terminal..."
TERM_WID=$(su - ga -c "DISPLAY=:1 xdotool search --name 'Terminal' | head -1" || echo "")
if [ -n "$TERM_WID" ]; then
    su - ga -c "DISPLAY=:1 xdotool windowactivate --sync $TERM_WID" || true
    sleep 1
fi

echo "=== Enumerate Codec Support Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  Goal: Extract VLC codec list and save to:"
echo "        /home/ga/Documents/vlc_info/codecs_supported.txt"
echo ""
echo "  Method 1 (CLI - Recommended):"
echo "    vlc --list > /home/ga/Documents/vlc_info/codecs_supported.txt"
echo ""
echo "  Method 2 (CLI - Detailed):"
echo "    vlc --longhelp --advanced > /home/ga/Documents/vlc_info/codecs_supported.txt"
echo ""
echo "  Method 3 (System Inspection):"
echo "    ls -l /usr/lib/x86_64-linux-gnu/vlc/plugins/codec/ > /home/ga/Documents/vlc_info/codecs_supported.txt"
echo ""
echo "  Method 4 (GUI):"
echo "    1. Launch VLC"
echo "    2. Tools → Plugins and Extensions"
echo "    3. Copy codec information to file"
echo ""
echo "  A terminal has been opened at /home/ga/Documents/vlc_info/"