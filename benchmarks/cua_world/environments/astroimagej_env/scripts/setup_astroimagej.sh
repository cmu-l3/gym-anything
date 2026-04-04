#!/bin/bash
# set -euo pipefail

echo "=== Setting up AstroImageJ configuration ==="

# Set up AstroImageJ for a specific user
setup_user_aij() {
    local username=$1
    local home_dir=$2

    echo "Setting up AstroImageJ for user: $username"

    # Give recursive full permissions to cache
    sudo chmod -R 777 /home/$username/.cache 2>/dev/null || true

    # Create AstroImageJ directories
    sudo -u $username mkdir -p "$home_dir/.astroimagej"
    sudo -u $username mkdir -p "$home_dir/.config/AstroImageJ"
    sudo -u $username mkdir -p "$home_dir/AstroImages"
    sudo -u $username mkdir -p "$home_dir/AstroImages/raw"
    sudo -u $username mkdir -p "$home_dir/AstroImages/processed"
    sudo -u $username mkdir -p "$home_dir/AstroImages/lightcurves"
    sudo -u $username mkdir -p "$home_dir/AstroImages/measurements"
    sudo -u $username mkdir -p "$home_dir/Desktop"

    # Copy sample FITS files to user directory
    echo "  - Copying sample FITS files..."
    if [ -d "/opt/fits_samples" ]; then
        cp /opt/fits_samples/*.fits "$home_dir/AstroImages/raw/" 2>/dev/null || true
        chown -R $username:$username "$home_dir/AstroImages"
    fi

    # Create AstroImageJ preferences file
    # Note: AstroImageJ uses ImageJ preferences format
    cat > "$home_dir/.astroimagej/IJ_Prefs.txt" << 'PREFEOF'
.astroimagej.prefs.firstRun=false
.astroimagej.prefs.updateCheckOnStartup=false
.astroimagej.prefs.showWelcomeOnStartup=false
ij.y=0
ij.x=0
proxy.server=
proxy.port=-1
PREFEOF
    chown $username:$username "$home_dir/.astroimagej/IJ_Prefs.txt"
    echo "  - Created AstroImageJ preferences"

    # Create desktop shortcut
    cat > "$home_dir/Desktop/AstroImageJ.desktop" << 'DESKTOPEOF'
[Desktop Entry]
Name=AstroImageJ
Comment=Astronomical Image Processing and Photometry
Exec=/usr/local/bin/aij
Icon=java
StartupNotify=true
Terminal=false
Categories=Science;Astronomy;
Type=Application
DESKTOPEOF
    chown $username:$username "$home_dir/Desktop/AstroImageJ.desktop"
    chmod +x "$home_dir/Desktop/AstroImageJ.desktop"
    echo "  - Created desktop shortcut"

    # Create launch script
    cat > "$home_dir/launch_astroimagej.sh" << 'LAUNCHEOF'
#!/bin/bash
# Launch AstroImageJ with optimized settings
export DISPLAY=${DISPLAY:-:1}

# Ensure proper permissions for X11
xhost +local: 2>/dev/null || true

# Set memory options (AstroImageJ needs more memory for large FITS files)
export _JAVA_OPTIONS="-Xmx4g"

# Find AstroImageJ - check multiple possible locations for different versions
AIJ_PATH=""
for path in \
    "/usr/local/bin/aij" \
    "/opt/astroimagej/astroimagej/bin/AstroImageJ" \
    "/opt/astroimagej/AstroImageJ/bin/AstroImageJ" \
    "/opt/astroimagej/astroimagej/AstroImageJ" \
    "/opt/astroimagej/AstroImageJ/AstroImageJ" \
    "/opt/astroimagej/bin/AstroImageJ" \
    "/opt/astroimagej/astroimagej/aij" \
    "/opt/astroimagej/AstroImageJ/aij" \
    "/opt/astroimagej/aij"; do
    if [ -x "$path" ]; then
        AIJ_PATH="$path"
        break
    fi
done

if [ -z "$AIJ_PATH" ]; then
    echo "AstroImageJ not found!"
    echo "Checked locations:"
    ls -la /opt/astroimagej/ 2>/dev/null || echo "  /opt/astroimagej not found"
    exit 1
fi

echo "Found AstroImageJ at: $AIJ_PATH"

# Launch AstroImageJ
cd "$(dirname "$AIJ_PATH")" 2>/dev/null || cd /opt/astroimagej
"$AIJ_PATH" "$@" > /tmp/astroimagej_$USER.log 2>&1 &

echo "AstroImageJ started (PID: $!)"
echo "Log file: /tmp/astroimagej_$USER.log"
LAUNCHEOF
    chown $username:$username "$home_dir/launch_astroimagej.sh"
    chmod +x "$home_dir/launch_astroimagej.sh"
    echo "  - Created launch script"

    # Create utility script for FITS info
    cat > "/usr/local/bin/fits-info" << 'FITSINFOEOF'
#!/usr/bin/env python3
"""Display FITS file information."""
import sys
try:
    from astropy.io import fits

    if len(sys.argv) < 2:
        print("Usage: fits-info <fits_file>")
        sys.exit(1)

    filename = sys.argv[1]
    with fits.open(filename) as hdul:
        print(f"=== FITS File: {filename} ===")
        print(f"Number of HDUs: {len(hdul)}")
        for i, hdu in enumerate(hdul):
            print(f"\n--- HDU {i}: {type(hdu).__name__} ---")
            if hasattr(hdu, 'data') and hdu.data is not None:
                print(f"Data shape: {hdu.data.shape}")
                print(f"Data type: {hdu.data.dtype}")
            print("Header keywords:")
            for key in list(hdu.header.keys())[:20]:  # First 20 keys
                if key:
                    print(f"  {key}: {hdu.header.get(key, '')}")
except ImportError:
    print("astropy not installed")
except Exception as e:
    print(f"Error: {e}")
FITSINFOEOF
    chmod +x /usr/local/bin/fits-info

    # Set proper permissions
    chown -R $username:$username "$home_dir/.astroimagej"
    chown -R $username:$username "$home_dir/.config/AstroImageJ" 2>/dev/null || true
    chown -R $username:$username "$home_dir/AstroImages"
}

# Setup for ga user (the main VNC user)
if id "ga" &>/dev/null; then
    setup_user_aij "ga" "/home/ga"
fi

echo "=== AstroImageJ configuration completed ==="

# Do not auto-launch AstroImageJ here - let task scripts handle launching
echo "AstroImageJ is ready! Users can:"
echo "  - Launch from desktop shortcut"
echo "  - Run 'aij' from terminal"
echo "  - Run '~/launch_astroimagej.sh' for optimized launch"
echo "  - Use 'fits-info <file>' to inspect FITS files"
echo ""
echo "Sample FITS files are in ~/AstroImages/raw/"
