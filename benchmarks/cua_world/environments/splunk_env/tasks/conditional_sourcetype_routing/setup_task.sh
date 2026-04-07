#!/bin/bash
echo "=== Setting up Conditional Sourcetype Routing Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Splunk is running cleanly
if splunk_is_running; then
    echo "Splunk is running."
else
    echo "Starting Splunk..."
    sudo /opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt
    sleep 10
fi

# Clean up any pre-existing custom configurations in system/local that might interfere
sudo sed -i '/\[udp:\/\/5140\]/d' /opt/splunk/etc/system/local/inputs.conf 2>/dev/null || true
sudo sed -i '/\[legacy_app/d' /opt/splunk/etc/system/local/props.conf 2>/dev/null || true
sudo sed -i '/\[route_critical/d' /opt/splunk/etc/system/local/transforms.conf 2>/dev/null || true
sudo sed -i '/\[route_warn/d' /opt/splunk/etc/system/local/transforms.conf 2>/dev/null || true

# Launch Firefox for the agent
echo "Ensuring Firefox is visible..."
ensure_firefox_with_splunk 60 || true

# Launch a terminal for the agent to easily edit configs
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/opt/splunk/etc/system/local &"
    sleep 2
fi

# Maximize and arrange windows
WID_TERM=$(DISPLAY=:1 wmctrl -l | grep -i "Terminal" | awk '{print $1}' | head -1)
if [ -n "$WID_TERM" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID_TERM" 2>/dev/null || true
    # Make it take up half the screen or just focus it
fi

sleep 2
take_screenshot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="