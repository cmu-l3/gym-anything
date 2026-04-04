#!/bin/bash
# set -euo pipefail

echo "=== Setting up OpenLCA configuration ==="

# Set up OpenLCA for a specific user
setup_user_openlca() {
    local username=$1
    local home_dir=$2

    echo "Setting up OpenLCA for user: $username"

    # Give recursive full permissions to cache
    sudo chmod -R 777 /home/$username/.cache 2>/dev/null || true

    # Create OpenLCA workspace directories
    # OpenLCA uses a workspace directory for databases
    sudo -u $username mkdir -p "$home_dir/openLCA-data-1.4"
    sudo -u $username mkdir -p "$home_dir/openLCA-data-1.4/databases"
    sudo -u $username mkdir -p "$home_dir/.config/openLCA"
    sudo -u $username mkdir -p "$home_dir/Desktop"
    sudo -u $username mkdir -p "$home_dir/LCA_Results"
    sudo -u $username mkdir -p "$home_dir/LCA_Imports"

    # Copy USLCI database to user's import directory
    echo "  - Copying USLCI database for import..."
    if [ -f "/opt/openlca_data/uslci_database.zip" ]; then
        cp /opt/openlca_data/uslci_database.zip "$home_dir/LCA_Imports/uslci_database.zip"
        chown $username:$username "$home_dir/LCA_Imports/uslci_database.zip"
        echo "  - USLCI database copied to ~/LCA_Imports/"
    fi

    # Copy LCIA methods if available and valid (not 0-byte)
    if [ -f "/opt/openlca_data/lcia_methods.zip" ]; then
        LCIA_SIZE=$(stat -c%s "/opt/openlca_data/lcia_methods.zip" 2>/dev/null || echo "0")
        if [ "$LCIA_SIZE" -gt 100000 ]; then
            cp /opt/openlca_data/lcia_methods.zip "$home_dir/LCA_Imports/lcia_methods.zip"
            chown $username:$username "$home_dir/LCA_Imports/lcia_methods.zip"
            echo "  - LCIA methods copied to ~/LCA_Imports/ ($(du -h /opt/openlca_data/lcia_methods.zip | cut -f1))"
        else
            echo "  - LCIA methods file too small ($LCIA_SIZE bytes), skipping"
        fi
    fi

    # Create OpenLCA configuration to suppress first-run dialogs
    # OpenLCA 1.x/2.x uses Eclipse-based config files
    cat > "$home_dir/.config/openLCA/openlca.ini" << 'INIEOF'
# OpenLCA configuration
-nosplash
-vmargs
-Xmx4g
-Xms512m
-Dorg.eclipse.swt.browser.DefaultType=webkit
INIEOF
    chown $username:$username "$home_dir/.config/openLCA/openlca.ini"
    echo "  - Created OpenLCA configuration"

    # Create desktop shortcut
    cat > "$home_dir/Desktop/OpenLCA.desktop" << 'DESKTOPEOF'
[Desktop Entry]
Name=openLCA
Comment=Life Cycle Assessment Software
Exec=/usr/local/bin/openlca
Icon=java
StartupNotify=true
Terminal=false
Categories=Science;Education;
Type=Application
DESKTOPEOF
    chown $username:$username "$home_dir/Desktop/OpenLCA.desktop"
    chmod +x "$home_dir/Desktop/OpenLCA.desktop"
    echo "  - Created desktop shortcut"

    # Create launch script with optimized settings
    cat > "$home_dir/launch_openlca.sh" << 'LAUNCHEOF'
#!/bin/bash
# Launch OpenLCA with optimized settings
export DISPLAY=${DISPLAY:-:1}

# Ensure proper permissions for X11
xhost +local: 2>/dev/null || true

# Set memory options (OpenLCA needs more memory for large databases)
export _JAVA_OPTIONS="-Xmx4g -Xms512m"
export SWT_GTK3=1

# Find OpenLCA - check multiple possible locations
OPENLCA_PATH=""
for path in \
    "/usr/local/bin/openlca" \
    "/opt/openlca/openLCA/openLCA" \
    "/opt/openlca/openlca/openLCA" \
    "/opt/openlca/openLCA" \
    "/opt/openlca/openlca" \
    "/opt/openlca/openLCA/openLCA.sh" \
    "/opt/openlca/openLCA.sh" \
    "/snap/openlca/current/openLCA"; do
    if [ -x "$path" ]; then
        OPENLCA_PATH="$path"
        break
    fi
done

if [ -z "$OPENLCA_PATH" ]; then
    echo "OpenLCA not found!"
    echo "Checked standard locations. Searching..."
    OPENLCA_PATH=$(find /opt/openlca -maxdepth 3 -type f \( -name "openLCA" -o -name "openlca" \) -executable 2>/dev/null | head -1)
    if [ -z "$OPENLCA_PATH" ]; then
        echo "Could not find OpenLCA executable"
        exit 1
    fi
fi

echo "Found OpenLCA at: $OPENLCA_PATH"

# Launch OpenLCA
cd "$(dirname "$OPENLCA_PATH")" 2>/dev/null || cd /opt/openlca
"$OPENLCA_PATH" "$@" > /tmp/openlca_$USER.log 2>&1 &

echo "OpenLCA started (PID: $!)"
echo "Log file: /tmp/openlca_$USER.log"
LAUNCHEOF
    chown $username:$username "$home_dir/launch_openlca.sh"
    chmod +x "$home_dir/launch_openlca.sh"
    echo "  - Created launch script"

    # Set proper permissions
    chown -R $username:$username "$home_dir/openLCA-data-1.4" 2>/dev/null || true
    chown -R $username:$username "$home_dir/.config/openLCA" 2>/dev/null || true
    chown -R $username:$username "$home_dir/LCA_Results"
    chown -R $username:$username "$home_dir/LCA_Imports"
}

# Setup for ga user (the main VNC user)
if id "ga" &>/dev/null; then
    setup_user_openlca "ga" "/home/ga"
fi

echo "=== OpenLCA configuration completed ==="

# Do not auto-launch OpenLCA here - let task scripts handle launching
echo "OpenLCA is ready! Users can:"
echo "  - Launch from desktop shortcut"
echo "  - Run 'openlca' from terminal"
echo "  - Run '~/launch_openlca.sh' for optimized launch"
echo ""
echo "USLCI database is available for import at ~/LCA_Imports/uslci_database.zip"
echo "Results should be saved to ~/LCA_Results/"
