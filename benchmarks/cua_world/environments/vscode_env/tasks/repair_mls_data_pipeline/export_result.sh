#!/bin/bash
set -e
echo "=== Exporting MLS Pipeline Result ==="

source /workspace/scripts/task_utils.sh
WORKSPACE_DIR="/home/ga/workspace/mls_pipeline"
RESULT_FILE="/tmp/task_result.json"

# Capture final state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Focus and save files
focus_vscode_window 2>/dev/null || true
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1

# ─────────────────────────────────────────────────────────────
# Hidden Test Suite Runner
# ─────────────────────────────────────────────────────────────
# We execute this inside the container to dynamically test the agent's code.
cat > /tmp/run_hidden_tests.py << 'EOF'
import sys, os, json, traceback
from unittest.mock import patch, MagicMock

sys.path.insert(0, "/home/ga/workspace/mls_pipeline")

results = {
    "bug1_pagination": False,
    "bug2_timezone": False,
    "bug3_enum": False,
    "bug4_spatial": False,
    "bug5_zerodiv": False,
    "errors": {}
}

# Test 1: Pagination follows nextLink
try:
    from api.client import fetch_all_listings
    call_count = 0
    def mock_get(url):
        global call_count
        call_count += 1
        mock = MagicMock()
        if call_count == 1:
            mock.json.return_value = {"value": [{"id": 1}], "@odata.nextLink": "http://api.com/next"}
        else:
            mock.json.return_value = {"value": [{"id": 2}]}
        return mock

    with patch('requests.get', side_effect=mock_get):
        data = fetch_all_listings("http://api.com/base")
        # If it successfully followed the next link, it should have made 2 calls
        if call_count == 2 and len(data) == 2:
            results["bug1_pagination"] = True
except Exception as e:
    results["errors"]["bug1"] = str(e)

# Test 2: Timezone Aware
try:
    from transformers.datetime_utils import is_active_listing
    res = is_active_listing("2024-01-01T12:00:00Z")
    results["bug2_timezone"] = True
except TypeError:
    results["errors"]["bug2"] = "TypeError: still comparing naive and aware datetimes"
except Exception as e:
    results["errors"]["bug2"] = str(e)

# Test 3: Enum Mapper
try:
    from transformers.property_mapper import map_property_type
    res = map_property_type("Condo / Townhouse")
    if res == "CONDO":
        results["bug3_enum"] = True
except KeyError:
    results["errors"]["bug3"] = "KeyError: Condo / Townhouse not mapped"
except Exception as e:
    results["errors"]["bug3"] = str(e)

# Test 4: Spatial Regex
try:
    from transformers.spatial import parse_wkt_point
    res = parse_wkt_point("POINT (-122.33 47.60)")
    if res and res.get("lon", 0) < 0:
        results["bug4_spatial"] = True
except Exception as e:
    results["errors"]["bug4"] = str(e)

# Test 5: Zero Division
try:
    from analytics.price_stats import calculate_median_ppsqft
    # Includes a 0 sqft entry and a missing sqft entry
    data = [{"ListPrice": 100, "LivingArea": 0}, {"ListPrice": 200, "LivingArea": 100}, {"ListPrice": 300}]
    res = calculate_median_ppsqft(data)
    if res == 2.0:
        results["bug5_zerodiv"] = True
except ZeroDivisionError:
    results["errors"]["bug5"] = "ZeroDivisionError"
except Exception as e:
    results["errors"]["bug5"] = str(e)

with open("/tmp/hidden_test_results.json", "w") as f:
    json.dump(results, f)
EOF

# Run the hidden tests
python3 /tmp/run_hidden_tests.py 2>/dev/null || echo '{"error": "hidden tests script crashed"}' > /tmp/hidden_test_results.json

# ─────────────────────────────────────────────────────────────
# Collect files and modification times
# ─────────────────────────────────────────────────────────────
python3 << 'EOF'
import json, os

workspace = "/home/ga/workspace/mls_pipeline"
task_start = 0
if os.path.exists("/tmp/task_start_time.txt"):
    with open("/tmp/task_start_time.txt", "r") as f:
        task_start = int(f.read().strip())

files_to_check = [
    "api/client.py",
    "transformers/datetime_utils.py",
    "transformers/property_mapper.py",
    "transformers/spatial.py",
    "analytics/price_stats.py"
]

files_data = {}
modified_count = 0

for rel_path in files_to_check:
    full_path = os.path.join(workspace, rel_path)
    content = ""
    is_modified = False
    
    if os.path.exists(full_path):
        mtime = int(os.path.getmtime(full_path))
        is_modified = mtime > task_start
        if is_modified:
            modified_count += 1
            
        with open(full_path, "r", encoding="utf-8") as f:
            content = f.read()
            
    files_data[rel_path] = {
        "is_modified": is_modified,
        "content": content
    }

# Read hidden test results
hidden_results = {}
if os.path.exists("/tmp/hidden_test_results.json"):
    with open("/tmp/hidden_test_results.json", "r") as f:
        hidden_results = json.load(f)

result_payload = {
    "files": files_data,
    "modified_files_count": modified_count,
    "hidden_test_results": hidden_results
}

with open("/tmp/task_result.json", "w", encoding="utf-8") as out:
    json.dump(result_payload, out, indent=2)
EOF

echo "=== Export Complete ==="