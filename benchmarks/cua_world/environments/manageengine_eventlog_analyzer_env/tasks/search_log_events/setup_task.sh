#!/bin/bash
# Setup for "search_log_events" task
# Generates real log activity and opens Firefox to Log Search

echo "=== Setting up Search Log Events task ==="

# Do NOT use set -euo pipefail (cross-cutting pattern #25)
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Ensure EventLog Analyzer is running
wait_for_eventlog_analyzer

# Generate additional real log activity before the task
# These are REAL authentication events on the Ubuntu system
echo "Generating real authentication failure log events..."
for i in {1..8}; do
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 \
        -o PasswordAuthentication=yes \
        baduser@127.0.0.1 "echo test" < /dev/null 2>/dev/null || true
    sleep 1
done
echo "Real authentication failure events generated in auth.log"

# Wait for rsyslog to forward the new events to EventLog Analyzer
sleep 5

# Refresh the log sample files with the latest logs
cp /var/log/auth.log /home/ga/log_samples/auth.log 2>/dev/null || true
cp /var/log/syslog /home/ga/log_samples/system.log 2>/dev/null || true
chown -R ga:ga /home/ga/log_samples/ 2>/dev/null || true

# Navigate Firefox to EventLog Analyzer Log Search section
ensure_firefox_on_ela "/event/AppsHome.do#/search/index"
sleep 5

# Clear any pre-populated search field (ELA may persist last search query across sessions)
# Click the search textarea at (420, 402) in 1920x1080, then press Escape to dismiss
# any active query-builder chips before the agent starts typing
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool mousemove 420 402 click 1
sleep 0.5
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape
sleep 0.5
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key ctrl+a
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Delete
sleep 1

# Take initial screenshot
take_screenshot /tmp/search_log_events_start.png

echo ""
echo "=== Search Log Events Task Ready ==="
echo ""
echo "Instructions:"
echo "  EventLog Analyzer Log Search page is open in Firefox."
echo "  You are logged in as admin."
echo "  The search interface is ready."
echo "  In the query field, search for authentication failure events:"
echo "    - Use the Basic search mode"
echo "    - Search for: authentication failure"
echo "    - Time Range: Last 7 days"
echo ""
echo "Real auth log data is at: /home/ga/log_samples/auth.log"
echo ""
