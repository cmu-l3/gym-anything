#!/bin/bash
set -e

echo "=== Setting up ActivInspire environment ==="

APP_UID=$(id -u ga)
RUNTIME_DIR="/run/user/$APP_UID"
SESSION_BUS="unix:path=$RUNTIME_DIR/bus"

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

wait_for_session_bus() {
    local timeout="${1:-60}"
    local elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        if [ -S "$RUNTIME_DIR/bus" ]; then
            echo "User session bus is ready"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: User session bus did not become ready within ${timeout}s"
    return 1
}

is_supported_focal_base() {
    . /etc/os-release
    [ "${VERSION_CODENAME:-}" = "focal" ]
}

get_display_dimensions() {
    local dims
    dims=$(DISPLAY=:1 xdpyinfo 2>/dev/null | awk '/dimensions:/{print $2; exit}')
    if [ -z "$dims" ]; then
        echo "1920 1080"
        return
    fi
    echo "${dims%x*} ${dims#*x}"
}

click_scaled_coord() {
    local base_x="$1"
    local base_y="$2"
    local width height
    read -r width height < <(get_display_dimensions)
    local click_x=$((base_x * width / 1920))
    local click_y=$((base_y * height / 1080))
    DISPLAY=:1 xdotool mousemove --sync "$click_x" "$click_y" click 1
}

focus_window_title() {
    DISPLAY=:1 wmctrl -a "$1" 2>/dev/null || true
    sleep 1
}

handle_license_dialog() {
    local timeout="${1:-30}"
    local elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -q "Promethean License Agreement"; then
            echo "Handling license dialog"
            focus_window_title "Promethean License Agreement"
            click_scaled_coord 788 719
            sleep 1
            click_scaled_coord 845 744
            sleep 2
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

handle_welcome_dialog() {
    local timeout="${1:-30}"
    local elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -q "Welcome to ActivInspire"; then
            echo "Handling welcome dialog"
            focus_window_title "Welcome to ActivInspire"
            click_scaled_coord 1142 587
            sleep 2
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

auto_advance_startup_dialogs() {
    if ! is_supported_focal_base; then
        return 0
    fi
    handle_license_dialog 45 || true
    handle_welcome_dialog 45 || true
}

activinspire_window_open() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -Eq \
        "ActivInspire|Welcome to ActivInspire|Promethean License Agreement"
}

wait_for_activinspire_window() {
    local timeout="${1:-45}"
    local elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        if activinspire_window_open; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

launch_activinspire() {
    sudo -u ga bash -lc \
        "pkill -x Inspire 2>/dev/null || true
         pkill -x QtWebEngineProcess 2>/dev/null || true
         sleep 1
         nohup env \
            DISPLAY=:1 \
            XAUTHORITY=/home/ga/.Xauthority \
            XDG_RUNTIME_DIR=$RUNTIME_DIR \
            DBUS_SESSION_BUS_ADDRESS=$SESSION_BUS \
            DESKTOP_SESSION=ubuntu \
            LIBGL_ALWAYS_SOFTWARE=1 \
            QT_QUICK_BACKEND=software \
            QT_OPENGL=software \
            QTWEBENGINE_CHROMIUM_FLAGS=--disable-gpu \
            /usr/local/bin/activinspire \
            >/home/ga/activinspire_launch.log 2>&1 </dev/null &"
}

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
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -S "$XDG_RUNTIME_DIR/bus" ]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
fi
export DESKTOP_SESSION="${DESKTOP_SESSION:-ubuntu}"
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
export QT_QUICK_BACKEND="${QT_QUICK_BACKEND:-software}"
export QT_OPENGL="${QT_OPENGL:-software}"
export QTWEBENGINE_CHROMIUM_FLAGS="${QTWEBENGINE_CHROMIUM_FLAGS:---disable-gpu}"

# Kill any existing instances
pkill -x Inspire 2>/dev/null || true
pkill -x QtWebEngineProcess 2>/dev/null || true
sleep 1

if [ -x "/usr/local/bin/activinspire" ]; then
    exec /usr/local/bin/activinspire "$@"
else
    echo "ActivInspire wrapper not found at /usr/local/bin/activinspire"
    exit 1
fi
EOF

chmod +x /home/ga/Desktop/ActivInspire.desktop
chmod +x /home/ga/Desktop/launch_activinspire.sh
rm -f /home/ga/Desktop/activsoftware.desktop

# Set permissions on all config files
chown -R ga:ga /home/ga/.activsoftware
chown -R ga:ga /home/ga/Documents/Flipcharts
chown -R ga:ga /home/ga/Pictures/ActivInspire
chown ga:ga /home/ga/Desktop/ActivInspire.desktop
chown ga:ga /home/ga/Desktop/launch_activinspire.sh

# Trust the desktop file (GNOME specific)
sudo -u ga env \
    XDG_RUNTIME_DIR="$RUNTIME_DIR" \
    DBUS_SESSION_BUS_ADDRESS="$SESSION_BUS" \
    gio set /home/ga/Desktop/ActivInspire.desktop metadata::trusted true \
    2>/dev/null || true

# Fallback: use dbus-launch to create a D-Bus session if the above didn't work
su - ga -c "dbus-launch gio set /home/ga/Desktop/ActivInspire.desktop metadata::trusted true" 2>/dev/null || true

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
sudo -u ga update-mime-database /home/ga/.local/share/mime 2>/dev/null || true

# Launch ActivInspire
echo "=== Launching ActivInspire ==="
wait_for_session_bus || true

launch_attempt=1
while [ "$launch_attempt" -le 2 ]; do
    launch_activinspire
    if wait_for_activinspire_window 120; then
        echo "ActivInspire window detected"
        auto_advance_startup_dialogs
        break
    fi
    echo "WARNING: ActivInspire did not surface a window on attempt $launch_attempt"
    launch_attempt=$((launch_attempt + 1))
done

if ! activinspire_window_open; then
    echo "WARNING: ActivInspire did not surface a window after retries"
fi

# List running processes for debugging
echo "=== Running processes ==="
ps aux | grep -E "activinspire|Inspire" | grep -v grep || echo "No ActivInspire process found"

# List windows
echo "=== Windows ==="
DISPLAY=:1 wmctrl -l || echo "No windows found"

echo "=== ActivInspire setup complete ==="
