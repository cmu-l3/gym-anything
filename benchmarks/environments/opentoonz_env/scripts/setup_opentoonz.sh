#!/bin/bash
set -e

echo "=== Setting up OpenToonz environment ==="

# Wait for desktop to be ready
sleep 5

# Create OpenToonz directories for ga user
echo "Setting up OpenToonz directories..."
su - ga -c "mkdir -p /home/ga/OpenToonz"
su - ga -c "mkdir -p /home/ga/OpenToonz/projects"
su - ga -c "mkdir -p /home/ga/OpenToonz/outputs"
su - ga -c "mkdir -p /home/ga/Desktop"

# Download official OpenToonz sample data
echo "Downloading OpenToonz sample data..."
SAMPLE_DIR="/home/ga/OpenToonz/samples"
su - ga -c "mkdir -p $SAMPLE_DIR"

# Download from official GitHub repository
cd /tmp
wget -q https://github.com/opentoonz/opentoonz_sample/archive/refs/heads/master.zip -O opentoonz_sample.zip || {
    echo "Warning: Could not download sample data from GitHub"
}

if [ -f /tmp/opentoonz_sample.zip ]; then
    unzip -q /tmp/opentoonz_sample.zip -d /tmp/
    cp -r /tmp/opentoonz_sample-master/* "$SAMPLE_DIR/" || true
    chown -R ga:ga "$SAMPLE_DIR"
    rm -rf /tmp/opentoonz_sample.zip /tmp/opentoonz_sample-master
    echo "Sample data downloaded successfully"
fi

# Create desktop shortcut for OpenToonz
cat > /home/ga/Desktop/OpenToonz.desktop << 'EOF'
[Desktop Entry]
Name=OpenToonz
Comment=2D Animation Software
Exec=/snap/bin/opentoonz
Icon=opentoonz
StartupNotify=true
Terminal=false
Type=Application
Categories=Graphics;2DGraphics;Animation;
EOF
chmod +x /home/ga/Desktop/OpenToonz.desktop
chown ga:ga /home/ga/Desktop/OpenToonz.desktop

# Create launch script
cat > /usr/local/bin/launch-opentoonz << 'LAUNCH_EOF'
#!/bin/bash
export DISPLAY=${DISPLAY:-:1}
xhost +local: 2>/dev/null || true

# Try snap version first, then system version
if [ -x /snap/bin/opentoonz ]; then
    exec /snap/bin/opentoonz "$@"
elif command -v opentoonz &> /dev/null; then
    exec opentoonz "$@"
else
    echo "OpenToonz not found"
    exit 1
fi
LAUNCH_EOF
chmod +x /usr/local/bin/launch-opentoonz

# Disable first-run wizard if possible by creating config
# OpenToonz stores preferences in ~/.config/OpenToonz/
su - ga -c "mkdir -p /home/ga/.config/OpenToonz/stuff/config"

# Create a preferences file to skip startup dialogs
cat > /home/ga/.config/OpenToonz/stuff/config/preferences.ini << 'PREF_EOF'
[General]
AutoSaveEnabled=false
AutoSavePeriod=10
DefaultViewerEnabled=false
ShowSplashScreen=false
ShowStartupDialog=false
StartupPopupShown=true
[Paths]
ProjectRoot=/home/ga/OpenToonz/projects
[UI]
Language=english
StyleSheet=Default
PREF_EOF
chown -R ga:ga /home/ga/.config/OpenToonz

# Start OpenToonz
echo "Starting OpenToonz..."
su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz > /tmp/opentoonz.log 2>&1 &"

# Wait for OpenToonz to fully load (it takes a while to initialize)
echo "Waiting for OpenToonz to load..."
sleep 20

# Wait for main window to appear (poll for up to 60 seconds)
TIMEOUT=60
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -q "OpenToonz 1.5"; then
        echo "OpenToonz main window detected after ${ELAPSED}s"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# Additional wait for dialogs to appear
sleep 5

# Dismiss startup dialogs
echo "Dismissing startup dialogs..."

# Close the Information dialog first (press Enter or click OK)
for i in 1 2 3; do
    DISPLAY=:1 wmctrl -a "Information" 2>/dev/null && sleep 0.5 && DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
done

# Close the Startup dialog (press Escape or click the X)
for i in 1 2 3; do
    DISPLAY=:1 wmctrl -a "Startup" 2>/dev/null && sleep 0.5 && DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

# Try pressing Escape a few more times to dismiss any remaining dialogs
for i in 1 2 3; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Click somewhere in the middle of the screen to dismiss any popups
DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
sleep 1

# Close any Firefox windows that may have opened (OpenToonz sometimes opens help pages)
pkill -f firefox 2>/dev/null || true
sleep 2

# Maximize the main OpenToonz window
DISPLAY=:1 wmctrl -r "OpenToonz 1.5" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz 1.5" 2>/dev/null || true

# Final check
echo "Windows after setup:"
DISPLAY=:1 wmctrl -l 2>/dev/null || true

echo "=== OpenToonz setup complete ==="
echo "OpenToonz is ready!"
echo "  - Sample data: /home/ga/OpenToonz/samples/"
echo "  - Projects: /home/ga/OpenToonz/projects/"
echo "  - Outputs: /home/ga/OpenToonz/outputs/"
