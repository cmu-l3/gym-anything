#!/bin/bash
echo "=== Setting up export_scan_results task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any existing ipscan instances
kill_ipscan

# Ensure network services are running as real scan targets
systemctl start ssh 2>/dev/null || service ssh start 2>/dev/null || true
systemctl start apache2 2>/dev/null || service apache2 start 2>/dev/null || true

# Verify services are listening
echo "Checking scan target services..."
if ss -tlnp | grep -q ":22 "; then
    echo "  - SSH is listening on port 22"
else
    echo "  - WARNING: SSH not listening"
fi
if ss -tlnp | grep -q ":80 "; then
    echo "  - Apache is listening on port 80"
else
    echo "  - WARNING: Apache not listening"
fi

# Configure scanner preferences with ports that match running services
PREFS_DIR="/home/ga/.java/.userPrefs/ipscan/scanner"
mkdir -p "$PREFS_DIR"
cat > "$PREFS_DIR/prefs.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE map SYSTEM "http://java.sun.com/dtd/preferences.dtd">
<map MAP_XML_VERSION="1.0">
  <entry key="maxThreads" value="100"/>
  <entry key="pingingMethod" value="0"/>
  <entry key="pingTimeout" value="3000"/>
  <entry key="pingCount" value="3"/>
  <entry key="scanDeadHosts" value="false"/>
  <entry key="portTimeout" value="2000"/>
  <entry key="portString" value="22,80,443"/>
</map>
EOF
chown -R ga:ga /home/ga/.java

# Create output directory
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any previous export file
rm -f /home/ga/Documents/scan_results.csv

# Launch Angry IP Scanner
echo "Launching Angry IP Scanner..."
su - ga -c "DISPLAY=:1 setsid ipscan > /tmp/ipscan_task.log 2>&1 &"

# Wait for the window to appear
wait_for_process "ipscan" 15
wait_for_window "Angry IP Scanner" 30

# Dismiss Getting Started dialog if it appears
dismiss_ipscan_dialogs 10

# Focus and maximize the window
sleep 1
focus_and_maximize "Angry IP Scanner"

echo "=== Task setup complete ==="
echo "Angry IP Scanner is open. Agent should start scan and export results."
