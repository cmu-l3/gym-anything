#!/bin/bash
# ManageEngine ServiceDesk Plus Installation Script (pre_start hook)
#
# Starts background download + install, returns fast (<5 min for apt setup).
# pre_task hooks will wait for /tmp/sdp_install_complete.marker
#
# Default credentials: administrator / administrator
# Web UI: https://localhost:8080/ (HTTPS with self-signed cert)

echo "=== ManageEngine ServiceDesk Plus Pre-Start ==="

export DEBIAN_FRONTEND=noninteractive

echo "Updating package lists..."
apt-get update -q

echo "Installing system dependencies..."
apt-get install -y \
    wget \
    curl \
    expect \
    net-tools \
    procps \
    wmctrl \
    xdotool \
    x11-utils \
    imagemagick \
    python3-pip \
    python3-requests \
    scrot \
    sysstat 2>/dev/null || true

echo "Installing Python packages..."
pip3 install --no-cache-dir requests psycopg2-binary pycryptodome 2>/dev/null || true

mkdir -p /opt/setup /opt/ManageEngine

# =====================================================
# Write the background install script
# =====================================================
cat > /tmp/sdp_install_bg.sh << 'BGEOF'
#!/bin/bash
INSTALL_LOG="/tmp/sdp_install.log"
MARKER="/tmp/sdp_install_complete.marker"
SDP_BIN="/opt/setup/ManageEngine_ServiceDesk_Plus.bin"
SDP_HOME="/opt/ManageEngine/ServiceDesk"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$INSTALL_LOG"; }
log "=== ServiceDesk Plus Background Install Started ==="

# Download ManageEngine ServiceDesk Plus (~747MB)
log "Downloading ManageEngine ServiceDesk Plus (~747MB)..."
DOWNLOADED=false
for url in \
    "https://download.manageengine.com/products/service-desk/91677414/ManageEngine_ServiceDesk_Plus_64bit.bin" \
    "https://www.manageengine.com/products/service-desk/91677414/ManageEngine_ServiceDesk_Plus_64bit.bin"; do
    log "  Trying: $url"
    if wget -q --timeout=1200 --tries=2 "$url" -O "$SDP_BIN" 2>>"$INSTALL_LOG"; then
        FILESIZE=$(stat -c%s "$SDP_BIN" 2>/dev/null || echo 0)
        if [ "$FILESIZE" -gt 100000000 ]; then
            log "  Download succeeded ($FILESIZE bytes)"
            DOWNLOADED=true
            break
        else
            log "  File too small ($FILESIZE bytes), trying next URL"
        fi
    else
        log "  URL failed: $?"
    fi
done

if [ "$DOWNLOADED" != "true" ]; then
    log "ERROR: All download URLs failed"
    echo "DOWNLOAD_FAILED" > "$MARKER"
    exit 1
fi

chmod +x "$SDP_BIN"

# Write the FIXED expect script (handles all installer prompts correctly)
cat > /tmp/install_sdp.expect << 'EXPECTEOF'
#!/usr/bin/expect -f
# Fixed expect script for ManageEngine ServiceDesk Plus installer
set timeout 1200

log_user 1

spawn /opt/setup/ManageEngine_ServiceDesk_Plus.bin -i console

expect {
    -re {PRESS <ENTER> TO CONTINUE} {
        after 300
        send "\r"
        exp_continue
    }
    -re {DO YOU ACCEPT THE TERMS OF THIS LICENSE AGREEMENT\? \(Y/N\):} {
        after 300
        send "Y\r"
        exp_continue
    }
    -re {ENTER A COMMA-SEPARATED LIST OF NUMBERS REPRESENTING THE DESIRED CHOICES} {
        after 300
        send "\r"
        exp_continue
    }
    -re {register for technical support\?\(Y/N\)} {
        after 300
        send "N\r"
        exp_continue
    }
    -re {register for technical support} {
        after 300
        send "N\r"
        exp_continue
    }
    -re {^Name: $} {
        after 300
        send "\r"
        exp_continue
    }
    -re {^Phone: $} {
        after 300
        send "\r"
        exp_continue
    }
    -re {^E-Mail} {
        after 300
        send "\r"
        exp_continue
    }
    -re {^Company} {
        after 300
        send "\r"
        exp_continue
    }
    -re {ENTER AN ABSOLUTE PATH, OR PRESS <ENTER> TO ACCEPT THE DEFAULT} {
        after 300
        send "/opt/ManageEngine/ServiceDesk\r"
        exp_continue
    }
    -re {IS THIS CORRECT\? \(Y/N\):} {
        after 300
        send "Y\r"
        exp_continue
    }
    -re {(Web.?Server Port|WebServer Port|Tomcat Port|HTTP Port|Enter.*Port.*Default.*8080)} {
        after 300
        send "\r"
        exp_continue
    }
    -re {Pre-Installation Summary} {
        after 300
        send "\r"
        exp_continue
    }
    -re {PRESS ENTER TO INSTALL} {
        after 300
        send "\r"
        exp_continue
    }
    -re {Press Enter to continue} {
        after 300
        send "\r"
        exp_continue
    }
    -re {(Installation Complete|Installation Successful|installation complete|installed successfully)} {
        puts "\nInstallation completed successfully!"
    }
    eof {
        puts "\nInstaller process ended"
    }
    timeout {
        puts "\nWaiting for installer..."
        exp_continue
    }
}
puts "\nServiceDesk Plus installation finished"
EXPECTEOF

chmod +x /tmp/install_sdp.expect

log "Running installer (takes 10-20 minutes)..."
expect /tmp/install_sdp.expect >> "$INSTALL_LOG" 2>&1
EXPECT_EXIT=$?
log "Installer exited: $EXPECT_EXIT"

# Verify installation
if [ -d "$SDP_HOME/bin" ]; then
    log "Success: $SDP_HOME/bin exists"
else
    # Check alternative paths
    for alt_path in "/root/ManageEngine/ServiceDesk" "/home/ga/ManageEngine/ServiceDesk"; do
        if [ -d "$alt_path/bin" ]; then
            log "Found at: $alt_path, creating symlink"
            ln -sfn "$alt_path" "$SDP_HOME" 2>/dev/null || true
            SDP_HOME="$alt_path"
            break
        fi
    done
    if [ ! -d "$SDP_HOME/bin" ]; then
        log "ERROR: Install failed - no bin dir found"
        ls -la /opt/ManageEngine/ >> "$INSTALL_LOG" 2>&1 || true
        echo "INSTALL_FAILED" > "$MARKER"
        exit 1
    fi
fi

# Clean up installer to free space
rm -f "$SDP_BIN" /tmp/install_sdp.expect
apt-get clean

log "=== Installation Complete ==="
echo "OK" > "$MARKER"
log "Marker written: $MARKER"
BGEOF

chmod +x /tmp/sdp_install_bg.sh

echo "Starting background installation..."
nohup bash /tmp/sdp_install_bg.sh > /tmp/sdp_install_nohup.log 2>&1 &
echo "Background PID: $!"
echo "Progress log: /tmp/sdp_install.log"
echo "Marker: /tmp/sdp_install_complete.marker"
echo "=== Pre-Start Done (background install running) ==="
