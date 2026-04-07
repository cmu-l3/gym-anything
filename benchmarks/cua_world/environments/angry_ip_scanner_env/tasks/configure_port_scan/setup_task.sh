#!/bin/bash
echo "=== Setting up configure_port_scan task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any existing ipscan instances
kill_ipscan

# Reset port configuration to default (only 80,443)
# This ensures the agent needs to change it
PREFS_DIR="/home/ga/.java/.userPrefs/ipscan/scanner"
mkdir -p "$PREFS_DIR"
cat > "$PREFS_DIR/prefs.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE map SYSTEM "http://java.sun.com/dtd/preferences.dtd">
<map MAP_XML_VERSION="1.0">
  <entry key="maxThreads" value="100"/>
  <entry key="threadDelay" value="0"/>
  <entry key="pingingMethod" value="0"/>
  <entry key="pingTimeout" value="3000"/>
  <entry key="pingCount" value="3"/>
  <entry key="scanDeadHosts" value="false"/>
  <entry key="portTimeout" value="2000"/>
  <entry key="adaptPortTimeout" value="true"/>
  <entry key="portString" value="80,443"/>
</map>
EOF
chown -R ga:ga /home/ga/.java

# Ensure the reference data file is in place
mkdir -p /home/ga/Documents/network_data
if [ -f "/workspace/data/iana_common_ports.csv" ]; then
    cp /workspace/data/iana_common_ports.csv /home/ga/Documents/network_data/
    chown -R ga:ga /home/ga/Documents/network_data
    echo "  - IANA port reference data copied"
fi

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
echo "Angry IP Scanner is open. Agent should configure ports via Preferences."
