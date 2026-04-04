#!/bin/bash
# export_result.sh - Post-task export for create_health_check_script

echo "=== Exporting Health Check Results ==="

# Source utils
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
SCRIPT_PATH="/opt/aerobridge/health_check.sh"
REPORT_PATH="/opt/aerobridge/health_report.json"
TASK_START_EPOCH=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ============================================================
# 1. Collect Ground Truth Data
# ============================================================
# We run our own queries to see what the values SHOULD be.
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

# Generate ground truth JSON
GT_JSON=$(/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django, json, time
from django.conf import settings

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

try:
    from registry.models import Aircraft, Company, Person, Pilot
    from gcs_operations.models import FlightPlan, FlightOperation
    from django.contrib.auth.models import User
    
    # DB Counts
    counts = {
        "aircraft": Aircraft.objects.count(),
        "operators": Company.objects.count(),
        "persons": Person.objects.count(),
        "flight_plans": FlightPlan.objects.count(),
        "flight_operations": FlightOperation.objects.count(),
        "users": User.objects.count()
    }
    
    # File Stats
    db_path = settings.DATABASES['default']['NAME']
    db_size = os.path.getsize(db_path) if os.path.exists(db_path) else 0
    
    # Output JSON
    gt = {
        "records": counts,
        "database": {
            "size_bytes": db_size,
            "path": str(db_path)
        },
        "timestamp": time.time()
    }
    print(json.dumps(gt))

except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF
)

# ============================================================
# 2. Analyze Agent's Script & Report
# ============================================================

# Check script properties
SCRIPT_EXISTS="false"
SCRIPT_EXECUTABLE="false"
SCRIPT_CONTENT_SCORE=0
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    if [ -x "$SCRIPT_PATH" ]; then
        SCRIPT_EXECUTABLE="true"
    fi
    
    # Simple content heuristic: does it contain relevant commands?
    if grep -q "curl" "$SCRIPT_PATH" || grep -q "wget" "$SCRIPT_PATH"; then ((SCRIPT_CONTENT_SCORE++)); fi
    if grep -q "python" "$SCRIPT_PATH" || grep -q "manage.py" "$SCRIPT_PATH"; then ((SCRIPT_CONTENT_SCORE++)); fi
    if grep -q "sqlite3" "$SCRIPT_PATH" || grep -q "django" "$SCRIPT_PATH"; then ((SCRIPT_CONTENT_SCORE++)); fi
    if grep -q "df " "$SCRIPT_PATH"; then ((SCRIPT_CONTENT_SCORE++)); fi
fi

# Check report properties
REPORT_EXISTS="false"
REPORT_VALID="false"
REPORT_CONTENT="{}"
REPORT_MTIME=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH")
    
    # Try to read it
    if jq . "$REPORT_PATH" >/dev/null 2>&1; then
        REPORT_VALID="true"
        REPORT_CONTENT=$(cat "$REPORT_PATH")
    else
        # If invalid JSON, read as string but warn
        REPORT_CONTENT="{\"error\": \"Invalid JSON content\"}"
    fi
fi

# Check file created during task
CREATED_DURING_TASK="false"
if [ "$REPORT_MTIME" -gt "$TASK_START_EPOCH" ]; then
    CREATED_DURING_TASK="true"
fi

# ============================================================
# 3. Assemble Final Result
# ============================================================

# Create temporary result file
cat > /tmp/task_result.json << EOF
{
    "script_info": {
        "exists": $SCRIPT_EXISTS,
        "executable": $SCRIPT_EXECUTABLE,
        "content_heuristic_score": $SCRIPT_CONTENT_SCORE
    },
    "report_info": {
        "exists": $REPORT_EXISTS,
        "valid_json": $REPORT_VALID,
        "created_during_task": $CREATED_DURING_TASK
    },
    "agent_report": $REPORT_CONTENT,
    "ground_truth": $GT_JSON,
    "meta": {
        "task_start_epoch": $TASK_START_EPOCH,
        "export_time": $(date +%s)
    }
}
EOF

# Ensure permissions
chmod 644 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="