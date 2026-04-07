#!/bin/bash
set -e
echo "=== Setting up Import Focal Mechanism task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure services are running
systemctl start mariadb 2>/dev/null || true
ensure_scmaster_running

# Verify event data is in the database (import if missing)
EVENT_COUNT=$(mysql -u sysop -psysop seiscomp -N -B -e "SELECT COUNT(*) FROM Event" 2>/dev/null || echo "0")
if [ "$EVENT_COUNT" = "0" ] || [ -z "$EVENT_COUNT" ]; then
    echo "No events found. Re-importing base data..."
    SCML_FILE="$SEISCOMP_ROOT/var/lib/events/noto_earthquake.scml"
    if [ -s "$SCML_FILE" ]; then
        su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
            LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
            seiscomp exec scdb --plugins dbmysql -i $SCML_FILE \
            -d mysql://sysop:sysop@localhost/seiscomp" 2>/dev/null || true
    fi
fi

# Clean state: Remove any existing GCMT focal mechanisms to prevent false positives
echo "Cleaning up any pre-existing GCMT mechanisms..."
mysql -u sysop -psysop seiscomp -e "DELETE FROM MomentTensor WHERE _parent_oid IN (SELECT _oid FROM FocalMechanism WHERE creationInfo_agencyID='GCMT');" 2>/dev/null || true
mysql -u sysop -psysop seiscomp -e "DELETE FROM FocalMechanism WHERE creationInfo_agencyID='GCMT';" 2>/dev/null || true

# Pre-delete the expected output file if it exists
rm -f /home/ga/noto_mechanism.scml

# Open a terminal for the user
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --maximize &"
    sleep 2
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="