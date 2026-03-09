#!/bin/bash
# setup_task.sh — pre_task hook for audit_fleet_compliance_script

echo "=== Setting up Audit Fleet Compliance Script task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Wait for Aerobridge to be ready
wait_for_aerobridge 60 || echo "WARNING: Aerobridge server may not be ready"

# 2. Record task start time (for anti-gaming file timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded."

# 3. clean up any previous run artifacts
rm -f /home/ga/fleet_compliance_audit.py
rm -f /home/ga/fleet_compliance_report.txt
rm -f /tmp/ground_truth_compliance.json
rm -f /tmp/task_result.json

# 4. Generate Ground Truth data immediately (hidden from agent)
# This ensures we have a baseline of what the database looked like at start
echo "Generating ground truth data..."
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django, json
sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
with open('/opt/aerobridge/.env') as f:
    for line in f:
        line = line.strip()
        if '=' in line and not line.startswith('#'):
            k, _, v = line.partition('=')
            os.environ.setdefault(k, v.strip("'").strip('"'))
django.setup()

try:
    from registry.models import Aircraft
    
    total = 0
    compliant = 0
    non_compliant = 0
    
    aircrafts = Aircraft.objects.all()
    total = aircrafts.count()
    
    for ac in aircrafts:
        # Check criteria: manufacturer, operator, type_certificate must be non-null
        if ac.manufacturer and ac.operator and ac.type_certificate:
            compliant += 1
        else:
            non_compliant += 1
            
    truth = {
        "total": total,
        "compliant": compliant,
        "non_compliant": non_compliant
    }
    
    with open('/tmp/ground_truth_compliance.json', 'w') as f:
        json.dump(truth, f)
    print(f"Ground Truth: Total={total}, Compliant={compliant}, Non={non_compliant}")

except Exception as e:
    print(f"Error generating ground truth: {e}")
PYEOF

# 5. Launch Terminal (since this is a scripting task)
if ! pgrep -f "gnome-terminal" > /dev/null; then
    echo "Launching terminal..."
    su - ga -c "DISPLAY=:1 gnome-terminal --maximize &"
    sleep 2
fi

# 6. Launch Firefox to Admin Panel (for reference/exploration)
launch_firefox "http://localhost:8000/admin/"

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="