#!/bin/bash
# export_result.sh — post_task hook for add_firmware

echo "=== Exporting add_firmware result ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get verification data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "unknown")
INITIAL_COUNT=$(cat /tmp/initial_firmware_count.txt 2>/dev/null || echo "0")

# 3. Query Database and export to JSON
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << PYEOF
import os, sys, django, json
from datetime import datetime

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
with open('/opt/aerobridge/.env') as f:
    for line in f:
        line = line.strip()
        if '=' in line and not line.startswith('#'):
            k, _, v = line.partition('=')
            os.environ.setdefault(k, v.strip("'").strip('"'))
django.setup()

task_start_str = '${TASK_START}'
initial_count = int('${INITIAL_COUNT}' or '0')

result = {
    "task_start_time": task_start_str,
    "initial_count": initial_count,
    "current_count": 0,
    "firmware": None,
    "error": None
}

try:
    from registry.models import Firmware

    # Get current count
    result["current_count"] = Firmware.objects.count()

    # Look for the specific firmware created
    fw = Firmware.objects.filter(version='4.3.7').first()

    if fw:
        # Extract fields for verification
        manufacturer_name = fw.manufacturer.full_name if fw.manufacturer else None
        
        result["firmware"] = {
            "id": fw.pk,
            "version": fw.version,
            "binary_file_url": getattr(fw, 'binary_file_url', ''),
            "binary_file_hash": getattr(fw, 'binary_file_hash', ''),
            "friendly_name": getattr(fw, 'friendly_name', ''),
            "is_active": getattr(fw, 'is_active', False),
            "manufacturer_name": manufacturer_name,
            "created_at": str(fw.created_at) if fw.created_at else None
        }
        print(f"Found firmware: {fw.version} (ID: {fw.pk})")
    else:
        print("Firmware 4.3.7 not found")

except Exception as e:
    result["error"] = str(e)
    print(f"Export error: {e}")

# Write to temp file first to handle permissions
with open('/tmp/task_result_temp.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

# Move to final location (to avoid permission issues between root/ga users)
mv /tmp/task_result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="