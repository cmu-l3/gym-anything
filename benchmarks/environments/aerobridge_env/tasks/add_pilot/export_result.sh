#!/bin/bash
# export_result.sh — post_task hook for add_pilot

echo "=== Exporting add_pilot result ==="

DISPLAY=:1 scrot /tmp/add_pilot_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "unknown")
COUNT_BEFORE=$(cat /tmp/person_count_before 2>/dev/null || echo "0")

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
    "task": "add_pilot",
    "task_start_time": task_start,
    "count_before": count_before,
    "person": None,
    "pilot": None,
    "current_count": 0,
    "error": None
}

try:
    from registry.models import Person, Pilot

    current_count = Person.objects.count()
    result["current_count"] = current_count

    # Search for person by name
    person_qs = Person.objects.filter(first_name='Aditya', last_name='Kumar')
    if not person_qs.exists():
        person_qs = Person.objects.filter(email='aditya.kumar@droneops.in')

    if person_qs.exists():
        p = person_qs.first()
        result["person"] = {
            "id": str(p.pk),
            "first_name": str(getattr(p, 'first_name', '') or ''),
            "last_name": str(getattr(p, 'last_name', '') or ''),
            "email": str(getattr(p, 'email', '') or ''),
        }
        print(f"Found person: {result['person']['first_name']} {result['person']['last_name']}")
        # Also check if a Pilot record exists for this Person
        try:
            pilot_qs = Pilot.objects.filter(person=p)
            if pilot_qs.exists():
                pilot = pilot_qs.first()
                result["pilot"] = {
                    "id": str(pilot.pk),
                    "person_id": str(p.pk),
                    "operator": str(getattr(pilot, 'operator', '') or ''),
                }
                print(f"Found pilot record for person")
            else:
                print("No Pilot record found for this Person")
        except Exception as pe:
            print(f"Pilot lookup note: {pe}")
    else:
        # Most recent fallback
        recent = Person.objects.order_by('-id').first()
        if recent:
            result["person"] = {
                "id": str(recent.pk),
                "first_name": str(getattr(recent, 'first_name', '') or ''),
                "last_name": str(getattr(recent, 'last_name', '') or ''),
                "email": str(getattr(recent, 'email', '') or ''),
                "note": "most_recent_fallback"
            }
        print("Person 'Aditya Kumar' not found")

except Exception as e:
    result["error"] = str(e)
    print(f"Export error: {e}")

result_path = '/tmp/add_pilot_result.json'
with open(result_path, 'w') as f:
    json.dump(result, f, indent=2)
print(f"Result written to {result_path}")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
