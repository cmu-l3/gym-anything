#!/bin/bash
set -euo pipefail

echo "=== Export: backfill_reciprocal_travel_friendships ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_backfill_reciprocal_travel_friendships.png

python3 << 'PYEOF'
import json
import urllib.request
import base64
from datetime import datetime

EXPECTED = {
    "david.jones@example.com->john.smith@example.com",
    "david.jones@example.com->emma.white@example.com",
    "sophie.martin@example.com->maria.garcia@example.com",
}
COHORT = {
    "john.smith@example.com",
    "david.jones@example.com",
    "emma.white@example.com",
    "maria.garcia@example.com",
    "sophie.martin@example.com",
}

auth = base64.b64encode(b"root:GymAnything123!").decode()
headers = {"Authorization": f"Basic {auth}", "Content-Type": "application/json"}


def sql(cmd):
    req = urllib.request.Request(
        "http://localhost:2480/command/demodb/sql",
        data=json.dumps({"command": cmd}).encode(),
        headers=headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.loads(r.read())
    except Exception:
        return {}


def schema():
    req = urllib.request.Request(
        "http://localhost:2480/database/demodb",
        headers={"Authorization": f"Basic {auth}"},
        method="GET",
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.loads(r.read())
    except Exception:
        return {}

reverse_rows = sql(
    "SELECT out.Email as src, in.Email as dst FROM HasFriend WHERE "
    "(out.Email='david.jones@example.com' AND in.Email='john.smith@example.com') OR "
    "(out.Email='david.jones@example.com' AND in.Email='emma.white@example.com') OR "
    "(out.Email='sophie.martin@example.com' AND in.Email='maria.garcia@example.com')"
).get("result", [])

all_aff = sql("SELECT out.Email as src, in.Email as dst, SharedHotels, CountryOverlap, RuleVersion FROM TravelAffinity").get("result", [])

pairs = []
unexpected_pairs = []
for row in all_aff:
    src = row.get("src")
    dst = row.get("dst")
    if not src or not dst:
        continue
    pair = f"{src}->{dst}"
    rec = {
        "pair": pair,
        "src": src,
        "dst": dst,
        "SharedHotels": row.get("SharedHotels"),
        "CountryOverlap": row.get("CountryOverlap"),
        "RuleVersion": row.get("RuleVersion"),
    }
    pairs.append(rec)
    if pair not in EXPECTED:
        unexpected_pairs.append(pair)

schema_data = schema()
classes = {c.get("name"): c for c in schema_data.get("classes", [])}
aff_cls = classes.get("TravelAffinity", {})
props = {p.get("name"): p for p in aff_cls.get("properties", [])}
mandatory = {k: bool(v.get("mandatory", False)) for k, v in props.items()}

baseline = {}
try:
    with open("/tmp/backfill_reciprocal_travel_friendships_baseline.json", "r", encoding="utf-8") as f:
        baseline = json.load(f)
except Exception:
    baseline = {}

baseline_reverse_edges = sorted({
    f"{r.get('src')}->{r.get('dst')}"
    for r in baseline.get("reverse_edges", [])
    if r.get("src") and r.get("dst")
})
baseline_affinity_count = int(baseline.get("travel_affinity_count", 0) or 0)

result = {
    "export_timestamp": datetime.utcnow().isoformat() + "Z",
    "reverse_edges": sorted({f"{r.get('src')}->{r.get('dst')}" for r in reverse_rows if r.get('src') and r.get('dst')}),
    "baseline_reverse_edges": baseline_reverse_edges,
    "baseline_travel_affinity_count": baseline_affinity_count,
    "travel_affinity_exists": bool(aff_cls),
    "travel_affinity_properties": sorted(props.keys()),
    "travel_affinity_mandatory": mandatory,
    "travel_affinity_edges": sorted(pairs, key=lambda x: x["pair"]),
    "unexpected_travel_affinity_pairs": sorted(set(unexpected_pairs)),
    "cohort_size": len(COHORT),
}

with open("/tmp/backfill_reciprocal_travel_friendships_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
