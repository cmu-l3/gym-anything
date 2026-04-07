#!/bin/bash
echo "=== Setting up generate_seismicity_catalog_report task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 1. Ensure Services Running
echo "--- Ensuring SeisComP services are running ---"
ensure_scmaster_running

# 2. Inject Simulated Aftershocks to enrich dataset
echo "--- Injecting simulated aftershock sequence ---"

cat > /tmp/gen_aftershocks.py << 'EOF'
import sys
import random
from datetime import datetime, timedelta
import seiscomp.datamodel as scdm
import seiscomp.io as scio

def generate_events():
    ep = scdm.EventParameters()
    base_time = datetime(2024, 1, 1, 7, 10, 0)
    base_lat = 37.5
    base_lon = 137.2

    # Generate 5 additional events
    for i in range(5):
        dt = timedelta(hours=random.randint(1, 48) + i*2)
        evt_time = base_time + dt
        lat = base_lat + random.uniform(-0.2, 0.2)
        lon = base_lon + random.uniform(-0.2, 0.2)
        depth = random.uniform(8.0, 12.0)
        mag = round(random.uniform(4.0, 5.5), 1)
        
        ci = scdm.CreationInfo()
        ci.setAgencyID("SIM")
        ci.setCreationTime(scdm.Time.GMT())
        
        o = scdm.Origin.Create()
        o.setCreationInfo(ci)
        t = scdm.Time()
        t.fromString(evt_time.strftime("%Y-%m-%d %H:%M:%S.0000"), "%Y-%m-%d %H:%M:%S.%f")
        o.setTime(scdm.TimeQuantity(t))
        o.setLatitude(scdm.RealQuantity(lat))
        o.setLongitude(scdm.RealQuantity(lon))
        o.setDepth(scdm.RealQuantity(depth))
        ep.add(o)
        
        m = scdm.Magnitude.Create()
        m.setCreationInfo(ci)
        m.setMagnitude(scdm.RealQuantity(mag))
        m.setType("M")
        m.setOriginID(o.publicID())
        o.add(m)
        
        e = scdm.Event.Create()
        e.setCreationInfo(ci)
        e.setPreferredOriginID(o.publicID())
        e.setPreferredMagnitudeID(m.publicID())
        
        oref = scdm.OriginReference()
        oref.setOriginID(o.publicID())
        e.add(oref)
        
        ep.add(e)

    ar = scio.XMLArchive()
    ar.create("/tmp/aftershocks.scml")
    ar.setFormattedOutput(True)
    ar.writeObject(ep)
    ar.close()

if __name__ == '__main__':
    generate_events()
EOF

su - ga -c "export PYTHONPATH=$SEISCOMP_ROOT/lib/python && python3 /tmp/gen_aftershocks.py"

if [ -f "/tmp/aftershocks.scml" ]; then
    echo "Importing aftershocks to DB..."
    su - ga -c "$SEISCOMP_ROOT/bin/seiscomp exec scdb --plugins dbmysql -i /tmp/aftershocks.scml -d mysql://sysop:sysop@localhost/seiscomp" 2>/dev/null || true
fi

# 3. Final Prep
rm -f /home/ga/Documents/seismicity_report.md /home/ga/Documents/generate_report.py

# Open terminal for agent to start working
if ! pgrep -f "gnome-terminal" > /dev/null; then
    DISPLAY=:1 gnome-terminal --geometry=100x30+100+100 &
    sleep 2
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="