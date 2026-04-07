#!/bin/bash
set -e

echo "=== Setting up GNU Octave ==="

# Wait for desktop to be ready
sleep 5

# Layer 1: Pre-create Octave config to suppress first-run dialogs
mkdir -p /home/ga/.config/octave

# Octave GUI settings (Qt-based)
# The settings file location varies by Octave version; create both possible paths
mkdir -p /home/ga/.config/octave/qt-settings
cat > /home/ga/.config/octave/qt-settings/octave-gui.conf << 'OCTCONF'
[General]
news/allow_web_connection=false
show_news=false

[DockWidgets]
command_window=true
editor=true
file_browser=true
workspace=true

[Editor]
show_LineNumber=true

[MainWindow]
geometry=@ByteArray()
state=@ByteArray()
OCTCONF

# Also write the Octave settings INI format (used by some versions)
cat > /home/ga/.config/octave/octave-gui.ini << 'OCTINI'
[General]
news/allow_web_connection=false
show_news=false
[DockWidgets]
command_window=true
editor=true
file_browser=true
workspace=true
OCTINI

# Create .octaverc to suppress startup messages and configure defaults
cat > /home/ga/.octaverc << 'EOF'
% Suppress first-run wizard and startup messages
more off;
warning('off', 'all');
% Use gnuplot backend for reliable off-screen rendering
graphics_toolkit('gnuplot');
% Start in datasets directory
cd('/home/ga/Documents/datasets');
EOF

# Set proper ownership
chown -R ga:ga /home/ga/.config
chown ga:ga /home/ga/.octaverc

# Create output directory
mkdir -p /home/ga/plots
chown ga:ga /home/ga/plots

# Create a desktop launcher for Octave
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/octave-gui.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=GNU Octave
Exec=octave --gui
Icon=octave
Terminal=false
Categories=Science;Math;
EOF
chmod +x /home/ga/Desktop/octave-gui.desktop
chown ga:ga /home/ga/Desktop/octave-gui.desktop

# Mark the desktop file as trusted (GNOME)
su - ga -c "DISPLAY=:1 dbus-launch gio set /home/ga/Desktop/octave-gui.desktop metadata::trusted true" 2>/dev/null || true

# Layer 2: Warm-up launch to clear first-run state
echo "=== Performing warm-up launch of Octave ==="
su - ga -c "DISPLAY=:1 setsid octave --gui > /tmp/octave_warmup.log 2>&1 &"
WARMUP_START=$(date +%s)

# Wait for Octave window to appear
export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority
TIMEOUT=60
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    WID=$(xdotool search --name "Octave" 2>/dev/null | head -1) || true
    if [ -n "$WID" ]; then
        echo "Octave warmup window detected (WID=$WID)"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# Dismiss any first-run dialogs
sleep 3
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Return 2>/dev/null || true
sleep 2

# Take warmup screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xwd -root -out /tmp/octave_warmup_screen.xwd 2>/dev/null || true
convert /tmp/octave_warmup_screen.xwd /tmp/octave_warmup_screen.png 2>/dev/null || true

# Kill the warm-up instance
pkill -f "octave --gui" 2>/dev/null || true
sleep 2
# Force kill if still running
pkill -9 -f "octave --gui" 2>/dev/null || true
sleep 1

WARMUP_END=$(date +%s)
echo "Warm-up took $((WARMUP_END - WARMUP_START)) seconds"

echo "=== GNU Octave setup complete ==="
