#!/bin/bash
# export_result.sh — post_task hook for consolidate_manufacturers

echo "=== Exporting consolidate_manufacturers result ==="

DISPLAY=:1 scrot /tmp/consolidate_manufacturers_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "unknown")
COUNT_INITIAL=$(cat /tmp/aircraft_count_initial 2>/dev/null || echo "0")

cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << PYEOF
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

result = {
    "task": "consolidate_manufacturers",
    "timestamp": "${TASK_START}",
    "initial_aircraft_count": int("${COUNT_INITIAL}" or 0),
    "final_aircraft_count": 0,
    "duplicates_remaining": 0,
    "canonical_exists": False,
    "test_aircraft_status": {},
    "error": None
}

try:
    from registry.models import Company, Aircraft

    # 1. Check Data Loss (Total Count)
    result["final_aircraft_count"] = Aircraft.objects.count()

    # 2. Check Duplicates
    dups = Company.objects.filter(full_name__in=["Yuneec", "Yuneec Electric"])
    result["duplicates_remaining"] = dups.count()
    result["remaining_names"] = list(dups.values_list('full_name', flat=True))

    # 3. Check Canonical
    canonical = Company.objects.filter(full_name="Yuneec International").first()
    result["canonical_exists"] = (canonical is not None)
    canonical_id = canonical.id if canonical else -1

    # 4. Check Test Aircraft Links
    # We read the IDs saved during setup to ensure we check the specific instances
    try:
        with open("/tmp/setup_ids.txt", "r") as f:
            lines = f.readlines()
            # First line is aircraft IDs: id_a, id_b, id_c
            ac_ids = [int(x) for x in lines[0].strip().split(',')]
            
            # Check Unit A (originally Yuneec)
            try:
                ac_a = Aircraft.objects.get(pk=ac_ids[0])
                result["test_aircraft_status"]["unit_a"] = {
                    "exists": True,
                    "manufacturer_name": ac_a.manufacturer.full_name if ac_a.manufacturer else "None",
                    "manufacturer_id": ac_a.manufacturer.id if ac_a.manufacturer else -1,
                    "is_canonical": (ac_a.manufacturer.id == canonical_id) if ac_a.manufacturer and canonical else False
                }
            except Aircraft.DoesNotExist:
                result["test_aircraft_status"]["unit_a"] = {"exists": False}

            # Check Unit B (originally Yuneec Electric)
            try:
                ac_b = Aircraft.objects.get(pk=ac_ids[1])
                result["test_aircraft_status"]["unit_b"] = {
                    "exists": True,
                    "manufacturer_name": ac_b.manufacturer.full_name if ac_b.manufacturer else "None",
                    "manufacturer_id": ac_b.manufacturer.id if ac_b.manufacturer else -1,
                    "is_canonical": (ac_b.manufacturer.id == canonical_id) if ac_b.manufacturer and canonical else False
                }
            except Aircraft.DoesNotExist:
                result["test_aircraft_status"]["unit_b"] = {"exists": False}
    except FileNotFoundError:
        result["error"] = "Setup IDs file not found"

except Exception as e:
    result["error"] = str(e)
    print(f"Export error: {e}")

result_path = '/tmp/task_result.json'
with open(result_path, 'w') as f:
    json.dump(result, f, indent=2)
print(f"Result written to {result_path}")
PYEOF

echo "=== Export complete ==="