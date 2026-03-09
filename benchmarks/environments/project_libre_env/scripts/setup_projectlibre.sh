#!/bin/bash
set -e

echo "=== Setting up ProjectLibre environment ==="

# Create project directories for the ga user
mkdir -p /home/ga/Projects
mkdir -p /home/ga/Projects/samples
chown -R ga:ga /home/ga/Projects

# Copy sample project from mounted workspace assets
# The sample project is in MSPDI XML format (Microsoft Project XML schema)
# which ProjectLibre natively imports via file extension detection (.xml)
SAMPLE_DIR="/home/ga/Projects/samples"
SAMPLE_XML="${SAMPLE_DIR}/sample_project.xml"

if [ -f "/workspace/assets/sample_project.xml" ]; then
    cp /workspace/assets/sample_project.xml "$SAMPLE_XML"
    echo "Copied sample project from assets: $SAMPLE_XML"
    ls -lah "$SAMPLE_XML"
else
    echo "ERROR: sample_project.xml not found in /workspace/assets — assets mount may have failed"
    exit 1
fi

# Set proper permissions
chown -R ga:ga /home/ga/Projects

# Create a Desktop shortcut for ProjectLibre
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/ProjectLibre.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=ProjectLibre
Comment=Open-source project management
Exec=projectlibre %F
Icon=projectlibre
StartupNotify=true
Terminal=false
Type=Application
MimeType=application/x-projectlibre;
Categories=Office;ProjectManagement;
DESKTOPEOF
chmod +x /home/ga/Desktop/ProjectLibre.desktop
chown ga:ga /home/ga/Desktop/ProjectLibre.desktop

# Create a launch helper script
cat > /usr/local/bin/launch_projectlibre << 'LAUNCHEOF'
#!/bin/bash
export DISPLAY=${DISPLAY:-:1}
if [ -n "$1" ]; then
    setsid projectlibre "$1" > /tmp/projectlibre.log 2>&1 &
else
    setsid projectlibre > /tmp/projectlibre.log 2>&1 &
fi
echo "ProjectLibre launched (PID: $!)"
LAUNCHEOF
chmod +x /usr/local/bin/launch_projectlibre

# Perform warm-up launch to clear first-run dialogs
# This ensures subsequent launches are clean (no first-run dialogs)
echo "Performing warm-up launch to initialize ProjectLibre..."

# Launch ProjectLibre without a project file
su - ga -c "DISPLAY=:1 setsid projectlibre > /tmp/projectlibre_warmup.log 2>&1 &"

# Wait for window to appear
echo "Waiting for ProjectLibre window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "projectlibre"; then
        echo "ProjectLibre window appeared after ${i}s"
        break
    fi
    sleep 1
done

# Extra wait for UI to fully load
sleep 5

# Dismiss any first-run dialogs (welcome screen, recent projects, etc.)
echo "Dismissing any first-run dialogs..."
for attempt in $(seq 1 5); do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Additional wait
sleep 2

# Close any modal dialogs by pressing Enter (some dialogs have OK button)
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Kill the warm-up instance
echo "Terminating warm-up instance..."
pkill -f "/usr/share/projectlibre" 2>/dev/null || true
pkill -f "projectlibre" 2>/dev/null || true
sleep 3

# Verify cleanup
if pgrep -f "projectlibre" > /dev/null 2>&1; then
    echo "Force-killing remaining projectlibre processes..."
    pkill -9 -f "projectlibre" 2>/dev/null || true
    sleep 2
fi

echo "Warm-up complete. ProjectLibre first-run state cleared."

# List sample project files
echo ""
echo "Sample project files available:"
ls -la /home/ga/Projects/samples/ 2>/dev/null || echo "(none)"

echo "=== ProjectLibre setup complete ==="
