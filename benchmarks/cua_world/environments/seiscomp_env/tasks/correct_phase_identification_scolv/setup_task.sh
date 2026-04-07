#!/bin/bash
echo "=== Setting up correct_phase_identification_scolv task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# ─── 1. Ensure services are running ──────────────────────────────────────────
echo "--- Ensuring SeisComP services are running ---"
ensure_scmaster_running

# ─── 2. Inject target Pick and Arrival for TOLI ──────────────────────────────
echo "--- Injecting target 'P' arrival for GE.TOLI ---"

# Get current preferred origin of the Noto event
EVENT_ID=$(mysql -u sysop -psysop seiscomp -N -e "SELECT publicID FROM Event LIMIT 1" 2>/dev/null)
if [ -z "$EVENT_ID" ]; then
    echo "ERROR: No event found in database."
    exit 1
fi
ORIGIN_ID=$(mysql -u sysop -psysop seiscomp -N -e "SELECT preferredOriginID FROM Event WHERE publicID='$EVENT_ID'" 2>/dev/null)

echo "Event: $EVENT_ID | Origin: $ORIGIN_ID"

# Python script to generate SCML injection
cat > /tmp/inject_arrival.py << 'EOF'
import sys
import seiscomp.datamodel as scdm
import seiscomp.io as scio
import seiscomp.core as sccore

origin_id = sys.argv[1]

ep = scdm.EventParameters()

# Create Pick
pick = scdm.Pick.Create()
pick.setCreationInfo(scdm.CreationInfo())
pick.creationInfo().setAgencyID("USGS")
t = sccore.Time()
t.fromString("2024-01-01T07:14:30.0000Z", "%FT%T.%f%Z")
pick.setTime(scdm.TimeQuantity(t))
pick.setWaveformID(scdm.WaveformStreamID("GE", "TOLI", "", "BHZ", ""))
pick.setPhaseHint(scdm.Phase("P"))
pick.setEvaluationMode(scdm.AUTOMATIC)
ep.add(pick)

# Reference existing origin and add arrival
o = scdm.Origin.Create(origin_id)
arr = scdm.Arrival()
arr.setCreationInfo(scdm.CreationInfo())
arr.creationInfo().setAgencyID("USGS")
arr.setPickID(pick.publicID())
arr.setPhase(scdm.Phase("P"))
arr.setDistance(20.0)
arr.setAzimuth(230.0)
arr.setTimeResidual(0.0)
arr.setWeight(1.0)
o.add(arr)
ep.add(o)

ar = scio.XMLArchive()
ar.create("/tmp/injection.scml")
ar.setFormattedOutput(True)
ar.writeObject(ep)
ar.close()
EOF

# Run injection generation
su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT \
    PYTHONPATH=$SEISCOMP_ROOT/lib/python \
    LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib \
    python3 /tmp/inject_arrival.py '$ORIGIN_ID'"

# Import injection to DB
su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
    LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
    seiscomp exec scdb --plugins dbmysql -i /tmp/injection.scml \
    -d mysql://sysop:sysop@localhost/seiscomp" 2>/dev/null || true

sleep 2

# Verify injection
TOLI_EXISTS=$(mysql -u sysop -psysop seiscomp -N -e "SELECT COUNT(*) FROM Arrival a JOIN Pick p ON a.pickID = p.publicID WHERE a.originID = '$ORIGIN_ID' AND p.waveformID_stationCode = 'TOLI'" 2>/dev/null)
echo "TOLI arrivals in origin: $TOLI_EXISTS"

# ─── 3. Launch scolv ─────────────────────────────────────────────────────────
echo "--- Launching scolv ---"
kill_seiscomp_gui scolv
launch_seiscomp_gui scolv "--plugins dbmysql -d mysql://sysop:sysop@localhost/seiscomp --load-event-db 1000"

wait_for_window "scolv" 60 || wait_for_window "Origin" 30 || wait_for_window "SeisComP" 30
sleep 3
dismiss_dialogs 2
focus_and_maximize "scolv" || focus_and_maximize "Origin" || focus_and_maximize "SeisComP"
sleep 2

# ─── 4. Take initial screenshot ──────────────────────────────────────────────
echo "--- Taking initial screenshot ---"
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="