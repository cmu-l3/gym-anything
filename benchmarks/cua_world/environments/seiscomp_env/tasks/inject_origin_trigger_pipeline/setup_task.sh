#!/bin/bash
echo "=== Setting up inject_origin_trigger_pipeline task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ─── 1. Ensure system services are running ───────────────────────────────────
echo "--- Ensuring SeisComP services are running ---"
ensure_scmaster_running

# ─── 2. Clean up any previous state ──────────────────────────────────────────
echo "--- Cleaning up previous state ---"
# Stop scevent if it is currently running
su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
    LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
    seiscomp stop scevent" 2>/dev/null || true

sleep 2

# Remove the target event and origin from the database if they exist (ensures clean state)
TARGET_ORIGIN="Origin/20240101083015.123456.PARTNER"
mysql -u sysop -psysop seiscomp -e "DELETE FROM Event WHERE preferredOriginID='$TARGET_ORIGIN';" 2>/dev/null || true
mysql -u sysop -psysop seiscomp -e "DELETE FROM Origin WHERE publicID='$TARGET_ORIGIN';" 2>/dev/null || true

# Clear scevent log to ensure clean slate for the agent to tail
rm -f /home/ga/.seiscomp/log/scevent.log 2>/dev/null || true
touch /home/ga/.seiscomp/log/scevent.log
chown ga:ga /home/ga/.seiscomp/log/scevent.log

# Remove previous output file
rm -f /home/ga/Documents/new_event_id.txt 2>/dev/null || true

# ─── 3. Generate the external Origin SCML ────────────────────────────────────
echo "--- Generating external origin file ---"
mkdir -p /home/ga/Documents

cat > /home/ga/Documents/external_origin.scml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<seiscomp xmlns="http://geofon.gfz-potsdam.de/ns/seiscomp3-schema/0.12" version="0.12">
  <EventParameters>
    <origin publicID="Origin/20240101083015.123456.PARTNER">
      <time>
        <value>2024-01-01T08:30:15.000000Z</value>
      </time>
      <latitude>
        <value>37.15</value>
      </latitude>
      <longitude>
        <value>136.90</value>
      </longitude>
      <depth>
        <value>10.0</value>
      </depth>
      <creationInfo>
        <agencyID>PARTNER</agencyID>
        <creationTime>2024-01-01T08:31:00.000000Z</creationTime>
      </creationInfo>
      <evaluationMode>manual</evaluationMode>
    </origin>
  </EventParameters>
</seiscomp>
EOF

chown ga:ga /home/ga/Documents/external_origin.scml

# ─── 4. Open a terminal for the agent ────────────────────────────────────────
echo "--- Opening terminal ---"
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/Documents" &
sleep 3

# Focus and maximize terminal
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Terminal" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
fi

# Take initial screenshot
echo "--- Taking initial screenshot ---"
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="