#!/bin/bash
# export_result.sh - Validate results and export to JSON
set -e

echo "=== Exporting task results ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Python script to validate logic (File content + DB state)
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django, json
import pytz
from datetime import datetime

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

# Import Model
FlightPlan = None
try:
    from flight_passport.models import FlightPlan
except ImportError:
    try:
        from gcs_operations.models import FlightPlan
    except ImportError:
        pass

# Load Expected Data
try:
    with open('/tmp/expected_flight_data.json', 'r') as f:
        expected = json.load(f)
except FileNotFoundError:
    expected = {"historical_names": [], "active_names": []}

ARCHIVE_PATH = "/home/ga/archive_pre2024.json"
TASK_START_TIME = 0
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        TASK_START_TIME = int(f.read().strip())
except:
    pass

result = {
    "archive_exists": False,
    "archive_valid_json": False,
    "archive_created_during_task": False,
    "archived_names_found": [],
    "db_historical_count": -1,
    "db_active_count": -1,
    "db_active_names_preserved": False,
    "errors": []
}

# --- CHECK 1: Archive File ---
if os.path.exists(ARCHIVE_PATH):
    result["archive_exists"] = True
    
    # Check creation time
    mtime = int(os.path.getmtime(ARCHIVE_PATH))
    if mtime > TASK_START_TIME:
        result["archive_created_during_task"] = True
    
    # Check JSON content
    try:
        with open(ARCHIVE_PATH, 'r') as f:
            data = json.load(f)
        result["archive_valid_json"] = True
        
        # Flatten data to look for names (handles Django serialize format or simple dict list)
        # Django serialize: [{"fields": {"name": "..."}}, ...]
        # Simple dict: [{"name": "..."}, ...]
        found_names = []
        if isinstance(data, list):
            for item in data:
                name = None
                if isinstance(item, dict):
                    if "fields" in item and "name" in item["fields"]:
                        name = item["fields"]["name"]
                    elif "name" in item:
                        name = item["name"]
                if name:
                    found_names.append(name)
        
        # Check intersection with expected historical names
        exp_hist = set(expected["historical_names"])
        found_set = set(found_names)
        found_intersection = list(exp_hist.intersection(found_set))
        result["archived_names_found"] = found_intersection
        
    except json.JSONDecodeError:
        result["errors"].append("Archive file is not valid JSON")
    except Exception as e:
        result["errors"].append(f"Error reading archive: {str(e)}")
else:
    result["errors"].append("Archive file not found")

# --- CHECK 2: Database State ---
if FlightPlan:
    # Check if historical records are GONE
    # We can check by ID or by Name/Date. 
    # Since we injected specific IDs, let's check if those IDs exist.
    
    hist_still_in_db = FlightPlan.objects.filter(pk__in=expected["historical_ids"]).count()
    result["db_historical_count"] = hist_still_in_db
    
    # Check if active records REMAIN
    active_in_db = FlightPlan.objects.filter(pk__in=expected["active_ids"]).count()
    result["db_active_count"] = active_in_db
    
    if active_in_db == len(expected["active_ids"]):
        result["db_active_names_preserved"] = True
else:
    result["errors"].append("Could not load FlightPlan model for verification")

# Write Result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Validation complete. Result:")
print(json.dumps(result, indent=2))
PYEOF

# Move result to accessible location
rm -f /tmp/final_result.json 2>/dev/null || true
cp /tmp/task_result.json /tmp/final_result.json
chmod 666 /tmp/final_result.json

echo "=== Export complete ==="