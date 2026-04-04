#!/bin/bash
set -e

echo "=== Setting up SolveSpace environment ==="

# Wait for desktop to be ready
sleep 5

# Verify sample files exist (sanity check from install)
echo "=== Validating sample files ==="
for f in divider.slvs side.slvs base.slvs; do
    if [ ! -f "/opt/solvespace_samples/$f" ]; then
        echo "ERROR: /opt/solvespace_samples/$f not found"
        exit 1
    fi
    FSIZE=$(stat -c%s "/opt/solvespace_samples/$f")
    echo "  $f: $FSIZE bytes - OK"
done

# Create SolveSpace config directory (suppresses first-run behaviors)
mkdir -p /home/ga/.config/solvespace
chown -R ga:ga /home/ga/.config/solvespace

# Write SolveSpace settings.json to configure default behavior
# Suppresses update checks; sets consistent defaults
cat > /home/ga/.config/solvespace/settings.json << 'EOF'
{
  "checkForUpdates": false,
  "locale": "en_US",
  "exportUnit": "mm",
  "gridSpacing": 5.0,
  "gridVisible": true
}
EOF
chown ga:ga /home/ga/.config/solvespace/settings.json

# Create workspace directory for the agent
mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

# Create Desktop shortcut for SolveSpace
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/SolveSpace.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=SolveSpace
Comment=Parametric 2D/3D CAD
Exec=solvespace
Icon=solvespace
Terminal=false
StartupNotify=true
EOF
chmod +x /home/ga/Desktop/SolveSpace.desktop
chown ga:ga /home/ga/Desktop/SolveSpace.desktop

echo "=== Performing warm-up launch to settle first-run state ==="
# Launch SolveSpace, wait for it to appear, then close it
# This ensures any first-run initialization is complete
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority solvespace > /tmp/solvespace_warmup.log 2>&1 &"
sleep 8

# Check if SolveSpace launched
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "solvespace"; then
    echo "SolveSpace window found during warm-up"
    # Dismiss any dialogs with Escape
    DISPLAY=:1 xdotool key --clearmodifiers Escape 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key --clearmodifiers Escape 2>/dev/null || true
    sleep 1
else
    echo "SolveSpace window not found during warm-up (may still be loading)"
    sleep 5
fi

# Kill SolveSpace after warm-up
pkill -f solvespace 2>/dev/null || true
sleep 2

echo "=== SolveSpace warm-up complete ==="
echo "=== SolveSpace environment setup complete ==="
