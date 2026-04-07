#!/bin/bash
set -e
echo "=== Setting up batch_classify_quarry_blasts task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure SeisComP messaging and database are running
ensure_scmaster_running

# 2. Inject target "Mining" Events (Simulating unreviewed automatic detections)
# We use a python script to generate SCML and import it via scdb
cat > /tmp/inject_mining_events.py << 'EOF'
import sys
import seiscomp.datamodel as scdm
import seiscomp.io as scio

def create_event(lat, lon, depth, mag_val, time_str, suffix):
    ep = scdm.EventParameters()
    
    ci = scdm.CreationInfo()
    ci.setAgencyID("GYM")
    ci.setAuthor("AutoLocator")
    ci.setCreationTime(scdm.Time.GMT())

    ot = scdm.Time()
    ot.fromString(time_str, "%Y-%m-%dT%H:%M:%S.%f")
    
    o = scdm.Origin.Create()
    o.setCreationInfo(ci)
    o.setTime(scdm.TimeQuantity(ot))
    o.setLatitude(scdm.RealQuantity(lat))
    o.setLongitude(scdm.RealQuantity(lon))
    o.setDepth(scdm.RealQuantity(depth))
    ep.add(o)

    m = scdm.Magnitude.Create()
    m.setCreationInfo(ci)
    m.setMagnitude(scdm.RealQuantity(mag_val))
    m.setType("ML")
    m.setOriginID(o.publicID())
    o.add(m)

    e = scdm.Event.Create()
    e.setCreationInfo(ci)
    e.setPreferredOriginID(o.publicID())
    e.setPreferredMagnitudeID(m.publicID())
    
    # Intentionally misclassified initially by the "auto system"
    e.setType("earthquake") 
    e.setTypeCertainty("suspected")
    
    oref = scdm.OriginReference()
    oref.setOriginID(o.publicID())
    e.add(oref)
    
    ep.add(e)
    return ep

# Mining Cluster Coords (Target: Lat -1.7 to -1.5, Lon 116.0 to 116.2)
events = [
    (-1.60, 116.10, 0.0, 1.8, "2024-01-02T08:00:00.0000"),
    (-1.65, 116.05, 0.0, 2.1, "2024-01-03T09:15:00.0000"),
    (-1.55, 116.15, 0.0, 1.5, "2024-01-04T07:30:00.0000"),
    (-1.62, 116.08, 0.0, 1.9, "2024-01-05T12:00:00.0000"),
    (-1.58, 116.12, 0.0, 2.3, "2024-01-05T14:45:00.0000")
]

ep_all = scdm.EventParameters()
for i, (lat, lon, dep, mag, t) in enumerate(events):
    ep_chunk = create_event(lat, lon, dep, mag, t, str(i))
    for j in range(ep_chunk.originCount()):
        ep_all.add(ep_chunk.origin(j))
    for j in range(ep_chunk.eventCount()):
        ep_all.add(ep_chunk.event(j))

ar = scio.XMLArchive()
ar.create("/tmp/mining_events.scml")
ar.setFormattedOutput(True)
ar.writeObject(ep_all)
ar.close()
EOF

# Run generation
su - ga -c "PYTHONPATH=$SEISCOMP_ROOT/lib/python python3 /tmp/inject_mining_events.py"

# Import to DB
echo "Importing injected events..."
su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH seiscomp exec scdb --plugins dbmysql -i /tmp/mining_events.scml -d mysql://sysop:sysop@localhost/seiscomp"

# Make sure the Noto event is loaded (as a distractor/control event)
NOTO_COUNT=$(mysql -u sysop -psysop seiscomp -N -e "SELECT COUNT(*) FROM Event e JOIN Origin o ON e.preferredOriginID = o.publicID WHERE o.latitude > 30" 2>/dev/null || echo "0")
if [ "$NOTO_COUNT" -eq 0 ]; then
    echo "Importing Noto earthquake..."
    su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH python3 /workspace/scripts/convert_quakeml.py $SEISCOMP_ROOT/var/lib/events/noto_earthquake.xml $SEISCOMP_ROOT/var/lib/events/noto_earthquake.scml" 2>/dev/null || true
    su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH seiscomp exec scdb --plugins dbmysql -i $SEISCOMP_ROOT/var/lib/events/noto_earthquake.scml -d mysql://sysop:sysop@localhost/seiscomp" 2>/dev/null || true
fi

# 3. Clean UI State
dismiss_dialogs 3

# Start a fresh terminal for the agent
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"
    sleep 3
fi

focus_and_maximize "Terminal"

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="