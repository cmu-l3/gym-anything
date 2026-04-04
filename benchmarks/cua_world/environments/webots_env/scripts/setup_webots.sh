#!/bin/bash
set -euo pipefail

echo "=== Setting up Webots configuration ==="

# Wait for desktop to be ready
sleep 5

WEBOTS_HOME="/usr/local/webots"

# Pre-create Webots config to suppress first-run dialogs
# Webots uses Qt QSettings: ~/.config/Cyberbotics/Webots-<version>.conf
echo "Configuring Webots preferences..."
mkdir -p /home/ga/.config/Cyberbotics

# Create preferences file to disable guided tour, telemetry, update checks
cat > /home/ga/.config/Cyberbotics/Webots-R2023b.conf << 'CONFEOF'
[General]
StartupMode=Pause
telemetry=false
theme=
updatePolicy=Never

[MainWindow]
dontShowAgainBox=guided_tour;telemetry;welcome;openWorld
maximized=true
CONFEOF

# Also create for R2025a in case fallback version was installed
cp /home/ga/.config/Cyberbotics/Webots-R2023b.conf \
   /home/ga/.config/Cyberbotics/Webots-R2025a.conf 2>/dev/null || true

chown -R ga:ga /home/ga/.config/Cyberbotics

# Set environment variables for software rendering
cat >> /home/ga/.bashrc << 'ENVEOF'

# Webots environment
export WEBOTS_HOME=/usr/local/webots
export LIBGL_ALWAYS_SOFTWARE=1
export PATH=$WEBOTS_HOME:$PATH
ENVEOF

cat >> /home/ga/.profile << 'ENVEOF'

# Webots environment
export WEBOTS_HOME=/usr/local/webots
export LIBGL_ALWAYS_SOFTWARE=1
export PATH=$WEBOTS_HOME:$PATH
ENVEOF

chown ga:ga /home/ga/.bashrc /home/ga/.profile

# Create desktop shortcut
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/Webots.desktop << 'DESKEOF'
[Desktop Entry]
Name=Webots
Comment=Webots Robot Simulator
Exec=env DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 WEBOTS_HOME=/usr/local/webots /usr/local/webots/webots
Icon=/usr/local/webots/resources/icons/core/webots.png
StartupNotify=true
Categories=Science;Robotics;Simulation;
Type=Application
DESKEOF
chown ga:ga /home/ga/Desktop/Webots.desktop
chmod +x /home/ga/Desktop/Webots.desktop

# Mark desktop shortcut as trusted (prevents GNOME "untrusted" overlay)
su - ga -c "DISPLAY=:1 gio set /home/ga/Desktop/Webots.desktop metadata::trusted true" 2>/dev/null || true

# Create working directory for simulation projects
mkdir -p /home/ga/webots_projects
chown ga:ga /home/ga/webots_projects

# Dialog suppression is handled by the config file above and --batch flag
# in task setup scripts. No warm-up launch needed (saves memory and avoids
# crashes with Mesa software rendering in VM environments).

echo "=== Webots setup complete ==="
