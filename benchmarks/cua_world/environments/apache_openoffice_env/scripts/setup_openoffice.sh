#!/bin/bash
# set -euo pipefail

echo "=== Setting up Apache OpenOffice Writer configuration ==="

# Set up Writer for a specific user
setup_user_openoffice() {
    local username=$1
    local home_dir=$2

    echo "Setting up Apache OpenOffice Writer for user: $username"

    # Create directories as root first, then fix ownership
    mkdir -p "$home_dir/.openoffice/4/user"
    mkdir -p "$home_dir/.openoffice/4/user/template"
    mkdir -p "$home_dir/.openoffice/4/user/autotext"
    mkdir -p "$home_dir/Documents"
    mkdir -p "$home_dir/Documents/results"
    mkdir -p "$home_dir/Desktop"

    # Fix ownership of all created directories
    chown -R $username:$username "$home_dir/.openoffice"
    chown -R $username:$username "$home_dir/Documents"
    chown -R $username:$username "$home_dir/Desktop" 2>/dev/null || true

    # Copy custom preferences if available
    if [ -f "/workspace/config/registrymodifications.xcu" ]; then
        cp "/workspace/config/registrymodifications.xcu" "$home_dir/.openoffice/4/user/"
        chown $username:$username "$home_dir/.openoffice/4/user/registrymodifications.xcu"
        echo "  - Copied custom preferences"
    else
        # Create default preferences with optimizations
        cat > "$home_dir/.openoffice/4/user/registrymodifications.xcu" << 'PREFEOF'
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
        chown $username:$username "$home_dir/.openoffice/4/user/registrymodifications.xcu"
        echo "  - Created default preferences"
    fi

    # Set up desktop shortcut
    cat > "$home_dir/Desktop/OpenOffice-Writer.desktop" << DESKTOPEOF
[Desktop Entry]
Name=OpenOffice Writer
Comment=Apache OpenOffice Word Processor
Exec=/opt/openoffice4/program/soffice --writer %U
Icon=openoffice4-writer
StartupNotify=true
Terminal=false
MimeType=application/vnd.oasis.opendocument.text;application/msword;application/vnd.openxmlformats-officedocument.wordprocessingml.document;
Categories=Office;WordProcessor;
Type=Application
DESKTOPEOF
    chown $username:$username "$home_dir/Desktop/OpenOffice-Writer.desktop"
    chmod +x "$home_dir/Desktop/OpenOffice-Writer.desktop"
    echo "  - Created desktop shortcut"

    # Create launch script
    cat > "$home_dir/launch_writer.sh" << 'LAUNCHEOF'
#!/bin/bash
# Launch Apache OpenOffice Writer with optimized settings
export DISPLAY=${DISPLAY:-:1}

# Ensure proper permissions for X11
xhost +local: 2>/dev/null || true

# Launch Writer
if [ -x "/opt/openoffice4/program/soffice" ]; then
    /opt/openoffice4/program/soffice --writer "$@" > /tmp/writer_$USER.log 2>&1 &
else
    soffice --writer "$@" > /tmp/writer_$USER.log 2>&1 &
fi

echo "Apache OpenOffice Writer started"
echo "Log file: /tmp/writer_$USER.log"
LAUNCHEOF
    chown $username:$username "$home_dir/launch_writer.sh"
    chmod +x "$home_dir/launch_writer.sh"
    echo "  - Created launch script"
}

# Setup for ga user (the main VNC user)
if id "ga" &>/dev/null; then
    setup_user_openoffice "ga" "/home/ga"
fi

# Complete the first-run wizard automatically
# This runs OpenOffice once and clicks through the wizard dialogs
complete_first_run_wizard() {
    local username=$1
    local home_dir=$2

    echo "Completing first-run wizard for $username..."

    # Launch OpenOffice to trigger wizard creation
    sudo -u $username bash -c 'export DISPLAY=:1 && /opt/openoffice4/program/soffice --writer &'
    sleep 8

    # Check if wizard window appeared
    WIZARD_WID=$(sudo -u $username bash -c 'export DISPLAY=:1 && xdotool search --name "Welcome" 2>/dev/null | head -1')

    if [ -n "$WIZARD_WID" ]; then
        echo "  - First-run wizard detected, completing it..."

        # Step through the wizard pages using keyboard
        for i in 1 2 3 4; do
            sudo -u $username bash -c "export DISPLAY=:1 && xdotool key Tab Tab Tab Tab Return"
            sleep 2
        done

        echo "  - Wizard completed"
    else
        echo "  - No wizard detected (may have been skipped)"
    fi

    # Give it time to settle
    sleep 3

    # Close OpenOffice
    sudo -u $username bash -c 'pkill -f soffice' 2>/dev/null || true
    sleep 2

    echo "  - First-run wizard completion done"
}

# Complete first-run wizard for ga user
if id "ga" &>/dev/null && [ -n "$DISPLAY" ]; then
    complete_first_run_wizard "ga" "/home/ga"
fi

# Create utility scripts for verifiers
cat > /usr/local/bin/openoffice-headless << 'HEADLESSEOF'
#!/bin/bash
# Apache OpenOffice headless utility
# Usage: openoffice-headless <command> <file> [options]

SOFFICE_BIN="/opt/openoffice4/program/soffice"
if [ ! -x "$SOFFICE_BIN" ]; then
    SOFFICE_BIN="soffice"
fi

case "$1" in
    convert-pdf)
        $SOFFICE_BIN --headless --convert-to pdf --outdir "$(dirname "$2")" "$2"
        ;;
    convert-docx)
        $SOFFICE_BIN --headless --convert-to docx --outdir "$(dirname "$2")" "$2"
        ;;
    convert-odt)
        $SOFFICE_BIN --headless --convert-to odt --outdir "$(dirname "$2")" "$2"
        ;;
    convert-txt)
        $SOFFICE_BIN --headless --convert-to txt --outdir "$(dirname "$2")" "$2"
        ;;
    *)
        echo "Usage: openoffice-headless <convert-pdf|convert-docx|convert-odt|convert-txt> <file>"
        exit 1
        ;;
esac
HEADLESSEOF
chmod +x /usr/local/bin/openoffice-headless

echo "=== Apache OpenOffice Writer configuration completed ==="

echo "Apache OpenOffice Writer is ready! Users can:"
echo "  - Launch from desktop shortcut"
echo "  - Run '/opt/openoffice4/program/soffice --writer' from terminal"
echo "  - Run '~/launch_writer.sh <file>' for optimized launch"
echo "  - Use 'openoffice-headless' for conversions"
