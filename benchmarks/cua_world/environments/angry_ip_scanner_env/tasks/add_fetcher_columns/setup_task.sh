#!/bin/bash
echo "=== Setting up add_fetcher_columns task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any existing ipscan instances
kill_ipscan

# Ensure preferences are clean with default fetchers only
# (The default fetchers in Angry IP Scanner are: IP, Ping, Hostname, Ports)
PREFS_DIR="/home/ga/.java/.userPrefs/ipscan"
mkdir -p "$PREFS_DIR/gui"
mkdir -p "$PREFS_DIR/scanner"

# Reset GUI prefs to ensure default fetcher columns
cat > "$PREFS_DIR/gui/prefs.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE map SYSTEM "http://java.sun.com/dtd/preferences.dtd">
<map MAP_XML_VERSION="1.0">
  <entry key="firstRun" value="false"/>
  <entry key="versionCheckEnabled" value="false"/>
  <entry key="askScanConfirmation" value="false"/>
  <entry key="displayMethod" value="ALL"/>
</map>
EOF
chown -R ga:ga /home/ga/.java

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
echo "Angry IP Scanner is open with default fetchers. Agent should add Web Detect and MAC Vendor."
