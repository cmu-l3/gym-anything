#!/bin/bash
echo "=== Setting up consolidate_duplicate_events_scolv task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ─── 1. Ensure services are running ──────────────────────────────────────────
echo "--- Ensuring SeisComP services are running ---"
ensure_scmaster_running

# ─── 2. Ensure base event is present ─────────────────────────────────────────
echo "--- Verifying base event data ---"
EVENT_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Event" 2>/dev/null || echo "0")
if [ "$EVENT_COUNT" = "0" ] || [ -z "$EVENT_COUNT" ]; then
    echo "No events found, attempting to reimport base Noto event..."
    SCML_FILE="$SEISCOMP_ROOT/var/lib/events/noto_earthquake.scml"
    if [ -s "$SCML_FILE" ]; then
        su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
            LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
            seiscomp exec scdb --plugins dbmysql -i $SCML_FILE \
            -d mysql://sysop:sysop@localhost/seiscomp" 2>/dev/null || true
        sleep 2
    fi
fi

# ─── 3. Create duplicate event artifact ──────────────────────────────────────
echo "--- Creating duplicate event artifact ---"
cat > /tmp/create_duplicate.py << 'EOF'
import sys
import seiscomp.datamodel as scdm
import seiscomp.io as scio
import seiscomp.core as sccore

ep = scdm.EventParameters()

# Create duplicate origin shifted by a few seconds and degrees
o = scdm.Origin.Create()
t = sccore.Time()
t.fromString("2024-01-01T07:10:15.0000Z", "%FT%T.%f%Z")
o.setTime(scdm.TimeQuantity(t))
o.setLatitude(scdm.RealQuantity(37.28))
o.setLongitude(scdm.RealQuantity(137.04))
o.setDepth(scdm.RealQuantity(10.0))
o.setEvaluationMode(scdm.MANUAL)

ci = scdm.CreationInfo()
ci.setAgencyID("GYM")
o.setCreationInfo(ci)
ep.add(o)

# Create duplicate event
e = scdm.Event.Create()
e.setPreferredOriginID(o.publicID())
e.setType(scdm.EARTHQUAKE)
e.setCreationInfo(ci)

# Link origin to event
oref = scdm.OriginReference()
oref.setOriginID(o.publicID())
e.add(oref)
ep.add(e)

# Save to SCML
ar = scio.XMLArchive()
ar.create("/tmp/duplicate_event.scml")
ar.setFormattedOutput(True)
ar.writeObject(ep)
ar.close()
EOF

# Execute python script to generate SCML
su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
    LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
    PYTHONPATH=$SEISCOMP_ROOT/lib/python:\$PYTHONPATH \
    python3 /tmp/create_duplicate.py"

# Import the duplicate event into the database
if [ -f "/tmp/duplicate_event.scml" ]; then
    su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
        LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
        seiscomp exec scdb --plugins dbmysql -i /tmp/duplicate_event.scml \
        -d mysql://sysop:sysop@localhost/seiscomp" 2>/dev/null || true
    echo "Duplicate event inserted into database."
fi

# ─── 4. Record initial origins for verification ──────────────────────────────
echo "--- Recording initial origins ---"
su - ga -c "python3 -c \"
import MySQLdb, json
try:
    db = MySQLdb.connect(host='localhost', user='sysop', passwd='sysop', db='seiscomp')
    cur = db.cursor()
    cur.execute('SELECT publicID FROM Origin WHERE time_value LIKE \\'2024-01-01%\\'')
    origins = [r[0] for r in cur.fetchall()]
    with open('/tmp/initial_origins.json', 'w') as f:
        json.dump(origins, f)
except Exception as e:
    print('Failed to record origins:', e)
\""

# ─── 5. Configure scolv and launch ───────────────────────────────────────────
echo "--- Preparing scolv ---"
# Ensure scolv loads events from far enough back (Noto is Jan 2024)
sed -i 's/loadEventDB = .*/loadEventDB = 3000/' $SEISCOMP_ROOT/etc/scolv.cfg 2>/dev/null || echo "loadEventDB = 3000" >> $SEISCOMP_ROOT/etc/scolv.cfg

kill_seiscomp_gui scolv

echo "--- Launching scolv ---"
launch_seiscomp_gui scolv "--plugins dbmysql -d mysql://sysop:sysop@localhost/seiscomp"

# Wait for scolv window to appear
wait_for_window "scolv" 45 || wait_for_window "Origin" 30

sleep 3
dismiss_dialogs 2
focus_and_maximize "scolv" || focus_and_maximize "Origin"
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="