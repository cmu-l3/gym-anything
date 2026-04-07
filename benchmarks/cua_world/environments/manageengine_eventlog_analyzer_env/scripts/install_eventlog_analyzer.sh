#!/bin/bash
# ManageEngine EventLog Analyzer Installation Script (pre_start hook)
#
# This script runs INSIDE the QEMU VM before the desktop starts.
#
# IMPORTANT: Uses background continuation pattern (#23) because the
# download (~600MB) + install (~10 min) exceeds hook timeouts.
# The install runs in background; post_start waits for the marker file.
#
# NOTE: EventLog Analyzer is a Java-based SIEM application.
# Default web UI port: 8095 (newer versions); 8400 (legacy)
# Default credentials: admin / admin

# Do NOT use set -e here (background install returns 0 immediately)

echo "=== ManageEngine EventLog Analyzer Pre-Start ==="

# Configure non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Install dependencies SYNCHRONOUSLY before backgrounding
# (these are needed by the background install script itself)
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
    rsyslog \
    firefox \
    scrot

# Install Python packages for verification scripts
pip3 install --no-cache-dir requests psycopg2-binary 2>/dev/null || true

# Create required directories
mkdir -p /opt/setup
mkdir -p /opt/ManageEngine

# =====================================================
# Write the background install script
# =====================================================
cat > /opt/setup/ela_install_bg.sh << 'BGEOF'
#!/bin/bash
# Background installation script for ManageEngine EventLog Analyzer
# Runs detached from the pre_start hook to avoid timeout

INSTALL_LOG="/tmp/ela_install.log"
MARKER="/tmp/ela_install_complete.marker"
ELA_BIN="/opt/setup/ManageEngine_EventlogAnalyzer.bin"
ELA_HOME="/opt/ManageEngine/EventLog"

log() { echo "[$(date '+%H:%M:%S')] $*" >> "$INSTALL_LOG"; }

log "=== Background Install Started ==="

# Download ManageEngine EventLog Analyzer
ELA_URL_PRIMARY="https://www.manageengine.com/log-management/9182736/ManageEngine_EventlogAnalyzer.bin"
ELA_URL_FALLBACK="https://info.manageengine.com/log-management/9182736/ManageEngine_EventlogAnalyzer.bin"

log "Downloading ManageEngine EventLog Analyzer (~600MB)..."
if ! wget -q --timeout=600 --tries=2 "$ELA_URL_PRIMARY" -O "$ELA_BIN" 2>>"$INSTALL_LOG"; then
    log "Primary URL failed, trying fallback..."
    if ! wget -q --timeout=600 --tries=3 "$ELA_URL_FALLBACK" -O "$ELA_BIN" 2>>"$INSTALL_LOG"; then
        log "ERROR: Both download URLs failed"
        echo "DOWNLOAD_FAILED" > "$MARKER"
        exit 1
    fi
fi

FILESIZE=$(stat -c%s "$ELA_BIN" 2>/dev/null || echo 0)
log "Downloaded: $FILESIZE bytes"
if [ "$FILESIZE" -lt 400000000 ]; then
    log "ERROR: File too small (expected ~600MB, got ${FILESIZE} bytes)"
    echo "DOWNLOAD_TOO_SMALL" > "$MARKER"
    exit 1
fi

chmod +x "$ELA_BIN"
log "Download complete."

# Create expect script for unattended console installation.
# Verified installer flow (from testing with this exact binary):
#   1.  Introduction: PRESS <ENTER> TO CONTINUE
#   2-13. EULA pages (12): PRESS <ENTER> TO CONTINUE (each)
#   14. DO YOU ACCEPT THE TERMS? (Y/N) -> Y
#   15. Register for technical support? (Y/N) -> N
#   16. Install folder (accept default /opt/ManageEngine/EventLog) -> Enter
#   17. IS THIS CORRECT? (Y/N) -> Y
#   18. Web Server Port [8095] -> Enter (accept default)
#   19. IS THIS CORRECT? (Y/N) -> Y (if shown)
#   20. Service install menu: ENTER A COMMA-SEPARATED LIST -> Enter (accept default)
#   21. Pre-Installation Summary -> Enter
#   22. PRESS ENTER TO INSTALL -> Enter
cat > /tmp/install_ela.expect << 'EXPECTEOF'
#!/usr/bin/expect -f
set timeout 900

log_user 1

spawn /opt/setup/ManageEngine_EventlogAnalyzer.bin -i console

expect {
    -re {PRESS <ENTER> TO CONTINUE} {
        after 300
        send "\r"
        exp_continue
    }
    -re {DO YOU ACCEPT THE TERMS OF THIS LICENSE AGREEMENT} {
        after 300
        send "Y\r"
        exp_continue
    }
    -re {register for technical support} {
        after 300
        send "N\r"
        exp_continue
    }
    -re {ENTER AN ABSOLUTE PATH, OR PRESS <ENTER> TO ACCEPT THE DEFAULT} {
        after 300
        send "\r"
        exp_continue
    }
    -re {IS THIS CORRECT\? \(Y/N\)} {
        after 300
        send "Y\r"
        exp_continue
    }
    -re {(Web Server Port|web server port|Tomcat Port)} {
        after 300
        send "\r"
        exp_continue
    }
    -re {ENTER A COMMA-SEPARATED LIST} {
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
    -re {(Installation Complete|Installation Successful|installation complete|installation successful)} {
        puts "\nInstallation completed successfully!"
    }
    eof {
        puts "\nInstaller process ended"
    }
    timeout {
        puts "\nWaiting for installer... (still installing)"
        exp_continue
    }
}
puts "\nEventLog Analyzer installation finished"
EXPECTEOF

chmod +x /tmp/install_ela.expect

log "Running EventLog Analyzer installer (takes 5-15 minutes)..."
expect /tmp/install_ela.expect >> "$INSTALL_LOG" 2>&1
EXPECT_EXIT=$?
log "Expect script exited with code $EXPECT_EXIT"

# Verify installation
if [ -d "$ELA_HOME/bin" ]; then
    log "Installation verified: $ELA_HOME/bin exists"
    ls -la "$ELA_HOME/bin/" >> "$INSTALL_LOG" 2>&1
else
    log "ERROR: Installation directory $ELA_HOME/bin not found"
    log "Contents of /opt/ManageEngine:"
    ls -la /opt/ManageEngine/ >> "$INSTALL_LOG" 2>&1 || true
    echo "INSTALL_FAILED" > "$MARKER"
    exit 1
fi

# Create ela-db-query utility
cat > /usr/local/bin/ela-db-query << 'DBEOF'
#!/bin/bash
# Execute SQL against EventLog Analyzer's bundled PostgreSQL
# Usage: ela-db-query "SELECT ..."
ELA_HOME="/opt/ManageEngine/EventLog"
PSQL_BIN="$ELA_HOME/pgsql/bin/psql"
DB_PORT="33335"
DB_NAME="eventlog"
DB_USER="eventloganalyzer"

if [ -f "$PSQL_BIN" ]; then
    "$PSQL_BIN" -h localhost -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "$1" 2>/dev/null
else
    DB_PORT="5432"
    psql -h localhost -p "$DB_PORT" -U postgres -d "$DB_NAME" -c "$1" 2>/dev/null || \
    su - postgres -c "psql -d '$DB_NAME' -c '$1'" 2>/dev/null || \
    echo "ERROR: Cannot connect to database"
fi
DBEOF
chmod +x /usr/local/bin/ela-db-query

# Create ela-api utility
cat > /usr/local/bin/ela-api << 'APIEOF'
#!/usr/bin/env python3
"""Utility for EventLog Analyzer REST API queries.
Usage: ela-api <endpoint> [method] [json_data]
"""
import sys
import requests
import json

BASE_URL = "http://localhost:8095"
ADMIN_USER = "admin"
ADMIN_PASS = "admin"

def get_session():
    s = requests.Session()
    r = s.post(f"{BASE_URL}/event/j_security_check",
               data={"j_username": ADMIN_USER, "j_password": ADMIN_PASS},
               allow_redirects=True, timeout=10)
    return s

def main():
    if len(sys.argv) < 2:
        print("Usage: ela-api <endpoint> [GET|POST] [json_data]")
        sys.exit(1)

    endpoint = sys.argv[1]
    method = sys.argv[2] if len(sys.argv) > 2 else "GET"
    data = json.loads(sys.argv[3]) if len(sys.argv) > 3 else None

    try:
        s = get_session()
        url = f"{BASE_URL}{endpoint}"
        if method == "POST":
            r = s.post(url, json=data, timeout=10)
        else:
            r = s.get(url, timeout=10)
        print(r.text)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
APIEOF
chmod +x /usr/local/bin/ela-api

# Clean up
rm -f /tmp/install_ela.expect
apt-get clean
rm -rf /var/lib/apt/lists/*

log "=== Installation Complete ==="
log "Install directory: $ELA_HOME"
log "Start: (cd $ELA_HOME/bin && bash app_ctl.sh run)"

# Write success marker
echo "OK" > "$MARKER"
log "Marker written: $MARKER"
BGEOF

chmod +x /opt/setup/ela_install_bg.sh

# =====================================================
# Start installation in background and return immediately
# =====================================================
echo "Starting ManageEngine EventLog Analyzer installation in background..."
nohup bash /opt/setup/ela_install_bg.sh > /tmp/ela_install_nohup.log 2>&1 &
BG_PID=$!
echo "Background install PID: $BG_PID"
echo "Progress log: /tmp/ela_install.log"
echo "Marker file: /tmp/ela_install_complete.marker"
echo ""
echo "pre_start returning immediately (post_start will wait for marker)"
echo "=== ManageEngine EventLog Analyzer Pre-Start Done ==="
