#!/bin/bash
echo "=== Setting up Proximity Network task ==="

# Ensure safe PATH
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OrientDB to be ready
wait_for_orientdb 60

# Ensure demodb exists and is clean
# 1. Drop NearBy class if it exists (from previous runs)
echo "Cleaning up previous NearBy class..."
orientdb_sql "demodb" "DROP CLASS NearBy UNSAFE" > /dev/null 2>&1 || true

# 2. Verify Hotels and Restaurants exist (sanity check)
HOTEL_COUNT=$(orientdb_sql "demodb" "SELECT count(*) FROM Hotels" | grep -oE '"count":\s*[0-9]+' | grep -oE '[0-9]+' || echo "0")
REST_COUNT=$(orientdb_sql "demodb" "SELECT count(*) FROM Restaurants" | grep -oE '"count":\s*[0-9]+' | grep -oE '[0-9]+' || echo "0")

echo "Database check: Hotels=$HOTEL_COUNT, Restaurants=$REST_COUNT"

if [ "$HOTEL_COUNT" -eq "0" ] || [ "$REST_COUNT" -eq "0" ]; then
    echo "ERROR: demodb is missing required data. Re-seeding..."
    python3 /workspace/scripts/seed_demodb.py
fi

# Remove any existing report file
rm -f /home/ga/proximity_report.txt

# Launch Firefox to OrientDB Studio
echo "Launching Firefox..."
kill_firefox
su - ga -c "DISPLAY=:1 firefox -profile /home/ga/.mozilla/firefox/orientdb.profile \
    'http://localhost:2480/studio/index.html' &"
sleep 10

# Maximize Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
    DISPLAY=:1 wmctrl -ia "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="