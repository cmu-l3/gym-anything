#!/bin/bash
set -e

echo "=== Setting up OpenRocket ==="

# Wait for desktop to be ready
sleep 5

# Verify OpenRocket is installed
if [ ! -f /opt/openrocket/OpenRocket.jar ]; then
    echo "ERROR: OpenRocket JAR not found!"
    exit 1
fi

# Verify Java
if ! java -version 2>&1 | grep -q "17"; then
    echo "WARNING: Java 17 not detected, checking alternatives..."
    java -version 2>&1
fi

# Create working directories
mkdir -p /home/ga/Documents/rockets
mkdir -p /home/ga/Documents/exports
mkdir -p /home/ga/Desktop

# Create desktop launcher script
cat > /home/ga/Desktop/launch_openrocket.sh << 'EOF'
#!/bin/bash
export DISPLAY=:1
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
java -Xms512m -Xmx2048m -jar /opt/openrocket/OpenRocket.jar "$@" &
EOF
chmod +x /home/ga/Desktop/launch_openrocket.sh

# Create .desktop file
cat > /home/ga/Desktop/OpenRocket.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=OpenRocket
Comment=Model Rocket Design and Simulation
Exec=java -Xms512m -Xmx2048m -jar /opt/openrocket/OpenRocket.jar
Icon=/opt/openrocket/openrocket.png
StartupNotify=true
Terminal=false
Type=Application
Categories=Education;Science;Engineering;
DESKTOPEOF
chmod +x /home/ga/Desktop/OpenRocket.desktop

# Create symlink to rockets directory on desktop
ln -sf /home/ga/Documents/rockets /home/ga/Desktop/Rockets 2>/dev/null || true

# Set ownership for all user files
chown -R ga:ga /home/ga/Desktop/
chown -R ga:ga /home/ga/Documents/

# Warm-up launch: start OpenRocket, wait for window, dismiss any dialogs, then close
echo "=== Warm-up launch of OpenRocket ==="
su - ga -c "setsid bash -c 'export DISPLAY=:1 JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; java -Xms512m -Xmx2048m -jar /opt/openrocket/OpenRocket.jar > /tmp/openrocket_warmup.log 2>&1 &'"
sleep 3

# Wait for OpenRocket window to appear
echo "Waiting for OpenRocket window..."
OR_STARTED=false
for i in $(seq 1 120); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "openrocket\|rocket"; then
        OR_STARTED=true
        echo "OpenRocket window detected after ${i}s"
        break
    fi
    sleep 1
done

if [ "$OR_STARTED" = true ]; then
    sleep 5

    # Maximize the window
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "openrocket\|rocket" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        echo "Window maximized"
    fi

    # Dismiss any startup dialogs (update check, etc.)
    sleep 3
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1

    # Close any tip/update dialogs by pressing Enter (in case OK button is focused)
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 2

    # Kill the warm-up instance
    echo "Closing warm-up instance..."
    pkill -f "OpenRocket.jar" 2>/dev/null || true
    sleep 2
    # Force kill if still running
    pkill -9 -f "OpenRocket.jar" 2>/dev/null || true
    sleep 1
else
    echo "WARNING: OpenRocket window not detected within 120s"
    echo "Warm-up log:"
    cat /tmp/openrocket_warmup.log 2>/dev/null || true
    # Kill any orphaned processes
    pkill -9 -f "OpenRocket.jar" 2>/dev/null || true
fi

# List available rocket files
echo "=== Available rocket designs ==="
ls -la /home/ga/Documents/rockets/*.ork 2>/dev/null || echo "No .ork files found"

echo "=== OpenRocket setup complete ==="
