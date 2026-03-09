#!/bin/bash
set -euo pipefail

echo "=== Export: materialize_curated_itineraries ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_materialize_curated_itineraries.png

python3 << 'PYEOF'
import json
import urllib.request
import base64
from datetime import datetime

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

visit_rows = sql(
    "SELECT out.Email as Email, in.Name as Monument FROM HasVisited "
    "WHERE out.Email IN ['sophie.martin@example.com','luca.rossi@example.com','elena.petrakis@example.com'] "
    "ORDER BY out.Email"
).get("result", [])

summary_rows = sql(
    "SELECT Email, Country, HotelCount, RestaurantCount, AttractionCount, CurationTag "
    "FROM ItinerarySummary ORDER BY Email"
).get("result", [])

visits = {}
for r in visit_rows:
    email = r.get("Email")
    monument = r.get("Monument")
    if email and monument:
        visits[email] = monument

summary = {}
for r in summary_rows:
    email = r.get("Email")
    if not email:
        continue
    summary[email] = {
        "Country": r.get("Country"),
        "HotelCount": int(r.get("HotelCount", 0)),
        "RestaurantCount": int(r.get("RestaurantCount", 0)),
        "AttractionCount": int(r.get("AttractionCount", 0)),
        "CurationTag": r.get("CurationTag"),
    }

schema_data = schema()
classes = {c.get("name"): c for c in schema_data.get("classes", [])}
sum_cls = classes.get("ItinerarySummary", {})
props = {p.get("name"): p for p in sum_cls.get("properties", [])}
mandatory = {k: bool(v.get("mandatory", False)) for k, v in props.items()}
indexes = []
for idx in sum_cls.get("indexes", []):
    indexes.append({
        "name": idx.get("name", ""),
        "type": (idx.get("type") or "").upper(),
        "fields": idx.get("fields", []) or [],
    })

baseline = {}
try:
    with open("/tmp/materialize_curated_itineraries_baseline.json", "r", encoding="utf-8") as f:
        baseline = json.load(f)
except Exception:
    baseline = {}

result = {
    "export_timestamp": datetime.utcnow().isoformat() + "Z",
    "visits": visits,
    "itinerary_summary_exists": bool(sum_cls),
    "itinerary_summary_properties": sorted(props.keys()),
    "itinerary_summary_mandatory": mandatory,
    "itinerary_summary_indexes": indexes,
    "summary": summary,
    "summary_row_count": len(summary_rows),
    "baseline_visit_count": int(baseline.get("visit_count", 0) or 0),
    "baseline_summary_row_count": int(baseline.get("summary_row_count", 0) or 0),
}

with open("/tmp/materialize_curated_itineraries_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
