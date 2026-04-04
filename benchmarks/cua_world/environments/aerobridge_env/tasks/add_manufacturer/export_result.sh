#!/bin/bash
# export_result.sh — post_task hook for add_manufacturer

echo "=== Exporting add_manufacturer result ==="

DISPLAY=:1 scrot /tmp/add_manufacturer_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "unknown")
COUNT_BEFORE=$(cat /tmp/manufacturer_count_before 2>/dev/null || echo "0")

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

task_start = '${TASK_START}'
count_before = int('${COUNT_BEFORE}' or '0')

result = {
    "task": "add_manufacturer",
    "task_start_time": task_start,
    "count_before": count_before,
    "manufacturer": None,
    "current_count": 0,
    "error": None
}

try:
    from registry.models import Company

    current_count = Company.objects.count()
    result["current_count"] = current_count

    mfr_qs = Company.objects.filter(full_name='SkyTech Innovations')
    if mfr_qs.exists():
        m = mfr_qs.first()
        result["manufacturer"] = {
            "id": m.pk,
            "full_name": str(getattr(m, 'full_name', '') or ''),
            "country": str(getattr(m, 'country', '') or ''),
        }
        print(f"Found company: {result['manufacturer']['full_name']}")
    else:
        recent = Company.objects.order_by('-id').first()
        if recent:
            result["manufacturer"] = {
                "id": recent.pk,
                "full_name": str(getattr(recent, 'full_name', '') or ''),
                "country": str(getattr(recent, 'country', '') or ''),
                "note": "most_recent_fallback"
            }
        print("Company 'SkyTech Innovations' not found")

except Exception as e:
    result["error"] = str(e)
    print(f"Export error: {e}")

result_path = '/tmp/add_manufacturer_result.json'
with open(result_path, 'w') as f:
    json.dump(result, f, indent=2)
print(f"Result written to {result_path}")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
