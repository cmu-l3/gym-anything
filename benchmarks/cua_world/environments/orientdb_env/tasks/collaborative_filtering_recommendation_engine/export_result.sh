#!/bin/bash
set -euo pipefail

echo "=== Export: collaborative_filtering_recommendation_engine ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_collaborative_filtering_recommendation_engine.png

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


schema_data = schema()
classes = {c.get("name"): c for c in schema_data.get("classes", [])}

# ------- SimilarTraveler edge class -------
st_cls = classes.get("SimilarTraveler", {})
st_props = {p.get("name"): p for p in st_cls.get("properties", [])}
st_mandatory = {k: bool(v.get("mandatory", False)) for k, v in st_props.items()}

# Fetch all SimilarTraveler edges
st_edges_raw = sql(
    "SELECT out.Email as src, in.Email as dst, SharedHotelCount, SimilarityScore "
    "FROM SimilarTraveler"
).get("result", [])
st_edges = []
for r in st_edges_raw:
    src = r.get("src")
    dst = r.get("dst")
    if src and dst:
        st_edges.append({
            "src": src,
            "dst": dst,
            "SharedHotelCount": r.get("SharedHotelCount"),
            "SimilarityScore": r.get("SimilarityScore"),
        })

# ------- HotelRecommendation vertex class -------
hr_cls = classes.get("HotelRecommendation", {})
hr_props = {p.get("name"): p for p in hr_cls.get("properties", [])}
hr_mandatory = {k: bool(v.get("mandatory", False)) for k, v in hr_props.items()}
hr_indexes = []
for idx in hr_cls.get("indexes", []):
    hr_indexes.append({
        "name": idx.get("name", ""),
        "type": (idx.get("type") or "").upper(),
        "fields": idx.get("fields", []) or [],
    })

# Fetch all HotelRecommendation vertices
hr_rows_raw = sql(
    "SELECT TargetEmail, HotelName, RecommendedBy, Score "
    "FROM HotelRecommendation"
).get("result", [])
hr_rows = []
for r in hr_rows_raw:
    hr_rows.append({
        "TargetEmail": r.get("TargetEmail"),
        "HotelName": r.get("HotelName"),
        "RecommendedBy": r.get("RecommendedBy"),
        "Score": r.get("Score"),
    })

# ------- RecommendationReport vertex class -------
rr_cls = classes.get("RecommendationReport", {})
rr_props = {p.get("name"): p for p in rr_cls.get("properties", [])}
rr_mandatory = {k: bool(v.get("mandatory", False)) for k, v in rr_props.items()}

rr_rows_raw = sql(
    "SELECT TotalRecommendations, ProfilesWithRecommendations, "
    "MostRecommendedHotel, HighestSimilarityPair, ReportBatch "
    "FROM RecommendationReport"
).get("result", [])
rr_row = rr_rows_raw[0] if rr_rows_raw else {}

# ------- Load baseline -------
baseline = {}
try:
    with open("/tmp/collaborative_filtering_recommendation_engine_baseline.json", "r", encoding="utf-8") as f:
        baseline = json.load(f)
except Exception:
    baseline = {}

result = {
    "export_timestamp": datetime.utcnow().isoformat() + "Z",
    # SimilarTraveler
    "similar_traveler_exists": bool(st_cls),
    "similar_traveler_properties": sorted(st_props.keys()),
    "similar_traveler_mandatory": st_mandatory,
    "similar_traveler_edges": st_edges,
    "similar_traveler_edge_count": len(st_edges),
    # HotelRecommendation
    "hotel_recommendation_exists": bool(hr_cls),
    "hotel_recommendation_properties": sorted(hr_props.keys()),
    "hotel_recommendation_mandatory": hr_mandatory,
    "hotel_recommendation_indexes": hr_indexes,
    "hotel_recommendation_rows": hr_rows,
    "hotel_recommendation_count": len(hr_rows),
    # RecommendationReport
    "recommendation_report_exists": bool(rr_cls),
    "recommendation_report_properties": sorted(rr_props.keys()),
    "recommendation_report_mandatory": rr_mandatory,
    "recommendation_report": {
        "TotalRecommendations": rr_row.get("TotalRecommendations"),
        "ProfilesWithRecommendations": rr_row.get("ProfilesWithRecommendations"),
        "MostRecommendedHotel": rr_row.get("MostRecommendedHotel"),
        "HighestSimilarityPair": rr_row.get("HighestSimilarityPair"),
        "ReportBatch": rr_row.get("ReportBatch"),
    },
    # Baseline
    "baseline_similar_traveler_count": int(baseline.get("similar_traveler_count", 0) or 0),
    "baseline_recommendation_count": int(baseline.get("recommendation_count", 0) or 0),
    "baseline_report_count": int(baseline.get("report_count", 0) or 0),
}

with open("/tmp/collaborative_filtering_recommendation_engine_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
