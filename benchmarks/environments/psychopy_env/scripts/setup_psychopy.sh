#!/bin/bash
# NOTE: Do NOT use set -e here. Many PsychoPy setup steps may return
# non-zero exit codes (dbus errors, wmctrl failures) without being fatal.

echo "=== Setting up PsychoPy environment ==="

# Wait for desktop to be ready
sleep 5

# Ensure software rendering is enabled
export LIBGL_ALWAYS_SOFTWARE=1

# Create PsychoPy config directory
mkdir -p /home/ga/.psychopy3
mkdir -p /home/ga/PsychoPyExperiments/data
mkdir -p /home/ga/PsychoPyExperiments/conditions
mkdir -p /home/ga/PsychoPyExperiments/demos

# Copy conditions data files from assets
if [ -d /workspace/assets/conditions ]; then
    cp -r /workspace/assets/conditions/* /home/ga/PsychoPyExperiments/conditions/ 2>/dev/null || true
fi

# Set proper ownership
chown -R ga:ga /home/ga/.psychopy3
chown -R ga:ga /home/ga/PsychoPyExperiments

# Copy PsychoPy bundled demos using system cp (avoids dbus abort from psychopy import)
echo "Copying PsychoPy demos..."
# Method 1: Use pip show to find package location (avoids dbus abort from import)
PSYCHOPY_PKG_DIR=$(pip3 show psychopy 2>/dev/null | grep "^Location:" | awk '{print $2}')
if [ -n "$PSYCHOPY_PKG_DIR" ]; then
    PSYCHOPY_PKG_DIR="$PSYCHOPY_PKG_DIR/psychopy"
fi
# Method 2: Fallback to import (may abort but still prints)
if [ -z "$PSYCHOPY_PKG_DIR" ] || [ ! -d "$PSYCHOPY_PKG_DIR" ]; then
    PSYCHOPY_PKG_DIR=$(python3 -c "import os; import psychopy; print(os.path.dirname(psychopy.__file__))" 2>/dev/null) || true
fi
# Method 3: Search common pip install paths
if [ -z "$PSYCHOPY_PKG_DIR" ] || [ ! -d "$PSYCHOPY_PKG_DIR/demos" ]; then
    for candidate in /usr/local/lib/python3*/dist-packages/psychopy /usr/lib/python3*/dist-packages/psychopy /home/ga/.local/lib/python3*/dist-packages/psychopy; do
        if [ -d "$candidate/demos" ]; then
            PSYCHOPY_PKG_DIR="$candidate"
            echo "Found PsychoPy demos via path search: $candidate"
            break
        fi
    done
fi

if [ -n "$PSYCHOPY_PKG_DIR" ] && [ -d "$PSYCHOPY_PKG_DIR/demos" ]; then
    cp -r "$PSYCHOPY_PKG_DIR/demos/"* /home/ga/PsychoPyExperiments/demos/ 2>/dev/null || true
    DEMO_COUNT=$(ls -1 /home/ga/PsychoPyExperiments/demos/ 2>/dev/null | wc -l)
    echo "Demos copied from $PSYCHOPY_PKG_DIR/demos/ ($DEMO_COUNT items)"
else
    echo "WARNING: PsychoPy demos directory not found at $PSYCHOPY_PKG_DIR/demos/"
    echo "The modify_demo_experiment task may not work correctly."
fi

# Verify Stroop demo exists (critical for modify_demo_experiment task)
STROOP_FOUND=$(find /home/ga/PsychoPyExperiments/demos -iname "*stroop*" -name "*.psyexp" 2>/dev/null | head -1)
if [ -z "$STROOP_FOUND" ]; then
    echo "WARNING: Stroop demo not found after copy. Will be created by task setup if needed."
fi

chown -R ga:ga /home/ga/PsychoPyExperiments

# Create desktop launcher
cat > /home/ga/Desktop/launch_psychopy.sh << 'EOF'
#!/bin/bash
export DISPLAY=:1
export LIBGL_ALWAYS_SOFTWARE=1
export PSYCHOPY_USERDIR=/home/ga/.psychopy3
cd /home/ga/PsychoPyExperiments
psychopy &
EOF
chmod +x /home/ga/Desktop/launch_psychopy.sh
chown ga:ga /home/ga/Desktop/launch_psychopy.sh

# Create .desktop shortcut
cat > /home/ga/Desktop/PsychoPy.desktop << 'EOF'
[Desktop Entry]
Name=PsychoPy
Comment=Psychology Experiment Builder
Exec=bash -c "LIBGL_ALWAYS_SOFTWARE=1 psychopy"
Terminal=false
Type=Application
Categories=Science;Education;
EOF
chmod +x /home/ga/Desktop/PsychoPy.desktop
chown ga:ga /home/ga/Desktop/PsychoPy.desktop

# Trust the desktop file (GNOME)
dbus-launch gio set /home/ga/Desktop/PsychoPy.desktop metadata::trusted true 2>/dev/null || true

# Launch PsychoPy Builder (first launch generates default configs)
echo "Launching PsychoPy Builder..."
su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"

# Wait for PsychoPy to start
echo "Waiting for PsychoPy window..."
TIMEOUT=90
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "psychopy\|builder\|coder"; then
        echo "PsychoPy window detected after ${ELAPSED}s"
        break
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "WARNING: PsychoPy window not detected within ${TIMEOUT}s"
    echo "Window list:"
    DISPLAY=:1 wmctrl -l 2>/dev/null || true
fi

# Give PsychoPy a few more seconds to fully render
sleep 5

# ================================================================
# CRITICAL: Suppress startup dialogs by fixing config files
# PsychoPy overwrites userPrefs.cfg on first launch with defaults.
# We must patch AFTER PsychoPy generates its config files.
# ================================================================
echo "Patching PsychoPy config to suppress dialogs..."

# Get the current PsychoPy version (strip whitespace/newlines)
# python3 may abort due to dbus issues but still prints the version
PSYCHOPY_VER=$(python3 -c "import psychopy; print(psychopy.__version__)" 2>/dev/null | tr -d '[:space:]') || true
if [ -z "$PSYCHOPY_VER" ]; then
    # Try pip show as fallback
    PSYCHOPY_VER=$(pip3 show psychopy 2>/dev/null | grep "^Version:" | awk '{print $2}' | tr -d '[:space:]') || true
fi
if [ -z "$PSYCHOPY_VER" ]; then
    PSYCHOPY_VER="2025.2.4"
fi
echo "PsychoPy version: $PSYCHOPY_VER"

# Update appData.cfg: set lastVersion to current so "Changes" dialog is skipped
# The key may have varying whitespace; use a flexible regex
if [ -f /home/ga/.psychopy3/appData.cfg ]; then
    echo "Before patching appData.cfg:"
    grep -i "lastVersion" /home/ga/.psychopy3/appData.cfg || echo "(no lastVersion found)"
    sed -i "s/lastVersion\s*=.*/lastVersion = $PSYCHOPY_VER/" /home/ga/.psychopy3/appData.cfg
    echo "After patching appData.cfg:"
    grep -i "lastVersion" /home/ga/.psychopy3/appData.cfg || echo "(no lastVersion found)"
fi

# Update userPrefs.cfg: disable all startup dialogs and telemetry
# Use flexible whitespace matching in case of tabs
if [ -f /home/ga/.psychopy3/userPrefs.cfg ]; then
    sed -i 's/showStartupTips\s*=.*/showStartupTips = False/' /home/ga/.psychopy3/userPrefs.cfg
    sed -i 's/allowUsageStats\s*=.*/allowUsageStats = False/' /home/ga/.psychopy3/userPrefs.cfg
    sed -i 's/checkForUpdates\s*=.*/checkForUpdates = False/' /home/ga/.psychopy3/userPrefs.cfg
    sed -i 's/showSplash\s*=.*/showSplash = False/' /home/ga/.psychopy3/userPrefs.cfg
fi

# Kill PsychoPy and restart with patched configs
echo "Restarting PsychoPy with patched configs..."
pkill -f psychopy 2>/dev/null || true
sleep 3

su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"

# Wait for restart
ELAPSED=0
while [ $ELAPSED -lt 60 ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "psychopy\|builder\|coder"; then
        echo "PsychoPy restarted after ${ELAPSED}s"
        break
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

sleep 5

# Close any remaining secondary dialogs (error, config needed)
DISPLAY=:1 wmctrl -c 'PsychoPy Error' 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -c 'Additional configuration' 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize PsychoPy Builder window
BUILDER_WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Builder" | head -1 | awk '{print $1}')
if [ -n "$BUILDER_WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$BUILDER_WID" -b add,maximized_vert,maximized_horz
    DISPLAY=:1 wmctrl -i -a "$BUILDER_WID"
    echo "PsychoPy Builder maximized: $BUILDER_WID"
else
    echo "WARNING: Could not find PsychoPy Builder window to maximize"
fi

echo "=== PsychoPy setup complete ==="
