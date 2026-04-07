#!/bin/bash
set -euo pipefail

echo "=== Setting up CoppeliaSim environment ==="

# Source environment variables
source /etc/profile.d/coppeliasim.sh 2>/dev/null || true
export DISPLAY=:1
export LIBGL_ALWAYS_SOFTWARE=1

# Wait for desktop to be ready
echo "Waiting for desktop..."
for i in $(seq 1 30); do
    if DISPLAY=:1 xdpyinfo >/dev/null 2>&1; then
        echo "Desktop ready after ${i}s"
        break
    fi
    sleep 1
done

# Set screen resolution
DISPLAY=:1 xrandr --output default --mode 1920x1080 2>/dev/null || \
DISPLAY=:1 xrandr -s 1920x1080 2>/dev/null || true

# Create workspace directories
mkdir -p /home/ga/Documents/CoppeliaSim/scenes
mkdir -p /home/ga/Documents/CoppeliaSim/exports
mkdir -p /home/ga/Documents/CoppeliaSim/scripts
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Copy some demo scenes to user workspace for easy access
if [ -d /opt/CoppeliaSim/scenes ]; then
    cp /opt/CoppeliaSim/scenes/messaging*.ttt /home/ga/Documents/CoppeliaSim/scenes/ 2>/dev/null || true
    cp /opt/CoppeliaSim/scenes/robot*.ttt /home/ga/Documents/CoppeliaSim/scenes/ 2>/dev/null || true
    cp /opt/CoppeliaSim/scenes/*pick*.ttt /home/ga/Documents/CoppeliaSim/scenes/ 2>/dev/null || true
    cp /opt/CoppeliaSim/scenes/*ik*.ttt /home/ga/Documents/CoppeliaSim/scenes/ 2>/dev/null || true
    cp /opt/CoppeliaSim/scenes/*motion*.ttt /home/ga/Documents/CoppeliaSim/scenes/ 2>/dev/null || true
    chown -R ga:ga /home/ga/Documents/CoppeliaSim/scenes/
fi

# Suppress first-run dialogs by writing config BEFORE first launch
# CoppeliaSim uses TWO config locations:
# 1. ~/.CoppeliaSim/usrset.txt (the real one CoppeliaSim reads/writes)
# 2. ~/.config/CoppeliaSim/ (not used by default but some versions check)
for CSIM_CONFIG_DIR in "/home/ga/.CoppeliaSim" "/home/ga/.config/CoppeliaSim"; do
    mkdir -p "$CSIM_CONFIG_DIR"
    # Append our settings to existing usrset.txt (or create new)
    cat >> "$CSIM_CONFIG_DIR/usrset.txt" << 'USRSET'

// Dialog suppression (added by setup)
doNotShowOpenglSettingsMessage = true
doNotShowCrashRecoveryMessage = true
doNotShowUpdateCheckMessage = true
doNotShowSceneSelectionAtStartup = true
preferredScriptingLanguage = lua
doNotShowLanguageSelectionAtStartup = true
USRSET
    chown -R ga:ga "$CSIM_CONFIG_DIR"
done

# Do a warm-up launch of CoppeliaSim with GUI to dismiss first-run dialogs
echo "Performing warm-up launch of CoppeliaSim..."
cd /opt/CoppeliaSim

su - ga -c "
    export DISPLAY=:1
    export COPPELIASIM_ROOT_DIR=/opt/CoppeliaSim
    export LD_LIBRARY_PATH=/opt/CoppeliaSim:\${LD_LIBRARY_PATH:-}
    export QT_QPA_PLATFORM_PLUGIN_PATH=/opt/CoppeliaSim
    export LIBGL_ALWAYS_SOFTWARE=1
    cd /opt/CoppeliaSim
    setsid ./coppeliaSim.sh > /tmp/coppeliasim_warmup.log 2>&1 &
" &

# Wait for CoppeliaSim window to appear
echo "Waiting for CoppeliaSim window..."
for i in $(seq 1 40); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "coppelia"; then
        echo "CoppeliaSim window detected after ${i}s"
        break
    fi
    sleep 1
done

sleep 3

# Dismiss the "Welcome to CoppeliaSim" language selection dialog
# Click "Set up for Lua" button or press Escape
echo "Dismissing first-run dialogs..."
WELCOME_WID=$(DISPLAY=:1 xdotool search --name "Welcome to CoppeliaSim" 2>/dev/null | head -1)
if [ -n "$WELCOME_WID" ]; then
    echo "Found Welcome dialog, clicking 'Set up for Lua'..."
    DISPLAY=:1 xdotool windowactivate "$WELCOME_WID" 2>/dev/null || true
    sleep 0.5
    # Click "Set up for Lua" button - it's in the left-center area of the dialog
    # The dialog is centered at ~960,540 on 1920x1080, Lua button is left of center
    DISPLAY=:1 xdotool windowfocus "$WELCOME_WID" 2>/dev/null || true
    sleep 0.3
    # Use Tab+Enter to select the first button (Lua)
    DISPLAY=:1 xdotool key Tab 2>/dev/null || true
    sleep 0.2
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    # If dialog still there, try clicking directly on "Set up for Lua" button area
    STILL_THERE=$(DISPLAY=:1 xdotool search --name "Welcome to CoppeliaSim" 2>/dev/null | head -1)
    if [ -n "$STILL_THERE" ]; then
        echo "Dialog still visible, trying direct click on Lua button..."
        # Dialog at ~(731,448) size 531x324. Lua button is in left half, ~1/3 from bottom
        # Lua button center: ~(731+531/4, 448+324*0.6) = ~(864, 642)
        DISPLAY=:1 xdotool mousemove 867 675 click 1 2>/dev/null || true
        sleep 1
        # If STILL there, try other coordinates
        STILL_THERE2=$(DISPLAY=:1 xdotool search --name "Welcome to CoppeliaSim" 2>/dev/null | head -1)
        if [ -n "$STILL_THERE2" ]; then
            echo "Trying alternate click position..."
            DISPLAY=:1 xdotool mousemove 867 675 click 1 2>/dev/null || true
            sleep 1
        fi
    fi
fi

# Also try to dismiss any other dialogs
for dialog_name in "Warning" "Error" "Info" "Message" "Tip" "Welcome"; do
    DLG_WID=$(DISPLAY=:1 xdotool search --name "$dialog_name" 2>/dev/null | head -1)
    if [ -n "$DLG_WID" ]; then
        echo "Dismissing $dialog_name dialog..."
        DISPLAY=:1 xdotool windowactivate "$DLG_WID" 2>/dev/null || true
        sleep 0.3
        DISPLAY=:1 xdotool key Escape 2>/dev/null || true
        sleep 0.5
    fi
done

sleep 2

# Kill the warm-up instance
pkill -f /opt/CoppeliaSim/coppeliaSim 2>/dev/null || true
sleep 2
pkill -9 -f /opt/CoppeliaSim/coppeliaSim 2>/dev/null || true
sleep 1

echo "Warm-up launch complete, first-run dialogs cleared."

# Create a desktop shortcut
mkdir -p /home/ga/Desktop
cp /usr/share/applications/coppeliasim.desktop /home/ga/Desktop/ 2>/dev/null || true
chmod +x /home/ga/Desktop/coppeliasim.desktop 2>/dev/null || true
chown -R ga:ga /home/ga/Desktop/

# Create a helper script to launch CoppeliaSim with a scene
cat > /usr/local/bin/coppeliasim-scene << 'SCRIPT'
#!/bin/bash
# Launch CoppeliaSim with a specific scene file
export COPPELIASIM_ROOT_DIR=/opt/CoppeliaSim
export LD_LIBRARY_PATH="/opt/CoppeliaSim:${LD_LIBRARY_PATH:-}"
export QT_QPA_PLATFORM_PLUGIN_PATH="/opt/CoppeliaSim"
export LIBGL_ALWAYS_SOFTWARE=1
export DISPLAY=:1
cd /opt/CoppeliaSim
if [ -n "${1:-}" ]; then
    ./coppeliaSim.sh "$1" &
else
    ./coppeliaSim.sh &
fi
SCRIPT
chmod +x /usr/local/bin/coppeliasim-scene

echo "=== CoppeliaSim setup complete ==="
echo "CoppeliaSim is ready. Launch with: coppeliasim or coppeliasim-scene <file.ttt>"
