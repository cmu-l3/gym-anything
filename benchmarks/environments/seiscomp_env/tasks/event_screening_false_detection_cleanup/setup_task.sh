#!/bin/bash
echo "=== Setting up event_screening_false_detection_cleanup task ==="

source /workspace/scripts/task_utils.sh

TASK="event_screening_false_detection_cleanup"

# ─── 1. Ensure services are running ──────────────────────────────────────────

echo "--- Ensuring SeisComP services are running ---"
ensure_scmaster_running

# ─── 2. Ensure real event is in database ─────────────────────────────────────

echo "--- Verifying real event data ---"

EVENT_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Event" 2>/dev/null || echo "0")
echo "Events in database: $EVENT_COUNT"

if [ "$EVENT_COUNT" = "0" ] || [ -z "$EVENT_COUNT" ]; then
    echo "No events found, reimporting real event..."
    SCML_FILE="$SEISCOMP_ROOT/var/lib/events/noto_earthquake.scml"
    QML_FILE="$SEISCOMP_ROOT/var/lib/events/noto_earthquake.xml"
    if [ ! -s "$SCML_FILE" ] && [ -s "$QML_FILE" ]; then
        su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
            LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
            PYTHONPATH=$SEISCOMP_ROOT/lib/python:\$PYTHONPATH \
            python3 /workspace/scripts/convert_quakeml.py $QML_FILE $SCML_FILE" 2>/dev/null || true
    fi
    if [ -s "$SCML_FILE" ]; then
        su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
            LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
            seiscomp exec scdb --plugins dbmysql -i $SCML_FILE \
            -d mysql://sysop:sysop@localhost/seiscomp" 2>/dev/null || true
        sleep 2
    fi
fi

# ─── 3. Remove any previously injected false events ──────────────────────────

echo "--- Cleaning previous false events ---"

# Delete false events from previous runs (by matching unrealistic locations)
seiscomp_db_query "DELETE ar FROM Arrival ar
    JOIN Origin o ON ar._parent_oid = o._oid
    WHERE (ABS(o.latitude_value) > 60 OR o.longitude_value > 170
    OR o.longitude_value < -170 OR o.latitude_value < -50)" 2>/dev/null || true

seiscomp_db_query "DELETE FROM OriginReference WHERE originID IN (
    SELECT po.publicID FROM PublicObject po
    JOIN Origin o ON o._oid = po._oid
    WHERE (ABS(o.latitude_value) > 60 OR o.longitude_value > 170
    OR o.longitude_value < -170 OR o.latitude_value < -50)
)" 2>/dev/null || true

# Delete false events by joining through preferredOriginID
for FALSE_LAT_LON in "5.0 170.5" "-45.0 -175.0" "65.0 -30.5"; do
    LAT=$(echo $FALSE_LAT_LON | awk '{print $1}')
    LON=$(echo $FALSE_LAT_LON | awk '{print $2}')
    seiscomp_db_query "DELETE e FROM Event e
        JOIN PublicObject po ON po.publicID = e.preferredOriginID
        JOIN Origin o ON o._oid = po._oid
        WHERE ABS(o.latitude_value - $LAT) < 1.0
        AND ABS(o.longitude_value - ($LON)) < 1.0" 2>/dev/null || true
    seiscomp_db_query "DELETE FROM Origin
        WHERE ABS(latitude_value - $LAT) < 1.0
        AND ABS(longitude_value - ($LON)) < 1.0" 2>/dev/null || true
done

echo "Previous false events cleaned"

# ─── 4. Inject three false detection events ──────────────────────────────────

echo "--- Injecting false detection events ---"

# Use Python with SeisComP library to create false events
su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
    LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
    PYTHONPATH=$SEISCOMP_ROOT/lib/python:\$PYTHONPATH \
    python3 << 'PYEOF'
import sys
sys.path.insert(0, '/home/ga/seiscomp/lib/python')

try:
    import seiscomp.datamodel as dm
    import seiscomp.io as sio

    ep = dm.EventParameters()

    false_events = [
        {
            \"id\": \"false_det_001\",
            \"lat\": 5.0, \"lon\": 170.5, \"depth\": 33000.0,
            \"time\": \"2024-01-01T06:45:12.000Z\",
            \"mag\": 1.3, \"mag_type\": \"ML\",
            \"desc\": \"False detection - mid-Pacific\"
        },
        {
            \"id\": \"false_det_002\",
            \"lat\": -45.0, \"lon\": -175.0, \"depth\": 10000.0,
            \"time\": \"2024-01-01T07:02:33.000Z\",
            \"mag\": 0.8, \"mag_type\": \"ML\",
            \"desc\": \"False detection - South Pacific\"
        },
        {
            \"id\": \"false_det_003\",
            \"lat\": 65.0, \"lon\": -30.5, \"depth\": 5000.0,
            \"time\": \"2024-01-01T07:15:45.000Z\",
            \"mag\": 1.6, \"mag_type\": \"ML\",
            \"desc\": \"False detection - North Atlantic\"
        },
    ]

    for fe in false_events:
        ot = dm.Core.Time()
        ot.fromString(fe[\"time\"], \"%Y-%m-%dT%H:%M:%S.%fZ\")

        origin = dm.Origin.Create(\"Origin/\" + fe[\"id\"])
        origin.setTime(dm.TimeQuantity(ot))
        origin.setLatitude(dm.RealQuantity(fe[\"lat\"]))
        origin.setLongitude(dm.RealQuantity(fe[\"lon\"]))
        origin.setDepth(dm.RealQuantity(fe[\"depth\"]))
        origin.setEvaluationMode(dm.AUTOMATIC)

        ci = dm.CreationInfo()
        ci.setAgencyID(\"GYM\")
        ct = dm.Core.Time()
        ct.fromString(\"2024-01-01T08:00:00.000Z\", \"%Y-%m-%dT%H:%M:%S.%fZ\")
        ci.setCreationTime(ct)
        origin.setCreationInfo(ci)

        # Add 2 fake arrivals (below the threshold of 4)
        for i in range(2):
            arr = dm.Arrival()
            arr.setPhase(dm.Phase(\"P\"))
            arr.setDistance(float(i + 1) * 10.0)
            arr.setAzimuth(float(i) * 90.0)
            arr.setTimeResidual(float(i) * 0.5)
            origin.add(arr)

        ep.add(origin)

        mag = dm.Magnitude.Create(\"Magnitude/\" + fe[\"id\"])
        mag.setMagnitude(dm.RealQuantity(fe[\"mag\"]))
        mag.setType(fe[\"mag_type\"])
        mag.setStationCount(2)
        mag.setOriginID(\"Origin/\" + fe[\"id\"])
        mag.setEvaluationMode(dm.AUTOMATIC)
        mag.setCreationInfo(ci)
        origin.add(mag)

        evt = dm.Event.Create(\"Event/\" + fe[\"id\"])
        evt.setPreferredOriginID(\"Origin/\" + fe[\"id\"])
        evt.setPreferredMagnitudeID(\"Magnitude/\" + fe[\"id\"])
        evt.setType(dm.EARTHQUAKE)
        evt.setCreationInfo(ci)

        desc = dm.EventDescription()
        desc.setText(fe[\"desc\"])
        desc.setType(dm.EARTHQUAKE_NAME)
        evt.add(desc)

        oref = dm.OriginReference()
        oref.setOriginID(\"Origin/\" + fe[\"id\"])
        evt.add(oref)

        ep.add(evt)

    ar = sio.XMLArchive()
    ar.create(\"/tmp/false_events.scml\")
    ar.setFormattedOutput(True)
    ar.writeObject(ep)
    ar.close()

    print(\"Created 3 false event SCML at /tmp/false_events.scml\")

except Exception as e:
    print(f\"Python error: {e}\", file=sys.stderr)
    # Fallback: create via direct SQL
    import subprocess
    for fe_data in [
        (\"false_det_001\", 5.0, 170.5, 33000.0, \"2024-01-01 06:45:12\", 1.3),
        (\"false_det_002\", -45.0, -175.0, 10000.0, \"2024-01-01 07:02:33\", 0.8),
        (\"false_det_003\", 65.0, -30.5, 5000.0, \"2024-01-01 07:15:45\", 1.6),
    ]:
        fid, flat, flon, fdep, ftime, fmag = fe_data
        # SQL fallback is in the shell below
    print(\"Python SeisComP API failed, will use SQL fallback\")
    sys.exit(1)
PYEOF
" 2>/dev/null

# Import the false events SCML
if [ -s "/tmp/false_events.scml" ]; then
    su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
        LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
        seiscomp exec scdb --plugins dbmysql -i /tmp/false_events.scml \
        -d mysql://sysop:sysop@localhost/seiscomp" 2>/dev/null || true
    echo "False events imported via SCML"
else
    # SQL fallback: inject false events directly into database
    echo "Using SQL fallback to inject false events..."

    MAX_OID=$(seiscomp_db_query "SELECT MAX(_oid) FROM Object" 2>/dev/null || echo "1000")
    NEXT_OID=$((MAX_OID + 1))

    for FE_DATA in \
        "false_det_001|5.0|170.5|33000|2024-01-01 06:45:12|1.3|False detection - mid-Pacific" \
        "false_det_002|-45.0|-175.0|10000|2024-01-01 07:02:33|0.8|False detection - South Pacific" \
        "false_det_003|65.0|-30.5|5000|2024-01-01 07:15:45|1.6|False detection - North Atlantic"; do

        IFS='|' read -r FID FLAT FLON FDEP FTIME FMAG FDESC <<< "$FE_DATA"

        ORIGIN_OID=$NEXT_OID
        NEXT_OID=$((NEXT_OID + 1))
        MAG_OID=$NEXT_OID
        NEXT_OID=$((NEXT_OID + 1))
        EVENT_OID=$NEXT_OID
        NEXT_OID=$((NEXT_OID + 1))
        OREF_OID=$NEXT_OID
        NEXT_OID=$((NEXT_OID + 1))

        seiscomp_db_query "INSERT INTO Object (_oid, _timestamp) VALUES
            ($ORIGIN_OID, NOW()), ($MAG_OID, NOW()), ($EVENT_OID, NOW()), ($OREF_OID, NOW())" 2>/dev/null || true

        seiscomp_db_query "INSERT INTO PublicObject (_oid, publicID) VALUES
            ($ORIGIN_OID, 'Origin/$FID'),
            ($MAG_OID, 'Magnitude/$FID'),
            ($EVENT_OID, 'Event/$FID')" 2>/dev/null || true

        seiscomp_db_query "INSERT INTO Origin (_oid, time_value, latitude_value, longitude_value, depth_value, evaluationMode)
            VALUES ($ORIGIN_OID, '$FTIME', $FLAT, $FLON, $FDEP, 'automatic')" 2>/dev/null || true

        seiscomp_db_query "INSERT INTO Magnitude (_oid, _parent_oid, magnitude_value, type, stationCount, originID)
            VALUES ($MAG_OID, $ORIGIN_OID, $FMAG, 'ML', 2, 'Origin/$FID')" 2>/dev/null || true

        seiscomp_db_query "INSERT INTO Event (_oid, preferredOriginID, preferredMagnitudeID, type)
            VALUES ($EVENT_OID, 'Origin/$FID', 'Magnitude/$FID', 'earthquake')" 2>/dev/null || true

        seiscomp_db_query "INSERT INTO OriginReference (_oid, _parent_oid, originID)
            VALUES ($OREF_OID, $EVENT_OID, 'Origin/$FID')" 2>/dev/null || true

        echo "  Injected false event: $FID (M$FMAG at $FLAT,$FLON)"
    done
fi

# ─── 5. Verify injection ────────────────────────────────────────────────────

TOTAL_EVENTS=$(seiscomp_db_query "SELECT COUNT(*) FROM Event" 2>/dev/null || echo "0")
echo "Total events after injection: $TOTAL_EVENTS"

# ─── 6. Record baseline ─────────────────────────────────────────────────────

echo "--- Recording baseline ---"

echo "$TOTAL_EVENTS" > /tmp/${TASK}_initial_event_count
echo "4" > /tmp/${TASK}_expected_total  # 1 real + 3 false
echo "3" > /tmp/${TASK}_false_event_count

date +%s > /tmp/${TASK}_start_ts

rm -f /home/ga/Desktop/verified_events.txt

echo "Baseline: $TOTAL_EVENTS events (1 real + 3 false), no verified bulletin"

# ─── 7. Launch scolv ────────────────────────────────────────────────────────

echo "--- Launching scolv ---"

cat > "$SEISCOMP_ROOT/etc/scolv.cfg" << 'CFGEOF'
loadEventDB = 1000
recordstream = sds://var/lib/archive
CFGEOF
chown ga:ga "$SEISCOMP_ROOT/etc/scolv.cfg"

kill_seiscomp_gui scolv

launch_seiscomp_gui scolv "--plugins dbmysql -d mysql://sysop:sysop@localhost/seiscomp --load-event-db 1000"

wait_for_window "scolv" 60 || wait_for_window "Origin" 30 || wait_for_window "SeisComP" 30

sleep 4
dismiss_dialogs 2
focus_and_maximize "scolv" || focus_and_maximize "Origin" || focus_and_maximize "SeisComP"
sleep 2

# Open terminal for scbulletin
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xfce4-terminal --title='SeisComP Terminal'" > /dev/null 2>&1 &
sleep 1
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority gnome-terminal -- bash -i" > /dev/null 2>&1 &
fi
sleep 2

# ─── 8. Take initial screenshot ──────────────────────────────────────────────

echo "--- Taking initial screenshot ---"
take_screenshot /tmp/${TASK}_start_screenshot.png
mkdir -p /workspace/evidence
cp /tmp/${TASK}_start_screenshot.png /workspace/evidence/ 2>/dev/null || true

echo "=== Task setup complete ==="
echo "scolv is open with 4 events (1 real + 3 false detections)."
echo "Agent must: identify false detections by location/magnitude/picks,"
echo "delete them, export bulletin of remaining real event."
