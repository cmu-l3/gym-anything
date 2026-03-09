#!/bin/bash
set -euo pipefail

echo "=== Setting up QBlade environment ==="

# Wait for desktop to be ready
sleep 5

# Find QBlade binary
QBLADE_BIN=$(find /opt/qblade -name "QBlade*" -type f -executable 2>/dev/null | head -1)
if [ -z "$QBLADE_BIN" ]; then
    QBLADE_BIN=$(find /opt/qblade -name "QBlade*" -type f 2>/dev/null | grep -iv '\.txt\|\.pdf\|\.md\|\.dll' | head -1)
    if [ -n "$QBLADE_BIN" ]; then
        chmod +x "$QBLADE_BIN"
    fi
fi

QBLADE_DIR=""
if [ -n "$QBLADE_BIN" ]; then
    QBLADE_DIR=$(dirname "$QBLADE_BIN")
    echo "QBlade binary found at: $QBLADE_BIN"
else
    echo "WARNING: QBlade binary not found"
    # List what was installed
    find /opt/qblade -maxdepth 3 -type f | head -20
fi

# Create QBlade launch script
cat > /home/ga/Desktop/launch_qblade.sh << LAUNCH_EOF
#!/bin/bash
export DISPLAY=:1

# Find QBlade binary
QBLADE_BIN=\$(find /opt/qblade -name "QBlade*" -type f -executable 2>/dev/null | head -1)
if [ -z "\$QBLADE_BIN" ]; then
    QBLADE_BIN=\$(find /opt/qblade -name "QBlade*" -type f 2>/dev/null | grep -iv '\.txt\|\.pdf\|\.md\|\.dll' | head -1)
fi

if [ -n "\$QBLADE_BIN" ]; then
    QBLADE_DIR=\$(dirname "\$QBLADE_BIN")
    export LD_LIBRARY_PATH="\$QBLADE_DIR:\${LD_LIBRARY_PATH:-}"
    export QT_QPA_PLATFORM=xcb
    cd "\$QBLADE_DIR"
    exec "\$QBLADE_BIN" "\$@"
else
    echo "ERROR: QBlade binary not found"
    zenity --error --text="QBlade binary not found in /opt/qblade" 2>/dev/null || true
fi
LAUNCH_EOF
chmod +x /home/ga/Desktop/launch_qblade.sh
chown ga:ga /home/ga/Desktop/launch_qblade.sh

# Create desktop entry for QBlade
cat > /home/ga/Desktop/QBlade.desktop << 'DESKTOP_EOF'
[Desktop Entry]
Name=QBlade
Comment=Wind Turbine Design & Simulation
Exec=/home/ga/Desktop/launch_qblade.sh %f
Icon=utilities-system-monitor
Terminal=false
Type=Application
Categories=Science;Engineering;
DESKTOP_EOF
chown ga:ga /home/ga/Desktop/QBlade.desktop
chmod +x /home/ga/Desktop/QBlade.desktop

# Create convenience symlinks
ln -sf /home/ga/Documents/airfoils /home/ga/Desktop/airfoils 2>/dev/null || true
ln -sf /home/ga/Documents/projects /home/ga/Desktop/projects 2>/dev/null || true

# Verify QBlade is accessible
echo "Verifying QBlade installation..."
if [ -n "$QBLADE_BIN" ]; then
    FILE_TYPE=$(file "$QBLADE_BIN" 2>/dev/null || echo "unknown")
    echo "QBlade binary type: $FILE_TYPE"

    # List sample projects if they exist (QBlade v0.96 uses "sample projects" dir with .wpa files)
    SAMPLE_DIR=$(find /opt/qblade -name "sample projects" -type d 2>/dev/null | head -1)
    if [ -z "$SAMPLE_DIR" ]; then
        SAMPLE_DIR=$(find /opt/qblade -iname "sampleprojects" -type d 2>/dev/null | head -1)
    fi
    if [ -n "$SAMPLE_DIR" ]; then
        echo "Sample projects found at: $SAMPLE_DIR"
        ls -la "$SAMPLE_DIR"/ 2>/dev/null || true
        echo "Sample projects available at: $SAMPLE_DIR"
        echo "Also available in /home/ga/Documents/sample_projects/"
    else
        echo "No sample projects directory found in QBlade installation"
    fi
fi

# Verify airfoil data is accessible
echo "Verifying airfoil data..."
ls -la /home/ga/Documents/airfoils/ 2>/dev/null || echo "WARNING: No airfoil data found"

echo "=== QBlade setup complete ==="
