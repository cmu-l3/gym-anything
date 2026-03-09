#!/bin/bash
# set -euo pipefail

echo "=== Setting up ONLYOFFICE Desktop Editors configuration ==="

# Set up ONLYOFFICE for a specific user
setup_user_onlyoffice() {
    local username=$1
    local home_dir=$2

    echo "Setting up ONLYOFFICE for user: $username"

    # Create ONLYOFFICE config directories
    sudo -u $username mkdir -p "$home_dir/.config/onlyoffice"
    sudo -u $username mkdir -p "$home_dir/Documents"
    sudo -u $username mkdir -p "$home_dir/Documents/Spreadsheets"
    sudo -u $username mkdir -p "$home_dir/Documents/Presentations"
    sudo -u $username mkdir -p "$home_dir/Documents/TextDocuments"
    sudo -u $username mkdir -p "$home_dir/Desktop"

    # Create ONLYOFFICE preferences with optimized settings and memory limits
    cat > "$home_dir/.config/onlyoffice/DesktopEditors.conf" << 'CONFEOF'
[General]
language=en-US
spell-check=false
autosave=false
recovery=false
macros=warn

[Editor]
zoom=100
show-changes=false
collaborative-mode=false

[App]
window-maximized=true
toolbar-style=compact
recent-files-enabled=false

[Fonts]
cache-fonts=true
use-system-fonts=true

[Advanced]
memory-limit=4096
renderer-memory-limit=2048
cache-max-size=512
disable-gpu=false
enable-hardware-acceleration=false

[Performance]
use-alt-key-nav=false
animation-player=false
CONFEOF
    chown $username:$username "$home_dir/.config/onlyoffice/DesktopEditors.conf"
    echo "  - Created ONLYOFFICE preferences"

    # Set up desktop shortcuts for all three editors
    cat > "$home_dir/Desktop/ONLYOFFICE-Document.desktop" << DESKTOPEOF
[Desktop Entry]
Name=ONLYOFFICE Document Editor
Comment=Document Editor
Exec=onlyoffice-desktopeditors --new:word %U
Icon=onlyoffice-desktopeditors
StartupNotify=true
Terminal=false
Type=Application
Categories=Office;WordProcessor;
MimeType=application/vnd.openxmlformats-officedocument.wordprocessingml.document;application/msword;application/vnd.oasis.opendocument.text;
DESKTOPEOF
    chown $username:$username "$home_dir/Desktop/ONLYOFFICE-Document.desktop"
    chmod +x "$home_dir/Desktop/ONLYOFFICE-Document.desktop"

    cat > "$home_dir/Desktop/ONLYOFFICE-Spreadsheet.desktop" << DESKTOPEOF
[Desktop Entry]
Name=ONLYOFFICE Spreadsheet Editor
Comment=Spreadsheet Editor
Exec=onlyoffice-desktopeditors --new:cell %U
Icon=onlyoffice-desktopeditors
StartupNotify=true
Terminal=false
Type=Application
Categories=Office;Spreadsheet;
MimeType=application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;application/vnd.ms-excel;application/vnd.oasis.opendocument.spreadsheet;
DESKTOPEOF
    chown $username:$username "$home_dir/Desktop/ONLYOFFICE-Spreadsheet.desktop"
    chmod +x "$home_dir/Desktop/ONLYOFFICE-Spreadsheet.desktop"

    cat > "$home_dir/Desktop/ONLYOFFICE-Presentation.desktop" << DESKTOPEOF
[Desktop Entry]
Name=ONLYOFFICE Presentation Editor
Comment=Presentation Editor
Exec=onlyoffice-desktopeditors --new:slide %U
Icon=onlyoffice-desktopeditors
StartupNotify=true
Terminal=false
Type=Application
Categories=Office;Presentation;
MimeType=application/vnd.openxmlformats-officedocument.presentationml.presentation;application/vnd.ms-powerpoint;application/vnd.oasis.opendocument.presentation;
DESKTOPEOF
    chown $username:$username "$home_dir/Desktop/ONLYOFFICE-Presentation.desktop"
    chmod +x "$home_dir/Desktop/ONLYOFFICE-Presentation.desktop"
    echo "  - Created desktop shortcuts"

    # Create launch scripts for each editor
    cat > "$home_dir/launch_document.sh" << 'LAUNCHEOF'
#!/bin/bash
# Launch ONLYOFFICE Document Editor
export DISPLAY=${DISPLAY:-:1}
xhost +local: 2>/dev/null || true

if [ -z "$1" ]; then
    onlyoffice-desktopeditors --new:word > /tmp/onlyoffice_doc_$USER.log 2>&1 &
else
    onlyoffice-desktopeditors "$1" > /tmp/onlyoffice_doc_$USER.log 2>&1 &
fi

echo "ONLYOFFICE Document Editor started"
echo "Log file: /tmp/onlyoffice_doc_$USER.log"
LAUNCHEOF

    cat > "$home_dir/launch_spreadsheet.sh" << 'LAUNCHEOF'
#!/bin/bash
# Launch ONLYOFFICE Spreadsheet Editor
export DISPLAY=${DISPLAY:-:1}
xhost +local: 2>/dev/null || true

if [ -z "$1" ]; then
    onlyoffice-desktopeditors --new:cell > /tmp/onlyoffice_sheet_$USER.log 2>&1 &
else
    onlyoffice-desktopeditors "$1" > /tmp/onlyoffice_sheet_$USER.log 2>&1 &
fi

echo "ONLYOFFICE Spreadsheet Editor started"
echo "Log file: /tmp/onlyoffice_sheet_$USER.log"
LAUNCHEOF

    cat > "$home_dir/launch_presentation.sh" << 'LAUNCHEOF'
#!/bin/bash
# Launch ONLYOFFICE Presentation Editor
export DISPLAY=${DISPLAY:-:1}
xhost +local: 2>/dev/null || true

if [ -z "$1" ]; then
    onlyoffice-desktopeditors --new:slide > /tmp/onlyoffice_pres_$USER.log 2>&1 &
else
    onlyoffice-desktopeditors "$1" > /tmp/onlyoffice_pres_$USER.log 2>&1 &
fi

echo "ONLYOFFICE Presentation Editor started"
echo "Log file: /tmp/onlyoffice_pres_$USER.log"
LAUNCHEOF

    chown $username:$username "$home_dir/launch_document.sh"
    chown $username:$username "$home_dir/launch_spreadsheet.sh"
    chown $username:$username "$home_dir/launch_presentation.sh"
    chmod +x "$home_dir/launch_document.sh"
    chmod +x "$home_dir/launch_spreadsheet.sh"
    chmod +x "$home_dir/launch_presentation.sh"
    echo "  - Created launch scripts"
}

# Setup for ga user (the main VNC user)
if id "ga" &>/dev/null; then
    setup_user_onlyoffice "ga" "/home/ga"
fi

# Create OOM protection script for ONLYOFFICE
cat > /usr/local/bin/onlyoffice-oom-protect << 'OOMEOF'
#!/bin/bash
# Adjust OOM score for ONLYOFFICE processes to make them less likely to be killed
# Lower score = less likely to be killed (-1000 to 1000)

for pid in $(pgrep -f "onlyoffice-desktopeditors|DesktopEditors"); do
    if [ -f "/proc/$pid/oom_score_adj" ]; then
        echo -500 > /proc/$pid/oom_score_adj 2>/dev/null || true
        echo "OOM score adjusted for PID $pid"
    fi
done
OOMEOF
chmod +x /usr/local/bin/onlyoffice-oom-protect

echo "✅ OOM protection script created"

# Create utility scripts for document operations
cat > /usr/local/bin/onlyoffice-convert << 'CONVERTEOF'
#!/bin/bash
# ONLYOFFICE document conversion utility
# Usage: onlyoffice-convert <input-file> <output-format>

if [ $# -lt 2 ]; then
    echo "Usage: onlyoffice-convert <input-file> <output-format>"
    echo "Formats: pdf, docx, xlsx, pptx, odt, ods, odp, txt, csv"
    exit 1
fi

INPUT_FILE="$1"
OUTPUT_FORMAT="$2"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file not found: $INPUT_FILE"
    exit 1
fi

# Use LibreOffice for conversion (more reliable in headless mode)
OUTPUT_DIR="$(dirname "$INPUT_FILE")"
libreoffice --headless --convert-to "$OUTPUT_FORMAT" --outdir "$OUTPUT_DIR" "$INPUT_FILE"

if [ $? -eq 0 ]; then
    echo "Conversion successful"
else
    echo "Conversion failed"
    exit 1
fi
CONVERTEOF
chmod +x /usr/local/bin/onlyoffice-convert

echo "=== ONLYOFFICE Desktop Editors configuration completed ==="

echo "ONLYOFFICE is ready! Users can:"
echo "  - Launch from desktop shortcuts"
echo "  - Run 'onlyoffice-desktopeditors' from terminal"
echo "  - Run '~/launch_document.sh <file>' for Document Editor"
echo "  - Run '~/launch_spreadsheet.sh <file>' for Spreadsheet Editor"
echo "  - Run '~/launch_presentation.sh <file>' for Presentation Editor"
echo "  - Use 'onlyoffice-convert <file> <format>' for conversions"
