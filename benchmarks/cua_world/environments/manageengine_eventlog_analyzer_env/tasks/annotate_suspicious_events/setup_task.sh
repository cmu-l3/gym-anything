#!/bin/bash
echo "=== Setting up Annotate Suspicious Events task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure EventLog Analyzer is running
wait_for_eventlog_analyzer

# =====================================================
# Inject Real Log Data
# =====================================================
echo "Injecting suspicious SSH logs..."
# We use 'logger' to write to local syslog/auth.log, which ELA collects
TARGET_USER="forensic_target"
ATTACKER_IP="192.168.1.55"

# Generate a few "noise" events
logger -t sshd -p auth.info "Failed password for invalid user guest from 192.168.1.10 port 22 ssh2"
logger -t sshd -p auth.info "Accepted password for user admin from 192.168.1.5 port 22 ssh2"

# Generate the TARGET events
for i in {1..5}; do
    logger -t sshd -p auth.info "Failed password for invalid user ${TARGET_USER} from ${ATTACKER_IP} port 4444 ssh2"
    sleep 1
done

echo "Log injection complete. Forcing log rotation/flush..."
# Copy to log samples just in case ELA is configured to read from file import in this env
mkdir -p /home/ga/log_samples
cp /var/log/auth.log /home/ga/log_samples/auth.log 2>/dev/null || true
chmod 644 /home/ga/log_samples/auth.log 2>/dev/null || true

# Wait a moment for ELA to potentially pick up real-time syslog
sleep 5

# =====================================================
# UI Setup
# =====================================================
# Open Firefox directly to the Search page to save time
SEARCH_URL="/event/AppsHome.do#/search/index"
echo "Opening Firefox to $SEARCH_URL..."
ensure_firefox_on_ela "$SEARCH_URL"

# Wait for window and maximize
if wait_for_window "firefox\|mozilla\|ManageEngine" 30; then
    echo "Browser ready"
    WID=$(get_firefox_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
else
    echo "WARNING: Browser window not found"
fi

# Dismiss any potential popup dialogs (e.g. 'What's New')
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="