#!/bin/bash
set -e
echo "=== Setting up create_booking_system task ==="

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Source OrientDB utilities
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin
source /workspace/scripts/task_utils.sh

# Wait for OrientDB to be ready
wait_for_orientdb 60

echo "Cleaning up previous task artifacts..."

# Helper to execute SQL quietly
quiet_sql() {
    orientdb_sql "demodb" "$1" > /dev/null 2>&1 || true
}

# Clean state: Delete data, drop classes, drop sequences
# Order matters: Edges -> Vertices -> Classes -> Sequences
quiet_sql "DELETE EDGE HasBooking"
quiet_sql "DELETE EDGE BookedAt"
quiet_sql "DELETE VERTEX Bookings"
quiet_sql "DROP CLASS HasBooking UNSAFE"
quiet_sql "DROP CLASS BookedAt UNSAFE"
quiet_sql "DROP CLASS Bookings UNSAFE"
quiet_sql "DROP SEQUENCE booking_seq"
quiet_sql "DROP SEQUENCE invoice_seq"

# Remove report file
rm -f /home/ga/bookings_report.json

# Verify required ground truth data exists (Profiles and Hotels)
echo "Verifying ground truth data..."
MISSING_DATA=false

# Check a few profiles
for email in "john.smith@example.com" "luca.rossi@example.com"; do
    CNT=$(orientdb_sql "demodb" "SELECT COUNT(*) as c FROM Profiles WHERE Email='$email'" | \
        python3 -c "import sys,json; print(json.load(sys.stdin).get('result',[{}])[0].get('c',0))" 2>/dev/null || echo "0")
    if [ "$CNT" -eq "0" ]; then
        echo "Missing profile: $email"
        MISSING_DATA=true
    fi
done

# Check a few hotels
for hotel in "Hotel Artemide" "The Plaza Hotel"; do
    CNT=$(orientdb_sql "demodb" "SELECT COUNT(*) as c FROM Hotels WHERE Name='$hotel'" | \
        python3 -c "import sys,json; print(json.load(sys.stdin).get('result',[{}])[0].get('c',0))" 2>/dev/null || echo "0")
    if [ "$CNT" -eq "0" ]; then
        echo "Missing hotel: $hotel"
        MISSING_DATA=true
    fi
done

if [ "$MISSING_DATA" = "true" ]; then
    echo "ERROR: Required ground truth data is missing in demodb. Re-running seeder..."
    # Attempt to seed if missing (backup safety)
    if [ -f "/workspace/scripts/seed_demodb.py" ]; then
        python3 /workspace/scripts/seed_demodb.py
    else
        echo "FATAL: Seeder script not found."
        exit 1
    fi
fi

# Ensure Firefox is open to OrientDB Studio
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="