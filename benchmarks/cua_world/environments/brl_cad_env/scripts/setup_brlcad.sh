#!/bin/bash
set -e

echo "=== Setting up BRL-CAD environment ==="

# Wait for desktop to be fully ready
sleep 5

# ============================================================
# Load BRL-CAD paths from install step
# ============================================================
BRLCAD_ROOT=$(cat /tmp/brlcad_root.txt 2>/dev/null || echo "/usr/brlcad")
DB_DIR=$(cat /tmp/brlcad_db_dir.txt 2>/dev/null || echo "")
export PATH="${BRLCAD_ROOT}/bin:$PATH"
export LD_LIBRARY_PATH="${BRLCAD_ROOT}/lib:$LD_LIBRARY_PATH"

echo "BRL-CAD root: ${BRLCAD_ROOT}"
echo "Sample DB dir: ${DB_DIR}"

# Verify MGED is accessible
if [ -f "${BRLCAD_ROOT}/bin/mged" ]; then
    echo "MGED found at: ${BRLCAD_ROOT}/bin/mged"
else
    echo "ERROR: mged not found at ${BRLCAD_ROOT}/bin/mged"
    exit 1
fi

# ============================================================
# Layer 1: Pre-configure MGED
# ============================================================
mkdir -p /home/ga/.brlcad

# Default .mgedrc (will be overwritten per-task)
cat > /home/ga/.mgedrc << 'MGEDEOF'
# BRL-CAD MGED startup configuration
MGEDEOF

chown -R ga:ga /home/ga/.brlcad
chown ga:ga /home/ga/.mgedrc

# ============================================================
# Create launcher script (MGED requires a TTY — must launch via xterm)
# ============================================================
cat > /usr/local/bin/launch_mged.sh << LAUNCHEOF
#!/bin/bash
export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority
export PATH=${BRLCAD_ROOT}/bin:/usr/local/bin:/usr/bin:/bin
export LD_LIBRARY_PATH=${BRLCAD_ROOT}/lib
exec xterm -title MGED_Terminal -geometry 80x6+0+900 -iconic -e "${BRLCAD_ROOT}/bin/mged \$1"
LAUNCHEOF
chmod +x /usr/local/bin/launch_mged.sh

# ============================================================
# Copy sample .g databases to user workspace
# ============================================================
mkdir -p /opt/brlcad_samples
mkdir -p /home/ga/Documents/BRLCAD

if [ -n "$DB_DIR" ] && [ -d "$DB_DIR" ]; then
    echo "Copying sample .g databases..."
    for model in moss.g m35.g havoc.g ktank.g star.g bldg391.g; do
        if [ -f "${DB_DIR}/${model}" ]; then
            cp "${DB_DIR}/${model}" /opt/brlcad_samples/
            echo "  Copied: ${model} ($(stat -c%s /opt/brlcad_samples/${model}) bytes)"
        else
            echo "  WARNING: ${model} not found in ${DB_DIR}"
        fi
    done
else
    echo "WARNING: Sample DB directory not available"
    find "${BRLCAD_ROOT}" -name "*.g" -type f 2>/dev/null | head -10
fi

# Verify critical sample files
if [ -f /opt/brlcad_samples/moss.g ]; then
    echo "moss.g: $(stat -c%s /opt/brlcad_samples/moss.g) bytes - OK"
else
    echo "WARNING: moss.g not available"
fi

if [ -f /opt/brlcad_samples/havoc.g ]; then
    echo "havoc.g: $(stat -c%s /opt/brlcad_samples/havoc.g) bytes - OK"
else
    echo "WARNING: havoc.g not available"
fi

# Copy samples to user workspace
cp /opt/brlcad_samples/*.g /home/ga/Documents/BRLCAD/ 2>/dev/null || true
chown -R ga:ga /home/ga/Documents/BRLCAD

# ============================================================
# Layer 2: Warm-up launch of MGED
# ============================================================
echo "Performing warm-up launch of MGED..."

# Create a temporary database for warm-up
su - ga -c "PATH=${BRLCAD_ROOT}/bin:\$PATH ${BRLCAD_ROOT}/bin/mged -c /tmp/warmup_test.g 'q'" 2>/dev/null || true
sleep 2

# Launch MGED via launcher script to create initial X11/Tk config
su - ga -c "setsid /usr/local/bin/launch_mged.sh /tmp/warmup_test.g > /tmp/mged_warmup.log 2>&1 &"
sleep 10

# Dismiss any dialog
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Return" 2>/dev/null || true
sleep 1

# Kill warm-up instance
pkill -f "mged" 2>/dev/null || true
pkill -f "xterm.*MGED" 2>/dev/null || true
sleep 2

rm -f /tmp/warmup_test.g
echo "Warm-up complete."

# ============================================================
# Create desktop launcher
# ============================================================
cat > /home/ga/Desktop/BRL-CAD_MGED.desktop << DESKTOPEOF
[Desktop Entry]
Type=Application
Name=BRL-CAD MGED
Exec=/usr/local/bin/launch_mged.sh
Icon=applications-engineering
Terminal=false
Categories=Graphics;3DGraphics;Engineering;
DESKTOPEOF
chmod +x /home/ga/Desktop/BRL-CAD_MGED.desktop
chown ga:ga /home/ga/Desktop/BRL-CAD_MGED.desktop

echo "=== BRL-CAD setup complete ==="
echo "MGED: ${BRLCAD_ROOT}/bin/mged"
echo "Launcher: /usr/local/bin/launch_mged.sh"
echo "Sample models in /home/ga/Documents/BRLCAD/"
ls -la /home/ga/Documents/BRLCAD/ 2>/dev/null || true
