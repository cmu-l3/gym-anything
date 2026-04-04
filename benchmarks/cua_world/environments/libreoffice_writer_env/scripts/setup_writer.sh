#!/bin/bash
# set -euo pipefail

echo "=== Setting up LibreOffice Writer configuration ==="

# Set up Writer for a specific user
setup_user_writer() {
    local username=$1
    local home_dir=$2

    echo "Setting up LibreOffice Writer for user: $username"

    # Create LibreOffice config directory
    sudo -u $username mkdir -p "$home_dir/.config/libreoffice/4/user"
    sudo -u $username mkdir -p "$home_dir/.config/libreoffice/4/user/template"
    sudo -u $username mkdir -p "$home_dir/.config/libreoffice/4/user/autotext"
    sudo -u $username mkdir -p "$home_dir/Documents"
    sudo -u $username mkdir -p "$home_dir/Documents/results"
    sudo -u $username mkdir -p "$home_dir/Desktop"

    # Create versionrc to suppress "What's New" infobar on first launch
    local lo_version=$(libreoffice --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+\.\d+' | head -1)
    if [ -n "$lo_version" ]; then
        cat > "$home_dir/.config/libreoffice/4/user/versionrc" << VRCEOF
[Version]
AllLanguages=$lo_version
buildid=
VRCEOF
        chown $username:$username "$home_dir/.config/libreoffice/4/user/versionrc"
        echo "  - Created versionrc ($lo_version) to suppress What's New bar"
    fi

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
    <prop oor:name="ShowTipOfTheDay" oor:op="fuse">
      <value>false</value>
    </prop>
  </item>
  <item oor:path="/org.openoffice.Office.Recovery">
    <prop oor:name="Enabled" oor:op="fuse">
      <value>false</value>
    </prop>
  </item>
</oor:items>
PREFEOF
        chown $username:$username "$home_dir/.config/libreoffice/4/user/registrymodifications.xcu"
        echo "  - Created default preferences"
    fi

    # Set up desktop shortcut
    cat > "$home_dir/Desktop/LibreOffice-Writer.desktop" << DESKTOPEOF
[Desktop Entry]
Name=LibreOffice Writer
Comment=Word Processing Application
Exec=libreoffice --writer %U
Icon=libreoffice-writer
StartupNotify=true
Terminal=false
MimeType=application/vnd.oasis.opendocument.text;application/msword;application/vnd.openxmlformats-officedocument.wordprocessingml.document;
Categories=Office;WordProcessor;
Type=Application
DESKTOPEOF
    chown $username:$username "$home_dir/Desktop/LibreOffice-Writer.desktop"
    chmod +x "$home_dir/Desktop/LibreOffice-Writer.desktop"
    echo "  - Created desktop shortcut"

    # Create launch script
    cat > "$home_dir/launch_writer.sh" << 'LAUNCHEOF'
#!/bin/bash
# Launch LibreOffice Writer with optimized settings
export DISPLAY=${DISPLAY:-:1}

# Ensure proper permissions for X11
xhost +local: 2>/dev/null || true

# Launch Writer
libreoffice --writer "$@" > /tmp/writer_$USER.log 2>&1 &

echo "LibreOffice Writer started"
echo "Log file: /tmp/writer_$USER.log"
LAUNCHEOF
    chown $username:$username "$home_dir/launch_writer.sh"
    chmod +x "$home_dir/launch_writer.sh"
    echo "  - Created launch script"
}

# Setup for ga user (the main VNC user)
if id "ga" &>/dev/null; then
    setup_user_writer "ga" "/home/ga"
fi

# Create utility scripts for verifiers
cat > /usr/local/bin/writer-headless << 'HEADLESSEOF'
#!/bin/bash
# LibreOffice Writer headless utility
# Usage: writer-headless <command> <file> [options]

case "$1" in
    convert-pdf)
        libreoffice --headless --convert-to pdf --outdir "$(dirname "$2")" "$2"
        ;;
    convert-docx)
        libreoffice --headless --convert-to docx --outdir "$(dirname "$2")" "$2"
        ;;
    convert-odt)
        libreoffice --headless --convert-to odt --outdir "$(dirname "$2")" "$2"
        ;;
    convert-txt)
        libreoffice --headless --convert-to txt --outdir "$(dirname "$2")" "$2"
        ;;
    *)
        echo "Usage: writer-headless <convert-pdf|convert-docx|convert-odt|convert-txt> <file>"
        exit 1
        ;;
esac
HEADLESSEOF
chmod +x /usr/local/bin/writer-headless

echo "=== LibreOffice Writer configuration completed ==="

echo "LibreOffice Writer is ready! Users can:"
echo "  - Launch from desktop shortcut"
echo "  - Run 'libreoffice --writer' from terminal"
echo "  - Run '~/launch_writer.sh <file>' for optimized launch"
echo "  - Use 'writer-headless' for conversions"
