#!/bin/bash
set -e

echo "=== Setting up LibreOffice Impress configuration ==="

# Wait for desktop to be ready
sleep 5

# Set up Impress for a specific user
setup_user_impress() {
    local username=$1
    local home_dir=$2

    echo "Setting up LibreOffice Impress for user: $username"

    # Create LibreOffice config directory
    sudo -u "$username" mkdir -p "$home_dir/.config/libreoffice/4/user"
    sudo -u "$username" mkdir -p "$home_dir/.config/libreoffice/4/user/template"
    sudo -u "$username" mkdir -p "$home_dir/.config/libreoffice/4/user/gallery"
    sudo -u "$username" mkdir -p "$home_dir/Documents/Presentations"
    sudo -u "$username" mkdir -p "$home_dir/Documents/results"
    sudo -u "$username" mkdir -p "$home_dir/Desktop"

    # Copy custom preferences if available
    if [ -f "/workspace/config/registrymodifications.xcu" ]; then
        sudo -u "$username" cp "/workspace/config/registrymodifications.xcu" "$home_dir/.config/libreoffice/4/user/"
        echo "  - Copied custom preferences"
    else
        # Create default preferences optimized for presentations
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
  <item oor:path="/org.openoffice.Office.Impress/Layout">
    <prop oor:name="Display" oor:op="fuse">
      <value>1</value>
    </prop>
  </item>
  <item oor:path="/org.openoffice.Office.Impress/Misc">
    <prop oor:name="StartWithTemplate" oor:op="fuse">
      <value>false</value>
    </prop>
  </item>
</oor:items>
PREFEOF
        chown "$username:$username" "$home_dir/.config/libreoffice/4/user/registrymodifications.xcu"
        echo "  - Created default preferences"
    fi

    # Copy default template if available
    if [ -f "/workspace/config/default_template.otp" ]; then
        sudo -u "$username" cp "/workspace/config/default_template.otp" "$home_dir/.config/libreoffice/4/user/template/"
        echo "  - Copied default template"
    fi

    # Set up desktop shortcut
    cat > "$home_dir/Desktop/LibreOffice-Impress.desktop" << DESKTOPEOF
[Desktop Entry]
Name=LibreOffice Impress
Comment=Presentation Application
Exec=libreoffice --impress %U
Icon=libreoffice-impress
StartupNotify=true
Terminal=false
MimeType=application/vnd.oasis.opendocument.presentation;application/vnd.ms-powerpoint;application/vnd.openxmlformats-officedocument.presentationml.presentation;
Categories=Office;Presentation;
Type=Application
DESKTOPEOF
    chown "$username:$username" "$home_dir/Desktop/LibreOffice-Impress.desktop"
    chmod +x "$home_dir/Desktop/LibreOffice-Impress.desktop"

    # Mark desktop file as trusted so GNOME doesn't show "Untrusted Desktop File" dialog
    su - "$username" -c "dbus-launch gio set $home_dir/Desktop/LibreOffice-Impress.desktop metadata::trusted true" 2>/dev/null || true

    echo "  - Created desktop shortcut"

    # Create launch script
    cat > "$home_dir/launch_impress.sh" << 'LAUNCHEOF'
#!/bin/bash
# Launch LibreOffice Impress with optimized settings
export DISPLAY=${DISPLAY:-:1}

# Launch Impress
setsid libreoffice --impress "$@" > /tmp/impress_$USER.log 2>&1 &

echo "LibreOffice Impress started (PID: $!)"
LAUNCHEOF
    chown "$username:$username" "$home_dir/launch_impress.sh"
    chmod +x "$home_dir/launch_impress.sh"
    echo "  - Created launch script"

    # === Warm-up launch to dismiss first-run dialogs ===
    echo "  - Performing warm-up launch to dismiss first-run dialogs..."
    su - "$username" -c "DISPLAY=:1 setsid libreoffice --impress" &
    local warmup_pid=$!
    sleep 15

    # Dismiss all startup dialogs: Template Selector, Tip of the Day, etc.
    for i in 1 2 3 4; do
        su - "$username" -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
        sleep 1
        su - "$username" -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
        sleep 1
    done

    # Gracefully close LibreOffice (Ctrl+Q)
    su - "$username" -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 5

    # Handle "Don't Save" dialog if it appears
    su - "$username" -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
    sleep 2

    # If still running, force kill
    pkill -f "soffice" 2>/dev/null || true
    wait $warmup_pid 2>/dev/null || true
    sleep 3
    pkill -9 -f "soffice" 2>/dev/null || true
    sleep 2

    # Clean up recovery files to prevent Document Recovery dialog
    rm -rf "$home_dir/.config/libreoffice/4/user/backup/" 2>/dev/null || true
    rm -rf /tmp/lu*/ 2>/dev/null || true
    rm -f /tmp/.~lock.* 2>/dev/null || true

    # Remove only recovery entries from registrymodifications.xcu
    # Keep all other settings that LibreOffice wrote during warm-up (like mstone, TipOfTheDay, etc.)
    local config_file="$home_dir/.config/libreoffice/4/user/registrymodifications.xcu"
    if [ -f "$config_file" ]; then
        python3 -c "
import re
with open('$config_file', 'r') as f:
    content = f.read()
# Remove recovery-related items
content = re.sub(r'<item oor:path=\"/org\.openoffice\.Office\.Recovery/RecoveryList\">.*?</item>', '', content, flags=re.DOTALL)
content = re.sub(r'<item oor:path=\"/org\.openoffice\.Office\.Recovery/RecoveryInfo\">.*?</item>', '', content, flags=re.DOTALL)
with open('$config_file', 'w') as f:
    f.write(content)
" 2>/dev/null || true
        chown "$username:$username" "$config_file"
        echo "  - Removed recovery entries from config (kept first-run dismissal settings)"
    fi

    echo "  - Warm-up launch complete (first-run dialogs dismissed, recovery files cleaned)"
}

# Setup for ga user (the main VNC user)
if id "ga" &>/dev/null; then
    setup_user_impress "ga" "/home/ga"
fi

# Create utility scripts for verifiers
cat > /usr/local/bin/impress-headless << 'HEADLESSEOF'
#!/bin/bash
# LibreOffice Impress headless utility
# Usage: impress-headless <command> <file> [options]

case "$1" in
    convert-pdf)
        libreoffice --headless --convert-to pdf --outdir "$(dirname "$2")" "$2"
        ;;
    convert-pptx)
        libreoffice --headless --convert-to pptx --outdir "$(dirname "$2")" "$2"
        ;;
    convert-odp)
        libreoffice --headless --convert-to odp --outdir "$(dirname "$2")" "$2"
        ;;
    convert-png)
        libreoffice --headless --convert-to png --outdir "$(dirname "$2")" "$2"
        ;;
    *)
        echo "Usage: impress-headless <convert-pdf|convert-pptx|convert-odp|convert-png> <file>"
        exit 1
        ;;
esac
HEADLESSEOF
chmod +x /usr/local/bin/impress-headless

echo "=== LibreOffice Impress configuration completed ==="
