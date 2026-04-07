#!/bin/bash
echo "=== Setting up clean_orphan_origins_db task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ─── 1. Ensure services are running ──────────────────────────────────────────
echo "--- Ensuring SeisComP and MariaDB services are running ---"
systemctl start mariadb 2>/dev/null || true
ensure_scmaster_running

# ─── 2. Inject orphan origins into the database ──────────────────────────────
echo "--- Injecting test orphan origins ---"

ORPHANS_SCML="/tmp/inject_orphans.scml"
cat > "$ORPHANS_SCML" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<seiscomp xmlns="http://geofon.gfz-potsdam.de/ns/seiscomp3-schema/0.12" version="0.12">
  <EventParameters>
    <origin publicID="smi:org/gfz/orphan_test_1">
      <time><value>2024-01-01T12:00:00.0000Z</value></time>
      <latitude><value>37.2</value></latitude>
      <longitude><value>136.8</value></longitude>
      <depth><value>10.0</value></depth>
      <creationInfo><agencyID>TEST</agencyID><creationTime>2024-01-01T12:00:00.0000Z</creationTime></creationInfo>
    </origin>
    <origin publicID="smi:org/gfz/orphan_test_2">
      <time><value>2024-01-01T12:05:00.0000Z</value></time>
      <latitude><value>37.3</value></latitude>
      <longitude><value>136.7</value></longitude>
      <depth><value>15.0</value></depth>
      <creationInfo><agencyID>TEST</agencyID><creationTime>2024-01-01T12:05:00.0000Z</creationTime></creationInfo>
    </origin>
    <origin publicID="smi:org/gfz/orphan_test_3">
      <time><value>2024-01-01T12:10:00.0000Z</value></time>
      <latitude><value>37.1</value></latitude>
      <longitude><value>136.9</value></longitude>
      <depth><value>5.0</value></depth>
      <creationInfo><agencyID>TEST</agencyID><creationTime>2024-01-01T12:10:00.0000Z</creationTime></creationInfo>
    </origin>
  </EventParameters>
</seiscomp>
EOF

# Import the orphans via scdb (this creates Origins without Events, effectively making them orphans)
su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
    LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
    seiscomp exec scdb --plugins dbmysql -i $ORPHANS_SCML \
    -d mysql://sysop:sysop@localhost/seiscomp" 2>/dev/null || true

# ─── 3. Clean environment state ──────────────────────────────────────────────
rm -f /home/ga/orphan_origins.txt 2>/dev/null
rm -f "$ORPHANS_SCML"

# Open a terminal for the agent to start working
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"

sleep 3

# Focus the terminal
WID=$(DISPLAY=:1 wmctrl -l | grep -i "Terminal" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="