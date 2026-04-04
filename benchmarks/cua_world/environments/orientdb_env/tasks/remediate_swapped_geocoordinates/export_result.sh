#!/bin/bash
set -euo pipefail

echo "=== Export: remediate_swapped_geocoordinates ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_remediate_swapped_geocoordinates.png

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

coords_rows = sql("SELECT Name, Latitude, Longitude FROM Hotels WHERE Name IN ['The Plaza Hotel','Park Hyatt Tokyo','Four Seasons Sydney']").get("result", [])
audit_rows = sql("SELECT HotelName, PreviousLatitude, PreviousLongitude, NewLatitude, NewLongitude, FixBatch FROM GeoFixAudit ORDER BY HotelName").get("result", [])

coords = {}
for r in coords_rows:
    name = r.get("Name")
    if not name:
        continue
    coords[name] = {
        "Latitude": float(r.get("Latitude", 0.0)),
        "Longitude": float(r.get("Longitude", 0.0)),
    }

schema_data = schema()
classes = {c.get("name"): c for c in schema_data.get("classes", [])}
geo_cls = classes.get("GeoFixAudit", {})
props = {p.get("name"): p for p in geo_cls.get("properties", [])}
mandatory = {k: bool(v.get("mandatory", False)) for k, v in props.items()}

baseline = {}
try:
    with open("/tmp/remediate_swapped_geocoordinates_baseline.json", "r", encoding="utf-8") as f:
        baseline = json.load(f)
except Exception:
    baseline = {}

result = {
    "export_timestamp": datetime.utcnow().isoformat() + "Z",
    "coordinates": coords,
    "baseline_coordinates": baseline.get("coordinates", {}),
    "geo_fix_audit_exists": bool(geo_cls),
    "geo_fix_audit_properties": sorted(props.keys()),
    "geo_fix_audit_mandatory": mandatory,
    "geo_fix_audit_rows": [
        {
            "HotelName": r.get("HotelName"),
            "PreviousLatitude": r.get("PreviousLatitude"),
            "PreviousLongitude": r.get("PreviousLongitude"),
            "NewLatitude": r.get("NewLatitude"),
            "NewLongitude": r.get("NewLongitude"),
            "FixBatch": r.get("FixBatch"),
        }
        for r in audit_rows
    ],
}

with open("/tmp/remediate_swapped_geocoordinates_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
