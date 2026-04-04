#!/bin/bash
echo "=== Setting up add_data_source task ==="

source /workspace/scripts/task_utils.sh

# Record initial monitor inputs
echo "Recording initial state..."

INITIAL_MONITORS=$(splunk_list_monitors | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    entries = data.get('entry', [])
    paths = []
    for e in entries:
        name = e.get('name', '')
        paths.append(name)
    print(json.dumps(paths))
except:
    print('[]')
" 2>/dev/null)
echo "$INITIAL_MONITORS" > /tmp/initial_monitors.json

INITIAL_MONITOR_COUNT=$(echo "$INITIAL_MONITORS" | python3 -c "
import sys, json
try:
    print(len(json.load(sys.stdin)))
except:
    print(0)
" 2>/dev/null)
echo "$INITIAL_MONITOR_COUNT" > /tmp/initial_monitor_count

# Ensure the target file exists (create kern.log if it doesn't exist)
if [ ! -f /var/log/kern.log ]; then
    touch /var/log/kern.log
    chmod 644 /var/log/kern.log
    # Add some real kernel-style log entries
    echo "$(date '+%b %d %H:%M:%S') $(hostname) kernel: [    0.000000] Linux version $(uname -r)" >> /var/log/kern.log
    echo "$(date '+%b %d %H:%M:%S') $(hostname) kernel: [    0.000000] Command line: BOOT_IMAGE=/vmlinuz" >> /var/log/kern.log
    echo "$(date '+%b %d %H:%M:%S') $(hostname) kernel: [    0.524031] PCI: Using configuration type 1" >> /var/log/kern.log
    echo "$(date '+%b %d %H:%M:%S') $(hostname) kernel: [    1.234567] EXT4-fs (sda1): mounted filesystem" >> /var/log/kern.log
    echo "$(date '+%b %d %H:%M:%S') $(hostname) kernel: [    2.345678] NET: Registered protocol family 10" >> /var/log/kern.log
fi

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# CRITICAL: Ensure Firefox is running with Splunk visible BEFORE task starts
# Using 120 second timeout as recommended by audit
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    echo "Task setup FAILED - task start state is INVALID"
    take_screenshot /tmp/task_start_screenshot_FAILED.png
    # EXIT WITH ERROR - Do not continue with invalid state
    exit 1
fi

# Additional wait to ensure UI is fully loaded
sleep 3

# Take initial screenshot AFTER successful verification
take_screenshot /tmp/task_start_screenshot.png
echo "Task start screenshot taken"

echo "=== Task setup complete ==="
echo "Initial monitor count: $INITIAL_MONITOR_COUNT"
echo "Initial monitors: $INITIAL_MONITORS"
