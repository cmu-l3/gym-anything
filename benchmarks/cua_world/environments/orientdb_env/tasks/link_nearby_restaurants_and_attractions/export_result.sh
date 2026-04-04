#!/bin/bash
set -euo pipefail

echo "=== Export: link_nearby_restaurants_and_attractions ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_link_nearby_restaurants_and_attractions.png

python3 << 'PYEOF'
import json
import urllib.request
import base64
from datetime import datetime

auth = base64.b64encode(b"root:GymAnything123!").decode()
headers = {"Authorization": f"Basic {auth}", "Content-Type": "application/json"}

EXPECTED_PAIRS = {
    ("Da Enzo al 29",          "Colosseum"),
    ("Lorenz Adlon Esszimmer", "Brandenburg Gate"),
    ("Le Cinq",                "Eiffel Tower"),
    ("Sketch",                 "Big Ben"),
    ("Per Se",                 "Statue of Liberty"),
    ("Spondi",                 "Acropolis of Athens"),
    ("Spondi",                 "Parthenon"),
    ("Tickets",                "Sagrada Familia"),
}


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


schema_data = schema()
classes = {c.get("name"): c for c in schema_data.get("classes", [])}

# ProximityLink edge class
pl_cls = classes.get("ProximityLink", {})
pl_props = {p.get("name"): p for p in pl_cls.get("properties", [])}
pl_mandatory = {k: bool(v.get("mandatory", False)) for k, v in pl_props.items()}

# RecommendationManifest class
rm_cls = classes.get("RecommendationManifest", {})
rm_props = {p.get("name"): p for p in rm_cls.get("properties", [])}
rm_mandatory = {k: bool(v.get("mandatory", False)) for k, v in rm_props.items()}
rm_indexes = []
for idx in rm_cls.get("indexes", []):
    rm_indexes.append({
        "name": idx.get("name", ""),
        "type": (idx.get("type") or "").upper(),
        "fields": idx.get("fields", []) or [],
    })

# Fetch ProximityLink edges with city info for cross-city detection
edge_rows = sql(
    "SELECT out.Name as rest_name, out.City as rest_city, "
    "in.Name as attr_name, in.City as attr_city FROM ProximityLink"
).get("result", [])

proximity_edges = []
cross_city_edges = []
for r in edge_rows:
    rest = r.get("rest_name", "")
    attr = r.get("attr_name", "")
    rcity = r.get("rest_city", "")
    acity = r.get("attr_city", "")
    if rest and attr:
        proximity_edges.append(f"{rest}->{attr}")
        if rcity != acity:
            cross_city_edges.append({"restaurant": rest, "r_city": rcity, "attraction": attr, "a_city": acity})

# Fetch RecommendationManifest rows
manifest_rows_raw = sql(
    "SELECT RestaurantName, AttractionName, City, MatchBasis, BatchId FROM RecommendationManifest"
).get("result", [])
manifest_rows = []
for r in manifest_rows_raw:
    manifest_rows.append({
        "RestaurantName": r.get("RestaurantName"),
        "AttractionName": r.get("AttractionName"),
        "City": r.get("City"),
        "MatchBasis": r.get("MatchBasis"),
        "BatchId": r.get("BatchId"),
    })

# Check which expected pairs are present
found_pairs = set()
for r in edge_rows:
    rest = r.get("rest_name", "")
    attr = r.get("attr_name", "")
    if (rest, attr) in EXPECTED_PAIRS:
        found_pairs.add((rest, attr))

missing_pairs = [{"restaurant": r, "attraction": a} for r, a in EXPECTED_PAIRS if (r, a) not in found_pairs]

# Load baseline
baseline = {}
try:
    with open("/tmp/link_nearby_restaurants_and_attractions_baseline.json", "r", encoding="utf-8") as f:
        baseline = json.load(f)
except Exception:
    baseline = {}

result = {
    "export_timestamp": datetime.utcnow().isoformat() + "Z",
    "proximity_link_exists": bool(pl_cls),
    "proximity_link_properties": sorted(pl_props.keys()),
    "proximity_link_mandatory": pl_mandatory,
    "recommendation_manifest_exists": bool(rm_cls),
    "recommendation_manifest_properties": sorted(rm_props.keys()),
    "recommendation_manifest_mandatory": rm_mandatory,
    "recommendation_manifest_indexes": rm_indexes,
    "proximity_edges": sorted(proximity_edges),
    "proximity_edge_count": len(proximity_edges),
    "cross_city_edges": cross_city_edges,
    "manifest_rows": manifest_rows,
    "manifest_row_count": len(manifest_rows),
    "missing_pairs": missing_pairs,
    "baseline_edge_count": int(baseline.get("proximity_edge_count", 0) or 0),
    "baseline_manifest_count": int(baseline.get("manifest_row_count", 0) or 0),
}

with open("/tmp/link_nearby_restaurants_and_attractions_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
