#!/bin/bash
set -euo pipefail

echo "=== Export: aggregate_hotel_country_metrics ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_aggregate_hotel_country_metrics.png

python3 << 'PYEOF'
import json
import urllib.request
import base64
from datetime import datetime

auth = base64.b64encode(b"root:GymAnything123!").decode()
headers = {"Authorization": f"Basic {auth}", "Content-Type": "application/json"}

VALID_COUNTRIES = {
    "Italy", "Germany", "France", "United Kingdom", "United States",
    "Japan", "Australia", "Brazil", "Spain", "Greece", "Netherlands"
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

hcm_cls = classes.get("HotelCountryMetrics", {})
hcm_props = {p.get("name"): p for p in hcm_cls.get("properties", [])}
hcm_mandatory = {k: bool(v.get("mandatory", False)) for k, v in hcm_props.items()}
hcm_indexes = []
for idx in hcm_cls.get("indexes", []):
    hcm_indexes.append({
        "name": idx.get("name", ""),
        "type": (idx.get("type") or "").upper(),
        "fields": idx.get("fields", []) or [],
    })

# Fetch all HotelCountryMetrics rows
rows = sql("SELECT Country, TotalHotels, LuxuryCount, ReportBatch FROM HotelCountryMetrics").get("result", [])

metrics_rows = {}
for r in rows:
    country = r.get("Country")
    if not country:
        continue
    metrics_rows[country] = {
        "TotalHotels": int(r.get("TotalHotels", 0) or 0),
        "LuxuryCount": int(r.get("LuxuryCount", 0) or 0),
        "ReportBatch": r.get("ReportBatch"),
    }

# Detect countries outside the valid set
unexpected_countries = [c for c in metrics_rows if c not in VALID_COUNTRIES]

# Load baseline
baseline = {}
try:
    with open("/tmp/aggregate_hotel_country_metrics_baseline.json", "r", encoding="utf-8") as f:
        baseline = json.load(f)
except Exception:
    baseline = {}

result = {
    "export_timestamp": datetime.utcnow().isoformat() + "Z",
    "hotel_country_metrics_exists": bool(hcm_cls),
    "hotel_country_metrics_properties": sorted(hcm_props.keys()),
    "hotel_country_metrics_mandatory": hcm_mandatory,
    "hotel_country_metrics_indexes": hcm_indexes,
    "metrics_rows": metrics_rows,
    "metrics_row_count": len(metrics_rows),
    "unexpected_countries": unexpected_countries,
    "baseline_metrics_count": int(baseline.get("metrics_count", 0) or 0),
    "baseline_country_hotel_counts": baseline.get("country_hotel_counts", {}),
}

with open("/tmp/aggregate_hotel_country_metrics_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
