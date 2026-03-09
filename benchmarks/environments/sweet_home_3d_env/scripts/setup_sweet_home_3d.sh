#!/bin/bash
set -e

echo "=== Setting up Sweet Home 3D ==="

# Wait for desktop to be ready
sleep 5

# Verify desktop is available
for i in $(seq 1 30); do
    if DISPLAY=:1 xdpyinfo >/dev/null 2>&1; then
        echo "Desktop is ready"
        break
    fi
    echo "Waiting for desktop... ($i/30)"
    sleep 2
done

# Copy sample files to user home directory
echo "Copying sample home plans to user directory..."
mkdir -p /home/ga/Documents/SweetHome3D
cp /opt/sweethome3d_samples/*.sh3d /home/ga/Documents/SweetHome3D/ 2>/dev/null || true
chown -R ga:ga /home/ga/Documents/SweetHome3D

# Pre-configure Sweet Home 3D preferences to suppress first-run behavior
# Sweet Home 3D stores prefs via Java Preferences API
PREFS_DIR="/home/ga/.java/.userPrefs/com/eteks/sweethome3d"
mkdir -p "$PREFS_DIR"

# Create preferences file to disable update checks and tips
cat > "$PREFS_DIR/prefs.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<!DOCTYPE map SYSTEM "http://java.sun.com/dtd/preferences.dtd">
<map MAP_XML_VERSION="1.0">
  <entry key="updateCheckDate" value="2099-01-01"/>
  <entry key="showTipsAtStartup" value="false"/>
  <entry key="furnitureCatalogViewedInTree" value="true"/>
  <entry key="navigationPanelVisible" value="false"/>
</map>
EOF
chown -R ga:ga /home/ga/.java

# Warm-up launch to initialize any remaining first-run settings
echo "Performing warm-up launch..."
su - ga -c "DISPLAY=:1 /opt/SweetHome3D/SweetHome3D &"
WARMUP_PID=$!

# Wait for the Sweet Home 3D window to appear (search by class name for Java apps)
echo "Waiting for Sweet Home 3D window..."
for i in $(seq 1 60); do
    WID=$(DISPLAY=:1 xdotool search --class "sweethome3d" 2>/dev/null | head -1)
    if [ -z "$WID" ]; then
        WID=$(DISPLAY=:1 xdotool search --name "com-eteks-sweethome3d" 2>/dev/null | head -1)
    fi
    if [ -n "$WID" ]; then
        echo "Sweet Home 3D window detected (WID: $WID)"
        break
    fi
    sleep 2
done

# Dismiss any tip-of-the-day or update dialogs
sleep 5
echo "Dismissing any startup dialogs..."
for attempt in 1 2 3 4 5; do
    # Try pressing Escape to dismiss dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    # Try pressing Enter/Return to accept defaults
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
done

# Take a verification screenshot
sleep 2
DISPLAY=:1 scrot /tmp/warmup_screenshot.png 2>/dev/null || true

# Kill the warm-up instance
echo "Killing warm-up instance..."
pkill -f "SweetHome3D" 2>/dev/null || true
sleep 3
pkill -9 -f "SweetHome3D" 2>/dev/null || true
sleep 2

# Verify all components are ready
echo "Verifying setup..."
if [ -f /opt/SweetHome3D/SweetHome3D ]; then
    echo "  Sweet Home 3D binary: OK"
else
    echo "  ERROR: Sweet Home 3D binary missing"
    exit 1
fi

SAMPLE_COUNT=$(ls /home/ga/Documents/SweetHome3D/*.sh3d 2>/dev/null | wc -l)
echo "  Sample plans available: $SAMPLE_COUNT"

echo "=== Sweet Home 3D setup complete ==="
