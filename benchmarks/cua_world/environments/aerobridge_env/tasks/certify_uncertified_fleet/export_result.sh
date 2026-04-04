#!/bin/bash
# export_result.sh — post_task hook for certify_uncertified_fleet

echo "=== Exporting certify_uncertified_fleet result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Metadata
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "unknown")
INITIAL_UNCERTIFIED=$(cat /tmp/initial_uncertified_count.txt 2>/dev/null || echo "3")
REPORT_PATH="/home/ga/compliance_report.txt"

# 3. Check for Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Read first 10 lines of report for verification
    REPORT_CONTENT=$(head -n 20 "$REPORT_PATH" | base64 -w 0)
fi

# 4. Query Django Database for Verification
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << PYEOF
import os, sys, django, json
from datetime import datetime
import pytz

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

from registry.models import Aircraft, TypeCertificate

# Load task start time for comparison
try:
    start_time_str = "${TASK_START}"
    # Simple parse assuming ISO format from date -u command
    task_start = datetime.strptime(start_time_str, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=pytz.UTC)
except Exception:
    task_start = datetime.now(pytz.UTC)

# Metrics
total_aircraft = Aircraft.objects.count()
uncertified_count = Aircraft.objects.filter(type_certificate__isnull=True).count()
certified_count = Aircraft.objects.filter(type_certificate__isnull=False).count()

# Anti-Gaming: Check if new certificates were actually created during the task
# (vs. just assigning old ones or deleting the aircraft)
new_certs_count = 0
try:
    # Check created_at if available, otherwise rely on ID or simple existence
    # Note: Aerobridge models usually have created_at/updated_at
    new_certs = TypeCertificate.objects.filter(created_at__gte=task_start)
    new_certs_count = new_certs.count()
except Exception:
    # Fallback if created_at not queryable
    pass

# Verify specific aircraft that were targeted
target_names = ["Project X-1 Prototype", "Surveyor Alpha", "Cargo Lifter V2"]
targets_status = {}
for name in target_names:
    ac = Aircraft.objects.filter(name=name).first()
    if ac:
        targets_status[name] = {
            "exists": True,
            "has_cert": ac.type_certificate is not None,
            "cert_id": str(ac.type_certificate) if ac.type_certificate else None
        }
    else:
        targets_status[name] = {"exists": False}

result = {
    "total_aircraft": total_aircraft,
    "uncertified_remaining": uncertified_count,
    "certified_count": certified_count,
    "initial_uncertified_count": int("${INITIAL_UNCERTIFIED}"),
    "new_certs_created_count": new_certs_count,
    "targets_status": targets_status,
    "report_exists": "${REPORT_EXISTS}" == "true",
    "report_content_b64": "${REPORT_CONTENT}",
    "timestamp": datetime.now().isoformat()
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="