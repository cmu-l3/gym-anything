#!/bin/bash
echo "=== Exporting Review Event Result ==="

source /workspace/scripts/task_utils.sh

# Capture final visual state
take_screenshot /tmp/task_final.png

# Write a robust Python script to cleanly extract DB state to JSON
# This avoids brittle bash string parsing of MySQL output
cat > /tmp/export_db.py << 'EOF'
import subprocess
import json
import os

def run_query(query):
    try:
        # Use \G for list output to easily parse key-value pairs
        out = subprocess.check_output(["mysql", "-u", "sysop", "-psysop", "seiscomp", "-e", query + "\\G"], text=True)
        record = {}
        for line in out.splitlines():
            if ':' in line and not line.startswith('*'):
                k, v = line.split(':', 1)
                record[k.strip()] = v.strip()
        return record
    except Exception:
        return {}

def count_query(query):
    try:
        out = subprocess.check_output(["mysql", "-u", "sysop", "-psysop", "seiscomp", "-N", "-e", query], text=True)
        return int(out.strip())
    except Exception:
        return 0

# 1. Get Event metadata
event = run_query("SELECT * FROM Event LIMIT 1")
pref_orig = event.get('preferredOriginID', '')
pref_mag = event.get('preferredMagnitudeID', '')
event_oid = event.get('_oid', '')

# Failsafe _oid extraction if SELECT * behaves strangely
if not event_oid:
    try:
        event_oid = subprocess.check_output(["mysql", "-u", "sysop", "-psysop", "seiscomp", "-N", "-e", "SELECT _oid FROM Event LIMIT 1"], text=True).strip()
    except Exception:
        pass

# 2. Get Origin and Magnitude corresponding to the event's preference
origin = run_query(f"SELECT * FROM Origin WHERE publicID='{pref_orig}'") if pref_orig else {}
mag = run_query(f"SELECT * FROM Magnitude WHERE publicID='{pref_mag}'") if pref_mag else {}

# 3. Check for specific comment
comments = count_query(f"SELECT COUNT(*) FROM EventComment WHERE _parent_oid='{event_oid}' AND text LIKE '%Depth constrained by regional phases%'") if event_oid else 0

result = {
    "event": event,
    "origin": origin,
    "magnitude": mag,
    "comment_count": comments
}

# Write results
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)

os.chmod("/tmp/task_result.json", 0o666)
EOF

# Execute the extraction script
python3 /tmp/export_db.py

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="