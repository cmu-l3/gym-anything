#!/bin/bash
set -euo pipefail

echo "=== Setting up LibreCAD environment ==="

# Wait for desktop to be ready
sleep 5

# ============================================================
# Validate that the real floorplan.dxf was downloaded
# (install script already validated size, but double-check here)
# ============================================================
FLOORPLAN_SIZE=$(stat -c%s /opt/librecad_samples/floorplan.dxf 2>/dev/null || echo 0)
if [ "$FLOORPLAN_SIZE" -lt 100000 ]; then
    echo "ERROR: /opt/librecad_samples/floorplan.dxf is missing or too small."
    echo "The real file must be >100KB. pre_start hook may have failed."
    exit 1
fi
echo "Confirmed: floorplan.dxf is ${FLOORPLAN_SIZE} bytes (real architectural drawing)."

chmod -R 755 /opt/librecad_samples

# ============================================================
# Configure LibreCAD to suppress first-run dialog
# Two-layer dialog suppression:
# Layer 1: Pre-write config file with FirstLoad=false
# Layer 2: Warm-up launch to clear any remaining state
# ============================================================
echo "Configuring LibreCAD for user ga..."

mkdir -p /home/ga/.config/LibreCAD
cat > /home/ga/.config/LibreCAD/LibreCAD.conf << 'EOF'
[Startup]
FirstLoad=false

[Appearance]
Language=en
LanguageCmd=en
Style=

[Paths]
Translations=
Hatchings=
Fonts=
Parts=
Template=

[Units]
Default=4

[Window]
Maximized=true
EOF

chown -R ga:ga /home/ga/.config/LibreCAD

# ============================================================
# Create workspace directory for drawings
# ============================================================
mkdir -p /home/ga/Documents/LibreCAD
cp /opt/librecad_samples/floorplan.dxf /home/ga/Documents/LibreCAD/
chown -R ga:ga /home/ga/Documents/LibreCAD

echo "Copied floorplan.dxf to /home/ga/Documents/LibreCAD/"

# ============================================================
# Warm-up launch: start LibreCAD to settle first-run state,
# then kill it. Subsequent launches will be clean.
# ============================================================
echo "Performing warm-up launch of LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad_warmup.log 2>&1 &"
sleep 8

# Dismiss any remaining dialog with Enter key
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 2

# Kill LibreCAD after warm-up
pkill -f librecad 2>/dev/null || true
sleep 2

echo "LibreCAD warm-up complete."

# ============================================================
# Verify LibreCAD is installed and accessible
# ============================================================
if which librecad > /dev/null 2>&1; then
    echo "LibreCAD is installed at: $(which librecad)"
else
    echo "ERROR: LibreCAD not found in PATH"
    exit 1
fi

echo "=== LibreCAD setup complete ==="
