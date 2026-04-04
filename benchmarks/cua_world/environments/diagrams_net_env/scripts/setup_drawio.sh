#!/bin/bash
set -euo pipefail

echo "=== Setting up Diagrams.net (draw.io) Desktop configuration ==="

# Set up draw.io for a specific user
setup_user_drawio() {
    local username=$1
    local home_dir=$2

    echo "Setting up draw.io for user: $username"

    # Create diagrams directory for projects
    sudo -u $username mkdir -p "$home_dir/Diagrams"
    sudo -u $username mkdir -p "$home_dir/Diagrams/templates"
    sudo -u $username mkdir -p "$home_dir/Diagrams/exports"
    sudo -u $username mkdir -p "$home_dir/Desktop"

    # Create desktop shortcut
    cat > "$home_dir/Desktop/drawio.desktop" << 'DESKTOPEOF'
[Desktop Entry]
Name=diagrams.net
Comment=Create flowcharts, UML diagrams, network diagrams and more
Exec=/opt/drawio/drawio.AppImage --no-sandbox %U
Icon=drawio
StartupNotify=true
Terminal=false
MimeType=application/vnd.jgraph.mxfile;application/drawio;
Categories=Graphics;FlowChart;
Type=Application
DESKTOPEOF
    chown $username:$username "$home_dir/Desktop/drawio.desktop"
    chmod +x "$home_dir/Desktop/drawio.desktop"
    echo "  - Created desktop shortcut"

    # Create launch script with sandbox disabled (needed for containers)
    cat > "$home_dir/launch_drawio.sh" << 'LAUNCHEOF'
#!/bin/bash
# Launch draw.io with optimized settings for container environment
export DISPLAY=${DISPLAY:-:1}

# Ensure proper permissions for X11
xhost +local: 2>/dev/null || true

# Launch draw.io (--no-sandbox is required for container environments)
/opt/drawio/drawio.AppImage --no-sandbox "$@" > /tmp/drawio_$USER.log 2>&1 &

echo "draw.io started"
echo "Log file: /tmp/drawio_$USER.log"
LAUNCHEOF
    chown $username:$username "$home_dir/launch_drawio.sh"
    chmod +x "$home_dir/launch_drawio.sh"
    echo "  - Created launch script"

    # Copy sample diagram templates if available
    if [ -d "/workspace/assets/templates" ]; then
        cp -r /workspace/assets/templates/* "$home_dir/Diagrams/templates/" 2>/dev/null || true
        chown -R $username:$username "$home_dir/Diagrams/templates/"
        echo "  - Copied sample templates"
    fi

    # Set proper permissions
    chown -R $username:$username "$home_dir/Diagrams"

    echo "  - Setup complete for user $username"
}

# Setup for ga user (the main VNC user)
if id "ga" &>/dev/null; then
    setup_user_drawio "ga" "/home/ga"
fi

# Create utility script for verifying diagrams
cat > /usr/local/bin/drawio-info << 'INFOEOF'
#!/bin/bash
# Draw.io diagram info utility
# Usage: drawio-info <diagram_file.drawio>

if [ $# -eq 0 ]; then
    echo "Usage: drawio-info <diagram_file.drawio>"
    exit 1
fi

FILE="$1"

if [ ! -f "$FILE" ]; then
    echo "Error: File not found: $FILE"
    exit 1
fi

echo "=== Diagram Information ==="
echo "File: $FILE"
echo "Size: $(stat --format=%s "$FILE") bytes"
echo "Modified: $(stat --format=%y "$FILE")"
echo ""

# Check if it's a valid draw.io file (XML-based)
if file "$FILE" | grep -q "XML"; then
    echo "Format: XML-based draw.io file"

    # Count pages/diagrams
    PAGES=$(grep -o '<diagram' "$FILE" | wc -l)
    echo "Number of pages/diagrams: $PAGES"

    # Count cells (shapes)
    CELLS=$(grep -o '<mxCell' "$FILE" | wc -l)
    echo "Number of cells (shapes): $CELLS"

    # Extract diagram names if present
    echo ""
    echo "Diagram names:"
    grep -oP 'name="[^"]*"' "$FILE" | head -10 || echo "  (none found)"

elif file "$FILE" | grep -q "Zip"; then
    echo "Format: Compressed draw.io file"
    echo "Contents:"
    unzip -l "$FILE" 2>/dev/null || echo "  (could not list contents)"
else
    echo "Format: Unknown"
fi
INFOEOF
chmod +x /usr/local/bin/drawio-info

# Create utility script for exporting diagrams via command line
cat > /usr/local/bin/drawio-export << 'EXPORTEOF'
#!/bin/bash
# Draw.io diagram export utility
# Usage: drawio-export <input.drawio> <output.png|pdf|svg>

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

# Use draw.io CLI export capability
/opt/drawio/drawio.AppImage --no-sandbox --export --format "$FORMAT" --output "$OUTPUT" "$INPUT" 2>/dev/null

if [ -f "$OUTPUT" ]; then
    echo "Export successful: $OUTPUT"
    ls -la "$OUTPUT"
else
    echo "Export may have failed - check if draw.io is running"
fi
EXPORTEOF
chmod +x /usr/local/bin/drawio-export

echo "=== Diagrams.net (draw.io) Desktop configuration completed ==="

# Create utility script to dismiss update dialog
cat > /usr/local/bin/drawio-dismiss-update << 'DISMISSEOF'
#!/bin/bash
# Dismiss draw.io update dialog by pressing Escape
# This is needed because draw.io AppImage always checks for updates
export DISPLAY=${DISPLAY:-:1}

# Wait a moment for the dialog to appear
sleep 1

# Check if update dialog is present
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "update\|confirm"; then
    # Press Escape to dismiss the dialog
    DISPLAY=:1 xdotool key Escape
    sleep 0.5
    DISPLAY=:1 xdotool key Escape
    echo "Update dialog dismissed"
else
    echo "No update dialog detected"
fi
DISMISSEOF
chmod +x /usr/local/bin/drawio-dismiss-update

# Create utility script to launch draw.io and handle update dialog
cat > /usr/local/bin/drawio-launch << 'LAUNCHHELPEREOF'
#!/bin/bash
# Launch draw.io and automatically dismiss update dialog
export DISPLAY=${DISPLAY:-:1}

# Kill any existing draw.io processes
pkill -f "drawio" 2>/dev/null || true
sleep 1

# Launch draw.io
/opt/drawio/drawio.AppImage --no-sandbox "$@" > /tmp/drawio.log 2>&1 &
DRAWIO_PID=$!

# Wait for draw.io to start
sleep 5

# Dismiss update dialog if present (try multiple times)
for i in 1 2 3; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "update\|confirm"; then
        DISPLAY=:1 xdotool key Escape
        sleep 1
    fi
done

echo "draw.io launched (PID: $DRAWIO_PID)"
LAUNCHHELPEREOF
chmod +x /usr/local/bin/drawio-launch

# Do not auto-launch draw.io here - let task scripts handle launching
echo "draw.io is ready! Users can:"
echo "  - Launch from desktop shortcut"
echo "  - Run '/opt/drawio/drawio.AppImage --no-sandbox' from terminal"
echo "  - Run '~/launch_drawio.sh <file>' for optimized launch"
echo "  - Use 'drawio-launch' to launch with auto update dialog dismiss"
echo "  - Use 'drawio-dismiss-update' to dismiss update dialog if present"
echo "  - Use 'drawio-info <file>' to inspect diagram files"
echo "  - Use 'drawio-export <input> <output>' for CLI export"
