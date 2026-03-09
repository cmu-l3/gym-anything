#!/bin/bash
# post_start hook: Configure gvSIG Desktop and perform warm-up launch
# Runs after the desktop is ready

echo "=== Setting up gvSIG Desktop ==="

# Wait for desktop to be fully ready
sleep 5

GVSIG_DATA_DIR="/home/ga/gvsig_data"

# -------------------------------------------------------------------
# Determine the actual gvSIG launcher
# The deb installs to /usr/local/lib/gvsig-desktop/2.4.0-2850-2-amd64/gvSIG.sh
# -------------------------------------------------------------------
GVSIG_LAUNCHER=""
if [ -f /etc/gvsig_launcher_path ]; then
    GVSIG_LAUNCHER=$(cat /etc/gvsig_launcher_path)
fi
if [ -z "$GVSIG_LAUNCHER" ] || [ ! -x "$GVSIG_LAUNCHER" ]; then
    GVSIG_LAUNCHER=$(find /usr/local/lib/gvsig-desktop -name "gvSIG.sh" 2>/dev/null | head -1)
fi
if [ -z "$GVSIG_LAUNCHER" ] || [ ! -x "$GVSIG_LAUNCHER" ]; then
    echo "ERROR: Could not find gvSIG launcher!"
    exit 1
fi
echo "gvSIG launcher: $GVSIG_LAUNCHER"

# Save launcher path for task scripts to use
echo "$GVSIG_LAUNCHER" > /tmp/gvsig_launcher_path
chmod 644 /tmp/gvsig_launcher_path

# -------------------------------------------------------------------
# Create a convenient system-wide launch wrapper
# -------------------------------------------------------------------
cat > /usr/local/bin/launch-gvsig << LAUNCHEOF
#!/bin/bash
export LC_NUMERIC=C
export DISPLAY=\${DISPLAY:-:1}
export XAUTHORITY=\${XAUTHORITY:-/home/ga/.Xauthority}
exec "$GVSIG_LAUNCHER" "\$@"
LAUNCHEOF
chmod +x /usr/local/bin/launch-gvsig

# -------------------------------------------------------------------
# Create desktop shortcut
# -------------------------------------------------------------------
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/gvSIG.desktop << DESKTOPEOF
[Desktop Entry]
Name=gvSIG Desktop
Comment=Geographic Information System
Exec=bash -c 'LC_NUMERIC=C DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority "$GVSIG_LAUNCHER" > /tmp/gvsig.log 2>&1'
Icon=gvsig-desktop
StartupNotify=true
Terminal=false
Categories=Education;Science;Geography;
Type=Application
DESKTOPEOF
chown ga:ga /home/ga/Desktop/gvSIG.desktop
chmod +x /home/ga/Desktop/gvSIG.desktop

# Ensure data dir permissions (gvSIG needs write access to data dirs for index files)
chown -R ga:ga "$GVSIG_DATA_DIR" 2>/dev/null || true
chmod -R 755 "$GVSIG_DATA_DIR" 2>/dev/null || true

# -------------------------------------------------------------------
# Warm-up launch: settle first-run state, populate gvSIG user directory
# -------------------------------------------------------------------
echo "Starting gvSIG warm-up launch..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Force Java 8 — gvSIG 2.4.0 uses commons-lang3 that cannot parse Java 9+ version strings
JAVA8_HOME=""
if [ -d /usr/lib/jvm/java-8-openjdk-amd64 ]; then
    JAVA8_HOME="/usr/lib/jvm/java-8-openjdk-amd64"
elif [ -d /usr/lib/jvm/java-1.8.0-openjdk-amd64 ]; then
    JAVA8_HOME="/usr/lib/jvm/java-1.8.0-openjdk-amd64"
fi
echo "Using JAVA_HOME=$JAVA8_HOME for gvSIG warm-up"
su - ga -c "LC_NUMERIC=C JAVA_HOME='$JAVA8_HOME' DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority '$GVSIG_LAUNCHER' > /tmp/gvsig_warmup.log 2>&1 &"

echo "Waiting for gvSIG to start (Java apps take 30-90 seconds)..."
ELAPSED=0
TIMEOUT=150
WINDOW_FOUND=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if pgrep -f "gvSIG" > /dev/null 2>&1; then
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "gvsig\|andami"; then
            echo "gvSIG window detected after ${ELAPSED}s"
            WINDOW_FOUND=1
            break
        fi
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

if [ $WINDOW_FOUND -eq 0 ]; then
    echo "gvSIG window not detected in ${TIMEOUT}s — still waiting 30 more seconds..."
    sleep 30
fi

# Additional wait for full initialization
sleep 10

# Take screenshot to document warm-up state
DISPLAY=:1 import -window root /tmp/gvsig_warmup_screenshot.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/gvsig_warmup_screenshot.png 2>/dev/null || true
echo "Warm-up screenshot: /tmp/gvsig_warmup_screenshot.png"

# Dismiss any dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Kill gvSIG after warm-up
echo "Killing gvSIG after warm-up..."
pkill -f "gvSIG" 2>/dev/null || true
sleep 4
pkill -9 -f "gvSIG" 2>/dev/null || true
sleep 2

# Ensure gvSIG user dir is owned by ga
chown -R ga:ga /home/ga/gvSIG 2>/dev/null || true

# -------------------------------------------------------------------
# Copy pre-built project file (countries_base.gvsproj) to gvsig_data
# This project file has the Natural Earth countries layer pre-loaded
# and is used as the start state for tasks 2-5
# -------------------------------------------------------------------
PROJECTS_DIR="/home/ga/gvsig_data/projects"
mkdir -p "$PROJECTS_DIR"
PREBUILT="/workspace/data/projects/countries_base.gvsproj"
if [ -f "$PREBUILT" ]; then
    cp "$PREBUILT" "$PROJECTS_DIR/countries_base.gvsproj"
    chown ga:ga "$PROJECTS_DIR/countries_base.gvsproj"
    chmod 644 "$PROJECTS_DIR/countries_base.gvsproj"
    echo "countries_base.gvsproj installed to $PROJECTS_DIR"
else
    echo "WARNING: Pre-built project not found at $PREBUILT"
fi

echo "gvSIG warm-up complete"
echo "=== gvSIG Desktop setup complete ==="
