#!/bin/bash
set -e

echo "=== Installing VeraCrypt ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install prerequisites (exfat-utils replaced by exfatprogs on newer Ubuntu)
apt-get install -y \
    software-properties-common \
    gnupg \
    wget \
    curl \
    xdotool \
    wmctrl \
    x11-utils \
    xclip \
    python3-pip \
    libfuse2 \
    dmsetup \
    ntfs-3g \
    imagemagick

# Install exfat support (handle both old and new package names)
apt-get install -y exfatprogs 2>/dev/null || apt-get install -y exfat-utils 2>/dev/null || true

# Add unit193 PPA for VeraCrypt
add-apt-repository ppa:unit193/encryption -y
apt-get update

# Try to install VeraCrypt from PPA first
if apt-get install -y veracrypt 2>/dev/null; then
    echo "VeraCrypt installed from PPA"
else
    echo "PPA install failed, downloading VeraCrypt console installer from official site..."
    # Download the official VeraCrypt generic installer
    # The .tar.bz2 contains setup scripts for both GUI and console
    cd /tmp
    VERACRYPT_VER="1.26.20"
    wget -q "https://launchpad.net/veracrypt/trunk/${VERACRYPT_VER}/+download/veracrypt-${VERACRYPT_VER}-setup.tar.bz2" -O veracrypt-setup.tar.bz2 || \
    wget -q "https://github.com/veracrypt/VeraCrypt/releases/download/VeraCrypt_${VERACRYPT_VER}/veracrypt-${VERACRYPT_VER}-setup.tar.bz2" -O veracrypt-setup.tar.bz2 || true

    if [ -f veracrypt-setup.tar.bz2 ]; then
        tar xjf veracrypt-setup.tar.bz2
        # Run the GUI installer (x64) in non-interactive mode
        chmod +x veracrypt-*-setup-gui-x64
        ./veracrypt-*-setup-gui-x64 --nox11 --noexec --target /tmp/vc_extract 2>/dev/null || true

        if [ -d /tmp/vc_extract ]; then
            cd /tmp/vc_extract
            # The extracted package should contain installation files
            if [ -f usr/bin/veracrypt ]; then
                cp -r usr/* /usr/
            fi
        fi

        # Alternative: try the console installer
        if ! which veracrypt >/dev/null 2>&1; then
            cd /tmp
            chmod +x veracrypt-*-setup-console-x64 2>/dev/null || true
            echo -e "\n1\nyes\n" | ./veracrypt-*-setup-console-x64 2>/dev/null || true
        fi
    fi

    # If all else fails, try downloading the .deb directly
    if ! which veracrypt >/dev/null 2>&1; then
        echo "Trying to download VeraCrypt .deb package..."
        # Try multiple versions/URLs
        for ver in "1.26.20" "1.26.14" "1.25.9"; do
            wget -q "https://launchpad.net/veracrypt/trunk/${ver}/+download/veracrypt-${ver}-Ubuntu-22.04-amd64.deb" -O /tmp/veracrypt.deb 2>/dev/null && break
        done
        if [ -f /tmp/veracrypt.deb ]; then
            dpkg -i /tmp/veracrypt.deb 2>/dev/null || true
            apt-get install -f -y 2>/dev/null || true
        fi
    fi
fi

# Verify installation
if which veracrypt >/dev/null 2>&1; then
    veracrypt --version 2>/dev/null || echo "VeraCrypt installed (version check may need GUI)"
    echo "VeraCrypt binary location: $(which veracrypt)"
else
    echo "ERROR: VeraCrypt installation failed!"
    exit 1
fi

# Create directories for VeraCrypt volumes and mount points
mkdir -p /home/ga/Volumes
mkdir -p /home/ga/MountPoints/slot1
mkdir -p /home/ga/MountPoints/slot2
mkdir -p /home/ga/MountPoints/slot3
mkdir -p /home/ga/Keyfiles
chown -R ga:ga /home/ga/Volumes
chown -R ga:ga /home/ga/MountPoints
chown -R ga:ga /home/ga/Keyfiles

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== VeraCrypt installation complete ==="
