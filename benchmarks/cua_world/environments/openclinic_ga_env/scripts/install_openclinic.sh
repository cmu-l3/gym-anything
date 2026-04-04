#!/bin/bash
# OpenClinic GA Installation Script (pre_start hook)
# Installs OpenClinic GA hospital information system with bundled Tomcat + MySQL
# Access URL: http://localhost:10088/openclinic
# Default credentials: username=4, password=openclinic
#
# Strategy: Download and install runs as a background process to avoid SSH timeout.
# The actual install happens asynchronously; post_start hook waits for completion.

set -e

echo "=== Installing OpenClinic GA (pre_start) ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update

# Install required system packages
echo "Installing system dependencies..."
apt-get install -y \
    wget \
    curl \
    tar \
    gzip \
    net-tools \
    lsof \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    scrot \
    imagemagick \
    python3-pip \
    python3-pymysql \
    default-mysql-client \
    firefox

# Install pip packages for verification
pip3 install --no-cache-dir requests pymysql 2>/dev/null || true

# Create the install script that runs in background
cat > /tmp/install_openclinic_bg.sh << 'BGEOF'
#!/bin/bash
set -e
LOG=/home/ga/env_setup_openclinic_download.log
echo "=== OpenClinic GA Background Download Started $(date) ===" >> $LOG

OPENCLINIC_DEST="/tmp/openclinic.tar.gz"
DOWNLOADED=0

# Try multiple download URLs
for URL in \
    "https://sourceforge.net/projects/open-clinic/files/Releases/OpenClinic%20version%205/Linux%20%2864-bit%29/openclinic.ubuntu24.tar.gz/download" \
    "https://sourceforge.net/projects/open-clinic/files/Releases/OpenClinic%20version%205/Linux%20%2864-bit%29/openclinic.ubuntu.tar.gz/download"; do

    echo "Trying: $URL" >> $LOG
    if wget --timeout=600 --tries=3 -q -O "$OPENCLINIC_DEST" "$URL" 2>> $LOG; then
        FILESIZE=$(stat -c%s "$OPENCLINIC_DEST" 2>/dev/null || echo 0)
        if [ "$FILESIZE" -gt 10000000 ]; then
            echo "Downloaded successfully ($(( FILESIZE / 1024 / 1024 ))MB)" >> $LOG
            DOWNLOADED=1
            break
        else
            echo "File too small ($FILESIZE bytes), trying next URL..." >> $LOG
            rm -f "$OPENCLINIC_DEST"
        fi
    else
        echo "Download failed, trying next URL..." >> $LOG
    fi
done

if [ "$DOWNLOADED" -eq 0 ]; then
    echo "ERROR: Failed to download OpenClinic GA from all known URLs" >> $LOG
    touch /tmp/openclinic_install_failed
    exit 1
fi

# Extract to /opt/openclinic
echo "Extracting OpenClinic GA to /opt/openclinic..." >> $LOG
mkdir -p /opt
tar -xzf "$OPENCLINIC_DEST" -C /opt/ 2>> $LOG || tar -xzf "$OPENCLINIC_DEST" -C /opt/ --warning=no-timestamp 2>> $LOG

if [ ! -d /opt/openclinic ]; then
    echo "ERROR: /opt/openclinic directory not found after extraction" >> $LOG
    echo "Contents of /opt:" >> $LOG
    ls -la /opt/ >> $LOG
    touch /tmp/openclinic_install_failed
    exit 1
fi

echo "Extraction complete: $(ls /opt/openclinic/)" >> $LOG
rm -f "$OPENCLINIC_DEST"

# Run the OpenClinic setup script
echo "Running OpenClinic setup script..." >> $LOG
cd /opt/openclinic
chmod +x setup 2>/dev/null || true
chmod +x *.sh 2>/dev/null || true

# The setup script installs database and configures Tomcat
./setup >> $LOG 2>&1 || echo "WARNING: setup exited non-zero (may still work)" >> $LOG

echo "=== OpenClinic GA install complete $(date) ===" >> $LOG
touch /tmp/openclinic_install_done
BGEOF

chmod +x /tmp/install_openclinic_bg.sh

# Launch the download + install in the background using nohup
echo "Launching background download and install..."
nohup bash /tmp/install_openclinic_bg.sh > /home/ga/env_setup_openclinic_bg.log 2>&1 &
BG_PID=$!
echo "Background install PID: $BG_PID"
echo "$BG_PID" > /tmp/openclinic_install_pid

echo "=== pre_start hook complete (install running in background, PID=$BG_PID) ==="
echo "Monitor: tail -f /home/ga/env_setup_openclinic_download.log"
echo "Check completion: ls /tmp/openclinic_install_done"
