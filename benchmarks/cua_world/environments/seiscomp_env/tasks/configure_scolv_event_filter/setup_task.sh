#!/bin/bash
set -e
echo "=== Setting up task: configure_scolv_event_filter ==="

# 1. Setup environment and record start time
source /workspace/scripts/task_utils.sh 2>/dev/null || true
export SEISCOMP_ROOT=/home/ga/seiscomp
export PATH="$SEISCOMP_ROOT/bin:$PATH"
export LD_LIBRARY_PATH="$SEISCOMP_ROOT/lib:$LD_LIBRARY_PATH"
export PYTHONPATH="$SEISCOMP_ROOT/lib/python:$PYTHONPATH"

date +%s > /tmp/task_start_time.txt

# Wait for desktop
sleep 5

# 2. Ensure services are running
echo "Starting scmaster..."
systemctl start mariadb || true
sleep 2

su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
    LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
    seiscomp start scmaster" || true
sleep 5

# 3. Inject a small "noise" event (M3.5) into the database
# This ensures there is a clear difference between the unfiltered and filtered views
echo "--- Injecting synthetic noise event (M3.5) ---"

cat > /tmp/create_noise_event.py << 'PYEOF'
import sys
import datetime
import seiscomp.datamodel as scdm
import seiscomp.io as scio
import seiscomp.core as sccore

def create_event():
    ep = scdm.EventParameters()
    
    # Create Origin
    o = scdm.Origin.Create()
    o.setCreationInfo(scdm.CreationInfo())
    o.creationInfo().setAgencyID('TEST')
    
    ot = sccore.Time()
    ot.fromString("2024-01-01T08:10:00.000", "%FT%T.%f")
    o.setTime(scdm.TimeQuantity(ot))
    o.setLatitude(scdm.RealQuantity(37.3))
    o.setLongitude(scdm.RealQuantity(136.8))
    o.setDepth(scdm.RealQuantity(10.0))
    ep.add(o)

    # Create Magnitude (M 3.5)
    m = scdm.Magnitude.Create()
    m.setCreationInfo(scdm.CreationInfo())
    m.creationInfo().setAgencyID('TEST')
    m.setMagnitude(scdm.RealQuantity(3.5))
    m.setType("M")
    m.setOriginID(o.publicID())
    o.add(m)

    # Create Event
    e = scdm.Event.Create()
    e.setCreationInfo(scdm.CreationInfo())
    e.creationInfo().setAgencyID('TEST')
    e.setPreferredOriginID(o.publicID())
    e.setPreferredMagnitudeID(m.publicID())
    e.add(scdm.OriginReference(o.publicID()))
    
    ep.add(e)
    
    ar = scio.XMLArchive()
    ar.create("/tmp/noise_event.scml")
    ar.setFormattedOutput(True)
    ar.writeObject(ep)
    ar.close()
    print("Created /tmp/noise_event.scml")

if __name__ == '__main__':
    create_event()
PYEOF

chown ga:ga /tmp/create_noise_event.py
su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
    LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
    PYTHONPATH=$SEISCOMP_ROOT/lib/python:\$PYTHONPATH \
    python3 /tmp/create_noise_event.py"

if [ -f "/tmp/noise_event.scml" ]; then
    echo "Importing noise event to database..."
    su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
        LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
        seiscomp exec scdb -i /tmp/noise_event.scml -d mysql://sysop:sysop@localhost/seiscomp" 2>/dev/null || true
fi

# 4. Clear any previous user config
rm -f /home/ga/.seiscomp/scolv.cfg
mkdir -p /home/ga/.seiscomp
chown -R ga:ga /home/ga/.seiscomp

# 5. Prepare the UI
# Maximize any existing windows (cleanup)
DISPLAY=:1 wmctrl -l | awk '{print $1}' | xargs -I{} DISPLAY=:1 wmctrl -i -r {} -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Launch a terminal for the user
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"
    sleep 3
    DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="