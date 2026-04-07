#!/bin/bash
echo "=== Exporting power_dependency_mapping results ==="

source /workspace/scripts/task_utils.sh

# Record end timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python export script
python3 << 'PYEOF'
import sys, json, os
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

# Load baseline
try:
    with open("/tmp/pdm_baseline.json", "r") as f:
        baseline = json.load(f)
except FileNotFoundError:
    print("ERROR: Baseline not found")
    sys.exit(1)

token = get_token()
if not token:
    print("ERROR: Auth failed")
    sys.exit(1)

asset_cls = baseline.get("asset_class")
ci_map = baseline.get("ci_map", {})

results = {
    "cis_found": {},
    "relations_found": []
}

# 1. Verify existence of CIs
for code, card_id in ci_map.items():
    card = get_card(asset_cls, card_id, token)
    if card:
        results["cis_found"][code] = {
            "exists": True,
            "id": card_id,
            "active": card.get("_is_active", True)
        }
    else:
        results["cis_found"][code] = {"exists": False}

# 2. Extract all relations for these cards
# We build an adjacency list of (src_code, dst_code)
# API returns relations: GET /classes/{class}/cards/{id}/relations
# Response items have 'srcId', 'dstId', 'domain'

# Helper to find code by ID
id_to_code = {v: k for k, v in ci_map.items()}

for code, card_id in ci_map.items():
    if not results["cis_found"][code]["exists"]:
        continue
        
    rels = api("GET", f"classes/{asset_cls}/cards/{card_id}/relations", token)
    if rels and "data" in rels:
        for r in rels["data"]:
            # Depending on API version, keys might be _src_id/_dst_id or srcId/dstId
            # CMDBuild v3 often uses _src_id, _dst_id in REST
            src_id = r.get("_src_id") or r.get("srcId")
            dst_id = r.get("_dst_id") or r.get("dstId")
            
            # Map back to codes if both ends are in our set
            src_code = id_to_code.get(str(src_id))
            dst_code = id_to_code.get(str(dst_id))
            
            if src_code and dst_code:
                # Avoid duplicates
                rel_entry = {"src": src_code, "dst": dst_code, "domain": r.get("_domain_id")}
                if rel_entry not in results["relations_found"]:
                    results["relations_found"].append(rel_entry)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(results, f, indent=2)

print("Export complete.")
PYEOF

# Add timestamp metadata to result
# We use jq to merge or python if jq is missing, but simpler to just append or rewrite
# Let's just use python to append metadata
python3 -c "
import json
try:
    with open('/tmp/task_result.json', 'r') as f:
        d = json.load(f)
    d['task_start'] = $TASK_START
    d['task_end'] = $TASK_END
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(d, f)
except Exception:
    pass
"

cat /tmp/task_result.json
echo "=== Export complete ==="