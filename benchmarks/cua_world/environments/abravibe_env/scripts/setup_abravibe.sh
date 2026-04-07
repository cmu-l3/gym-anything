#!/bin/bash
set -e

echo "=== Setting up ABRAVIBE environment ==="

# Wait for desktop to be ready
sleep 5

# Pre-create Octave config to suppress first-run dialogs
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

# Create .octaverc with ABRAVIBE path and defaults
cat > /home/ga/.octaverc << 'EOF'
% Suppress first-run wizard and startup messages
more off;
warning('off', 'all');
% Use gnuplot backend for reliable rendering
graphics_toolkit('gnuplot');
% Ensure ABRAVIBE is on the path
addpath('/usr/share/octave/site/m/abravibe');
EOF

chown -R ga:ga /home/ga/.config
chown ga:ga /home/ga/.octaverc

# Create output directory
mkdir -p /home/ga/plots
chown ga:ga /home/ga/plots

# Create desktop launcher for Octave
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/octave-gui.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=GNU Octave (ABRAVIBE)
Exec=octave --gui
Icon=octave
Terminal=false
Categories=Science;Math;
EOF
chmod +x /home/ga/Desktop/octave-gui.desktop
chown ga:ga /home/ga/Desktop/octave-gui.desktop

# Mark desktop file as trusted (GNOME)
su - ga -c "DISPLAY=:1 dbus-launch gio set /home/ga/Desktop/octave-gui.desktop metadata::trusted true" 2>/dev/null || true

# Warm-up launch to clear first-run state
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

# Kill the warm-up instance
pkill -f "octave --gui" 2>/dev/null || true
sleep 2
pkill -9 -f "octave --gui" 2>/dev/null || true
sleep 1

WARMUP_END=$(date +%s)
echo "Warm-up took $((WARMUP_END - WARMUP_START)) seconds"

echo "=== ABRAVIBE environment setup complete ==="
