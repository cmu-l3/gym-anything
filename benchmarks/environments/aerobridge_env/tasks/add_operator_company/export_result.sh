#!/bin/bash
# export_result.sh — post_task hook for add_operator_company

echo "=== Exporting add_operator_company result ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Retrieve start info
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "unknown")
INITIAL_COUNT=$(cat /tmp/initial_company_count 2>/dev/null || echo "0")

# 3. Python script to query DB and export JSON
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

result = {
    "initial_count": int("$INITIAL_COUNT"),
    "final_count": 0,
    "record_found": False,
    "record_details": {},
    "created_at": None,
    "error": None
}

try:
    from registry.models import Company
    
    # Get final count
    result["final_count"] = Company.objects.count()
    
    # Search for the specific record
    # Look for name containing "Vayupath"
    qs = Company.objects.filter(full_name__icontains="Vayupath")
    
    if qs.exists():
        # Get the most recently created one if multiple
        company = qs.order_by('-created_at').first() if hasattr(Company, 'created_at') else qs.last()
        
        result["record_found"] = True
        result["record_details"] = {
            "full_name": getattr(company, 'full_name', ''),
            "common_name": getattr(company, 'common_name', ''),
            "email": getattr(company, 'email', ''),
            "website": getattr(company, 'website', ''),
            "phone_number": getattr(company, 'phone_number', ''),
            "country": str(getattr(company, 'country', ''))
        }
        
        # Try to get creation timestamp if available
        if hasattr(company, 'created_at') and company.created_at:
            result["created_at"] = company.created_at.isoformat()
            
except Exception as e:
    result["error"] = str(e)

# Save to temp file
with open('/tmp/task_result_temp.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

# 4. Move result file safely
mv /tmp/task_result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="