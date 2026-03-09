#!/bin/bash
# set -euo pipefail

echo "=== Setting up LibreOffice Calc configuration ==="

# Set up Calc for a specific user
setup_user_calc() {
    local username=$1
    local home_dir=$2
    
    echo "Setting up LibreOffice Calc for user: $username"
    
    # Create LibreOffice config directory
    sudo -u $username mkdir -p "$home_dir/.config/libreoffice/4/user"
    sudo -u $username mkdir -p "$home_dir/.config/libreoffice/4/user/template"
    sudo -u $username mkdir -p "$home_dir/.config/libreoffice/4/user/autotext"
    sudo -u $username mkdir -p "$home_dir/Documents"
    sudo -u $username mkdir -p "$home_dir/Documents/results"
    sudo -u $username mkdir -p "$home_dir/Desktop"
    
    # Copy custom preferences if available
    if [ -f "/workspace/config/registrymodifications.xcu" ]; then
        sudo -u $username cp "/workspace/config/registrymodifications.xcu" "$home_dir/.config/libreoffice/4/user/"
        echo "  - Copied custom preferences"
    else
        # Create default preferences with optimizations
        cat > "$home_dir/.config/libreoffice/4/user/registrymodifications.xcu" << 'PREFEOF'
<?xml version="1.0" encoding="UTF-8"?>
<oor:items xmlns:oor="http://openoffice.org/2001/registry" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <item oor:path="/org.openoffice.Office.Common/Save/Document">
    <prop oor:name="AutoSave" oor:op="fuse">
      <value>false</value>
    </prop>
    <prop oor:name="CreateBackup" oor:op="fuse">
      <value>false</value>
    </prop>
  </item>
  <item oor:path="/org.openoffice.Office.Common/Misc">
    <prop oor:name="UseOpenCL" oor:op="fuse">
      <value>false</value>
    </prop>
  </item>
  <item oor:path="/org.openoffice.Office.Calc/Calculate">
    <prop oor:name="DecimalPlaces" oor:op="fuse">
      <value>2</value>
    </prop>
  </item>
  <item oor:path="/org.openoffice.Office.Common/View">
    <prop oor:name="NewDocumentHandling" oor:op="fuse">
      <value>0</value>
    </prop>
  </item>
</oor:items>
PREFEOF
        chown $username:$username "$home_dir/.config/libreoffice/4/user/registrymodifications.xcu"
        echo "  - Created default preferences"
    fi
    
    # Set up desktop shortcut
    cat > "$home_dir/Desktop/LibreOffice-Calc.desktop" << DESKTOPEOF
[Desktop Entry]
Name=LibreOffice Calc
Comment=Spreadsheet Application
Exec=libreoffice --calc %U
Icon=libreoffice-calc
StartupNotify=true
Terminal=false
MimeType=application/vnd.oasis.opendocument.spreadsheet;application/vnd.ms-excel;application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;text/csv;
Categories=Office;Spreadsheet;
Type=Application
DESKTOPEOF
    chown $username:$username "$home_dir/Desktop/LibreOffice-Calc.desktop"
    chmod +x "$home_dir/Desktop/LibreOffice-Calc.desktop"
    echo "  - Created desktop shortcut"
    
    # Create launch script
    cat > "$home_dir/launch_calc.sh" << 'LAUNCHEOF'
#!/bin/bash
# Launch LibreOffice Calc with optimized settings
export DISPLAY=${DISPLAY:-:1}

# Ensure proper permissions for X11
xhost +local: 2>/dev/null || true

# Launch Calc
libreoffice --calc "$@" > /tmp/calc_$USER.log 2>&1 &

echo "LibreOffice Calc started"
echo "Log file: /tmp/calc_$USER.log"
LAUNCHEOF
    chown $username:$username "$home_dir/launch_calc.sh"
    chmod +x "$home_dir/launch_calc.sh"
    echo "  - Created launch script"
}

# Setup for ga user (the main VNC user)
if id "ga" &>/dev/null; then
    setup_user_calc "ga" "/home/ga"
fi

# Create utility scripts for verifiers
cat > /usr/local/bin/calc-headless << 'HEADLESSEOF'
#!/bin/bash
# LibreOffice Calc headless utility
# Usage: calc-headless <command> <file> [options]

case "$1" in
    convert-pdf)
        libreoffice --headless --convert-to pdf --outdir "$(dirname "$2")" "$2"
        ;;
    convert-xlsx)
        libreoffice --headless --convert-to xlsx --outdir "$(dirname "$2")" "$2"
        ;;
    convert-ods)
        libreoffice --headless --convert-to ods --outdir "$(dirname "$2")" "$2"
        ;;
    convert-csv)
        libreoffice --headless --convert-to csv --outdir "$(dirname "$2")" "$2"
        ;;
    *)
        echo "Usage: calc-headless <convert-pdf|convert-xlsx|convert-ods|convert-csv> <file>"
        exit 1
        ;;
esac
HEADLESSEOF
chmod +x /usr/local/bin/calc-headless

echo "=== LibreOffice Calc configuration completed ==="

# Launch Calc for the main VNC user (to speed up first access)
# Note libreoffice is installed, but the task script is responsible for launching the calc instance.

echo "LibreOffice Calc is ready! Users can:"
echo "  - Launch from desktop shortcut"
echo "  - Run 'libreoffice --calc' from terminal"
echo "  - Run '~/launch_calc.sh <file>' for optimized launch"
echo "  - Use 'calc-headless' for conversions"
