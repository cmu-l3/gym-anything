#!/bin/bash
set -e

echo "=== Setting up SRE Incident Timeline Task ==="

# 1. Create the incident log file (Real Data from GitLab 2017 Incident)
cat > /home/ga/Desktop/incident_log.txt << 'EOF'
INCIDENT LOG: DATABASE OUTAGE - 2017-01-31
---------------------------------------------
SEVERITY: CRITICAL
AFFECTED SYSTEMS: Production Database (PostgreSQL)

TIMELINE (All times in UTC):

[18:00] Spam attack initiates heavy load on the database.
[21:00] Write replication lag increases significantly due to load.
[22:00] Primary database connection pool exhaustion detected.
[23:00] Database team attempts to fix replication by wiping the secondary node.
[23:27] CRITICAL: Engineer accidentally executes "rm -rf" on the PRIMARY database directory (meant for secondary).
[23:28] Deletion detected and process stopped. Approximately 300GB of production data lost.
[00:00] (Feb 01) Restoration procedure begins using LVM snapshots from 6 hours prior.
[18:14] (Feb 01) Service fully restored and public access enabled.
EOF

chown ga:ga /home/ga/Desktop/incident_log.txt
chmod 644 /home/ga/Desktop/incident_log.txt

# 2. Clean up previous artifacts
rm -f /home/ga/Diagrams/incident_timeline.drawio 2>/dev/null || true
rm -f /home/ga/Diagrams/exports/incident_timeline.pdf 2>/dev/null || true
mkdir -p /home/ga/Diagrams/exports
chown -R ga:ga /home/ga/Diagrams

# 3. Record start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Launch draw.io to save agent startup time
# We use a helper function to dismiss update dialogs if they appear
echo "Launching draw.io..."
pkill -f drawio 2>/dev/null || true

su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox > /dev/null 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done

# Attempt to dismiss update dialog if it appears
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="