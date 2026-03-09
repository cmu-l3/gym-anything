#!/bin/bash
# Do NOT use set -euo pipefail: some commands may return non-zero harmlessly

echo "=== Setting up draw.io Desktop environment ==="

# Create working directories for ga user
echo "Creating working directories..."
sudo -u ga mkdir -p /home/ga/Diagrams
sudo -u ga mkdir -p /home/ga/Diagrams/exports
sudo -u ga mkdir -p /home/ga/Desktop

# Copy real-world diagram assets to user directory
if [ -d "/workspace/assets/diagrams" ]; then
    cp -r /workspace/assets/diagrams/* /home/ga/Diagrams/ 2>/dev/null || true
    chown -R ga:ga /home/ga/Diagrams/
    echo "  - Copied diagram assets to ~/Diagrams/"
fi

# Find the drawio binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then
    DRAWIO_BIN="drawio"
elif [ -f /opt/drawio/drawio ]; then
    DRAWIO_BIN="/opt/drawio/drawio"
elif [ -f /usr/bin/drawio ]; then
    DRAWIO_BIN="/usr/bin/drawio"
fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found"
    exit 1
fi
echo "Using draw.io binary: $DRAWIO_BIN"

# Create desktop shortcut
cat > /home/ga/Desktop/drawio.desktop << DESKTOPEOF
[Desktop Entry]
Name=draw.io
Comment=Create UML, ER, flowchart, and architecture diagrams
Exec=$DRAWIO_BIN --no-sandbox %U
Icon=drawio
StartupNotify=true
Terminal=false
MimeType=application/vnd.jgraph.mxfile;application/drawio;
Categories=Graphics;FlowChart;
Type=Application
DESKTOPEOF
chown ga:ga /home/ga/Desktop/drawio.desktop
chmod +x /home/ga/Desktop/drawio.desktop
echo "  - Created desktop shortcut"

# Create launch helper that suppresses update checks
cat > /usr/local/bin/drawio-launch << LAUNCHEOF
#!/bin/bash
export DISPLAY=\${DISPLAY:-:1}
export DRAWIO_DISABLE_UPDATE=true
xhost +local: 2>/dev/null || true
$DRAWIO_BIN --no-sandbox --disable-update "\$@" > /tmp/drawio.log 2>&1 &
echo "draw.io launched (PID: \$!)"
LAUNCHEOF
chmod +x /usr/local/bin/drawio-launch

# Create CLI export helper
cat > /usr/local/bin/drawio-export << 'EXPORTEOF'
#!/bin/bash
if [ $# -lt 2 ]; then
    echo "Usage: drawio-export <input.drawio> <output.png|pdf|svg>"
    exit 1
fi
INPUT="$1"
OUTPUT="$2"
FORMAT="${OUTPUT##*.}"
if [ ! -f "$INPUT" ]; then
    echo "Error: Input file not found: $INPUT"
    exit 1
fi
echo "Exporting $INPUT to $OUTPUT (format: $FORMAT)..."
DRAWIO_DISABLE_UPDATE=true drawio --no-sandbox --export --format "$FORMAT" --output "$OUTPUT" "$INPUT" 2>/dev/null
if [ -f "$OUTPUT" ]; then
    echo "Export successful: $OUTPUT ($(stat --format=%s "$OUTPUT") bytes)"
else
    echo "Export may have failed"
fi
EXPORTEOF
chmod +x /usr/local/bin/drawio-export

# Install plyvel for potential LocalStorage manipulation by export scripts
pip3 install plyvel 2>/dev/null || true

# Pre-launch draw.io once to create initial config directory
# This speeds up the first task launch since config is already initialized
echo "Pre-launching draw.io to initialize config..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_prelaunched.log 2>&1 &"

# Wait for config to be created
for i in $(seq 1 20); do
    if [ -d "/home/ga/.config/draw.io/Local Storage/leveldb" ]; then
        echo "  - Config directory created after ${i} seconds"
        break
    fi
    sleep 1
done
sleep 3

# Kill draw.io - task scripts will relaunch with proper dialog handling
pkill -f drawio 2>/dev/null || true
sleep 2

# Remove singleton locks so task scripts can launch cleanly
rm -f /home/ga/.config/draw.io/SingletonCookie /home/ga/.config/draw.io/SingletonLock /home/ga/.config/draw.io/SingletonSocket 2>/dev/null || true

echo "=== draw.io Desktop configuration completed ==="
echo "draw.io is ready. Task scripts handle the startup dialog."
echo "NOTE: draw.io Desktop always shows a 'Create New / Open Existing' dialog."
echo "Task scripts dismiss it with Escape, then use Ctrl+O > Ctrl+L to open files."
