#!/bin/bash
# setup_task.sh - Pre-task setup for import_legacy_fleet

echo "=== Setting up Import Legacy Fleet task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Wait for Aerobridge to be ready
wait_for_aerobridge 60 || echo "WARNING: Aerobridge server may not be ready"

# 2. Prepare the CSV file
echo "Creating fleet CSV file..."
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/rural_drone_services_fleet.csv << 'EOF'
Registration,Manufacturer,Model,Mass_kg,Status
N-RDS01,DJI,Matrice 300 RTK,9.0,active
N-RDS02,DJI,Mavic 2 Enterprise,0.9,active
N-RDS03,Parrot,Anafi USA,0.5,active
N-RDS04,Skydio,X2,1.3,maintenance
EOF
chown ga:ga /home/ga/Documents/rural_drone_services_fleet.csv
chmod 644 /home/ga/Documents/rural_drone_services_fleet.csv

# 3. Clean up previous state (Delete 'Rural Drone Services' and its aircraft)
echo "Cleaning up previous task artifacts..."
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django
sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

from registry.models import Aircraft, Company

target_op_name = "Rural Drone Services"
try:
    ops = Company.objects.filter(name=target_op_name)
    count = ops.count()
    if count > 0:
        # Delete linked aircraft first (though CASCADE might handle it, explicit is safer)
        for op in ops:
            Aircraft.objects.filter(operator=op).delete()
        ops.delete()
        print(f"Cleaned up {count} existing '{target_op_name}' records and their aircraft.")
    else:
        print(f"No existing '{target_op_name}' records found.")
except Exception as e:
    print(f"Cleanup error: {e}")
PYEOF

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

# 5. Launch Firefox to Admin Panel
echo "Launching Firefox..."
launch_firefox "http://localhost:8000/admin/"

# 6. Take initial screenshot
echo "Capturing initial state..."
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="