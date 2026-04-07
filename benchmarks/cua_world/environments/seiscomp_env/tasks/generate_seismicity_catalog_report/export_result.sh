#!/bin/bash
echo "=== Exporting generate_seismicity_catalog_report results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
SCRIPT_PATH="/home/ga/Documents/generate_report.py"
REPORT_PATH="/home/ga/Documents/seismicity_report.md"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Extract Ground Truth from DB using Python API
cat > /tmp/extract_gt.py << 'EOF'
import sys, json
sys.path.append('/home/ga/seiscomp/lib/python')
try:
    import seiscomp.datamodel as scdm
    import seiscomp.io as scio

    db = scio.DatabaseInterface.Open("mysql://sysop:sysop@localhost/seiscomp")
    query = scio.DatabaseQuery(db)
    
    events = []
    it = query.getEvents()
    while it and it.get():
        e = scdm.Event.Cast(it.get())
        if e:
            eid = e.publicID()
            mag_val = None
            pmid = e.preferredMagnitudeID()
            if pmid:
                obj = query.getObject(scdm.Magnitude.TypeInfo(), pmid)
                if obj:
                    m = scdm.Magnitude.Cast(obj)
                    if m:
                        mag_val = m.magnitude().value()
            
            lat_val = None
            lon_val = None
            poid = e.preferredOriginID()
            if poid:
                obj = query.getObject(scdm.Origin.TypeInfo(), poid)
                if obj:
                    o = scdm.Origin.Cast(obj)
                    if o:
                        lat_val = o.latitude().value()
                        lon_val = o.longitude().value()

            events.append({
                "id": eid,
                "mag": mag_val,
                "lat": lat_val,
                "lon": lon_val
            })
        it.step()

    with open("/tmp/db_ground_truth.json", "w") as f:
        json.dump(events, f)
except Exception as e:
    with open("/tmp/db_ground_truth.json", "w") as f:
        json.dump({"error": str(e)}, f)
EOF

su - ga -c "export PYTHONPATH=/home/ga/seiscomp/lib/python && python3 /tmp/extract_gt.py"

# Gather file info
SCRIPT_EXISTS="false"
SCRIPT_MTIME=0
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    cp "$SCRIPT_PATH" /tmp/agent_script.py
fi

REPORT_EXISTS="false"
REPORT_MTIME=0
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    cp "$REPORT_PATH" /tmp/agent_report.md
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "script_exists": $SCRIPT_EXISTS,
    "script_mtime": $SCRIPT_MTIME,
    "report_exists": $REPORT_EXISTS,
    "report_mtime": $REPORT_MTIME
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
chmod 666 /tmp/db_ground_truth.json 2>/dev/null || true
chmod 666 /tmp/agent_script.py 2>/dev/null || true
chmod 666 /tmp/agent_report.md 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="