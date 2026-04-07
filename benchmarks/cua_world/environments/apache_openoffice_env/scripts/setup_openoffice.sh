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
        # Create default preferences with optimizations AND first-run wizard suppression
        cat > "$home_dir/.openoffice/4/user/registrymodifications.xcu" << 'PREFEOF'
<?xml version="1.0" encoding="UTF-8"?>
<oor:items xmlns:oor="http://openoffice.org/2001/registry" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <item oor:path="/org.openoffice.Setup/Office">
    <prop oor:name="ooSetupInstCompleted" oor:op="fuse">
      <value>true</value>
    </prop>
    <prop oor:name="LicenseAcceptDate" oor:op="fuse">
      <value>2024-01-01</value>
    </prop>
  </item>
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
    <prop oor:name="FirstRun" oor:op="fuse">
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
    # Mark desktop file as trusted (GNOME requirement)
    su - $username -c "DISPLAY=:1 dbus-launch gio set '$home_dir/Desktop/OpenOffice-Writer.desktop' metadata::trusted true" 2>/dev/null || true
    # Also copy to system-wide applications dir so GNOME recognizes it
    cp "$home_dir/Desktop/OpenOffice-Writer.desktop" /usr/share/applications/openoffice-writer.desktop 2>/dev/null || true
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

# Ensure first-run wizard is fully suppressed via config files
ensure_first_run_suppressed() {
    local username=$1
    local home_dir=$2

    echo "Ensuring first-run wizard is suppressed for $username..."

    # Create all profile subdirectories that OpenOffice expects
    mkdir -p "$home_dir/.openoffice/4/user/basic/Standard"
    mkdir -p "$home_dir/.openoffice/4/user/config"
    mkdir -p "$home_dir/.openoffice/4/user/database"
    mkdir -p "$home_dir/.openoffice/4/user/extensions"
    mkdir -p "$home_dir/.openoffice/4/user/gallery"
    mkdir -p "$home_dir/.openoffice/4/user/store"

    # Create script.xlb for Standard library
    cat > "$home_dir/.openoffice/4/user/basic/Standard/script.xlb" << 'XLBEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE library:library PUBLIC "-//OpenOffice.org//DTD OfficeDocument 1.0//EN" "library.dtd">
<library:library xmlns:library="http://openoffice.org/2000/library" library:name="Standard" library:link="false" library:readonly="false" library:passwordprotected="false"/>
XLBEOF

    # Create dialog.xlb for Standard library (prevents BASIC loading error)
    cat > "$home_dir/.openoffice/4/user/basic/Standard/dialog.xlb" << 'DLGEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE library:library PUBLIC "-//OpenOffice.org//DTD OfficeDocument 1.0//EN" "library.dtd">
<library:library xmlns:library="http://openoffice.org/2000/library" library:name="Standard" library:link="false" library:readonly="false" library:passwordprotected="false"/>
DLGEOF

    # Create script.xlc and dialog.xlc container files
    cat > "$home_dir/.openoffice/4/user/basic/script.xlc" << 'SCRIPTXLCEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE library:libraries PUBLIC "-//OpenOffice.org//DTD OfficeDocument 1.0//EN" "library.dtd">
<library:libraries xmlns:library="http://openoffice.org/2000/library" xmlns:xlink="http://www.w3.org/1999/xlink">
  <library:library library:name="Standard" xlink:href="$(USER)/basic/Standard/script.xlb/" xlink:type="simple" library:link="false"/>
</library:libraries>
SCRIPTXLCEOF

    cat > "$home_dir/.openoffice/4/user/basic/dialog.xlc" << 'DIALOGXLCEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE library:libraries PUBLIC "-//OpenOffice.org//DTD OfficeDocument 1.0//EN" "library.dtd">
<library:libraries xmlns:library="http://openoffice.org/2000/library" xmlns:xlink="http://www.w3.org/1999/xlink">
  <library:library library:name="Standard" xlink:href="$(USER)/basic/Standard/dialog.xlb/" xlink:type="simple" library:link="false"/>
</library:libraries>
DIALOGXLCEOF

    # Fix ownership of all created directories
    chown -R $username:$username "$home_dir/.openoffice"

    echo "  - First-run suppression configured via profile directories"
}

# Suppress first-run wizard for ga user
if id "ga" &>/dev/null; then
    ensure_first_run_suppressed "ga" "/home/ga"
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

# Warmup: launch OpenOffice once to complete the first-run wizard.
# OpenOffice 4.1.16 shows a setup wizard on first launch even with
# ooSetupInstCompleted=true. We dismiss it with keyboard navigation.
echo "Running first-launch warmup to dismiss setup wizard..."
su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer" 2>/dev/null &
WARMUP_PID=$!

# Wait for the wizard to appear, then dismiss it
WIZARD_DISMISSED=false
for i in $(seq 1 60); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Welcome to OpenOffice"; then
        echo "  - Wizard detected, dismissing..."
        sleep 2
        # Navigate through wizard: Tab*4 Enter goes past each page
        # Page 1: Welcome - click Next (Tab to Next, Enter)
        DISPLAY=:1 xdotool key Tab Tab Tab Tab Return 2>/dev/null || true
        sleep 2
        # Page 2: User info - click Finish (Tab to Finish, Enter)
        DISPLAY=:1 xdotool key Tab Tab Tab Tab Return 2>/dev/null || true
        sleep 3
        WIZARD_DISMISSED=true
        break
    fi
    sleep 1
done

# Dismiss any BASIC error dialogs that appear
for i in 1 2 3 4 5; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "OpenOffice 4.1.16"; then
        # Check if it's an error dialog (not the Start Center)
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
        sleep 0.5
    fi
done

# Close any remaining OpenOffice windows (Start Center, Writer)
DISPLAY=:1 wmctrl -c "OpenOffice" 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -c "OpenOffice" 2>/dev/null || true
sleep 1

# Kill all soffice processes from warmup
killall -9 soffice.bin soffice 2>/dev/null || true
sleep 2
rm -f /home/ga/.openoffice/4/.lock 2>/dev/null || true
rm -f /tmp/.~lock.* 2>/dev/null || true

if [ "$WIZARD_DISMISSED" = "true" ]; then
    echo "  - First-launch wizard dismissed successfully"
else
    echo "  - No wizard detected (may already be suppressed)"
fi

echo "=== Apache OpenOffice Writer configuration completed ==="

echo "Apache OpenOffice Writer is ready! Users can:"
echo "  - Launch from desktop shortcut"
echo "  - Run '/opt/openoffice4/program/soffice --writer' from terminal"
echo "  - Run '~/launch_writer.sh <file>' for optimized launch"
echo "  - Use 'openoffice-headless' for conversions"
