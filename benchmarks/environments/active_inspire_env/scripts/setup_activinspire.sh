#!/bin/bash
set -e

echo "=== Setting up ActivInspire environment ==="

# Wait for desktop to be ready
sleep 5

# Function to wait for X display to be ready
wait_for_display() {
    local timeout=60
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 xdpyinfo >/dev/null 2>&1; then
            echo "X display is ready"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: X display check timed out"
    return 1
}

# Wait for display
wait_for_display || true

# Create ActivInspire configuration directories
mkdir -p /home/ga/.activsoftware/ActivInspire
mkdir -p /home/ga/.activsoftware/ActivSoftware
mkdir -p /home/ga/Documents/Flipcharts
mkdir -p /home/ga/Pictures/ActivInspire

# Create a configuration file to disable first-run wizard and dashboard
# ActivInspire stores settings in various config files
cat > /home/ga/.activsoftware/ActivInspire/ActivInspire.conf << 'EOF'
[General]
ShowDashboardOnStartup=false
FirstRunComplete=true
LicenseAccepted=true

[Interface]
ShowTips=false
ShowWelcome=false
Language=en-US

[Workspace]
DefaultPath=/home/ga/Documents/Flipcharts
AutosaveEnabled=true
AutosaveInterval=5
EOF

# Create ActivSoftware general config
cat > /home/ga/.activsoftware/ActivSoftware/ActivSoftware.conf << 'EOF'
[Registration]
FirstRun=false
RegistrationComplete=true

[General]
Language=en-US
ShowStartupDialog=false
EOF

# Create desktop shortcut for ActivInspire
cat > /home/ga/Desktop/ActivInspire.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=ActivInspire
Comment=Interactive whiteboard software
Exec=/usr/bin/activinspire
Icon=activinspire
Terminal=false
Categories=Education;Office;
EOF

# Create launcher script that handles display and common issues
cat > /home/ga/Desktop/launch_activinspire.sh << 'EOF'
#!/bin/bash
export DISPLAY=:1
export QT_QPA_PLATFORM=xcb
export QT_X11_NO_MITSHM=1

# Kill any existing instances
pkill -f "activinspire" 2>/dev/null || true
pkill -f "/Inspire" 2>/dev/null || true
sleep 1

# ActivInspire installation directory
ACTIVINSPIRE_DIR="/usr/local/bin/activsoftware"
ACTIVINSPIRE_BIN="$ACTIVINSPIRE_DIR/Inspire"

if [ -x "$ACTIVINSPIRE_BIN" ]; then
    # Set comprehensive library path including all subdirectories with .so files
    export LD_LIBRARY_PATH="$ACTIVINSPIRE_DIR:$ACTIVINSPIRE_DIR/helperPlugins:$ACTIVINSPIRE_DIR/imageformats:$ACTIVINSPIRE_DIR/platforms:$ACTIVINSPIRE_DIR/printsupport:$ACTIVINSPIRE_DIR/sqldrivers:$ACTIVINSPIRE_DIR/tls:$ACTIVINSPIRE_DIR/xcbglintegrations:$LD_LIBRARY_PATH"
    cd "$ACTIVINSPIRE_DIR"
    exec "$ACTIVINSPIRE_BIN" "$@"
else
    echo "ActivInspire binary not found at $ACTIVINSPIRE_BIN"
    exit 1
fi
EOF

chmod +x /home/ga/Desktop/ActivInspire.desktop
chmod +x /home/ga/Desktop/launch_activinspire.sh

# Set permissions on all config files
chown -R ga:ga /home/ga/.activsoftware
chown -R ga:ga /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Pictures/ActivInspire
chown ga:ga /home/ga/Desktop/ActivInspire.desktop
chown ga:ga /home/ga/Desktop/launch_activinspire.sh

# Trust the desktop file (GNOME specific)
su - ga -c "gio set /home/ga/Desktop/ActivInspire.desktop metadata::trusted true" 2>/dev/null || true

# Copy any sample flipcharts from workspace
if [ -d "/workspace/assets/flipcharts" ]; then
    cp -r /workspace/assets/flipcharts/* /home/ga/Documents/Flipcharts/ 2>/dev/null || true
    chown -R ga:ga /home/ga/Documents/Flipcharts
fi

# Copy any sample images from workspace
if [ -d "/workspace/assets/images" ]; then
    cp -r /workspace/assets/images/* /home/ga/Pictures/ActivInspire/ 2>/dev/null || true
    chown -R ga:ga /home/ga/Pictures/ActivInspire
fi

# Set up file associations for flipchart files
mkdir -p /home/ga/.local/share/mime/packages
cat > /home/ga/.local/share/mime/packages/activinspire.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-flipchart">
    <comment>ActivInspire Flipchart</comment>
    <glob pattern="*.flipchart"/>
    <glob pattern="*.flp"/>
  </mime-type>
</mime-info>
EOF
chown -R ga:ga /home/ga/.local/share/mime

# Update MIME database
su - ga -c "update-mime-database /home/ga/.local/share/mime" 2>/dev/null || true

# Launch ActivInspire
echo "=== Launching ActivInspire ==="
su - ga -c "DISPLAY=:1 /home/ga/Desktop/launch_activinspire.sh &" 2>/dev/null || true

# Wait for application to start
sleep 10

# Function to handle the license dialog
handle_license_dialog() {
    echo "Checking for license dialog..."

    # Wait for license dialog to appear (up to 30 seconds)
    local timeout=30
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l | grep -q "License Agreement"; then
            echo "License dialog detected!"
            sleep 2

            # Click the "I accept" checkbox at (794, 719)
            # These coordinates are converted from 1280x720 to 1920x1080
            echo "Clicking 'I accept' checkbox..."
            DISPLAY=:1 xdotool search --name "License Agreement" windowactivate
            sleep 0.5
            DISPLAY=:1 xdotool mousemove 794 719
            sleep 0.2
            DISPLAY=:1 xdotool click 1
            sleep 1

            # Click "Run Personal Edition" button at (843, 746)
            echo "Clicking 'Run Personal Edition' button..."
            DISPLAY=:1 xdotool mousemove 843 746
            sleep 0.2
            DISPLAY=:1 xdotool click 1
            sleep 3

            echo "License dialog handled"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "No license dialog detected (may already be accepted)"
    return 0
}

# Function to handle the Welcome dialog
handle_welcome_dialog() {
    echo "Checking for Welcome dialog..."

    # Wait for Welcome dialog (up to 15 seconds)
    local timeout=15
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l | grep -q "Welcome"; then
            echo "Welcome dialog detected!"
            sleep 1

            # Click "Continue" button at (1142, 587)
            # Converted from 1280x720 to 1920x1080
            echo "Clicking 'Continue' button..."
            DISPLAY=:1 xdotool search --name "Welcome" windowactivate
            sleep 0.5
            DISPLAY=:1 xdotool mousemove 1142 587
            sleep 0.2
            DISPLAY=:1 xdotool click 1
            sleep 3

            echo "Welcome dialog handled"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "No Welcome dialog detected"
    return 0
}

# Check if ActivInspire is running
if pgrep -f "Inspire" > /dev/null 2>&1; then
    echo "ActivInspire is running"

    # Handle license dialog if it appears
    handle_license_dialog

    # Handle welcome dialog if it appears
    handle_welcome_dialog
else
    echo "WARNING: ActivInspire may not have started properly"
    echo "Attempting alternative launch methods..."

    # Try alternative launch
    su - ga -c "DISPLAY=:1 /usr/bin/activinspire &" 2>/dev/null || true
    sleep 5

    # Try handling dialogs again
    handle_license_dialog
    handle_welcome_dialog
fi

# List running processes for debugging
echo "=== Running processes ==="
ps aux | grep -E "activinspire|Inspire" | grep -v grep || echo "No ActivInspire process found"

# List windows
echo "=== Windows ==="
DISPLAY=:1 wmctrl -l || echo "No windows found"

echo "=== ActivInspire setup complete ==="
