#!/bin/bash
set -euo pipefail

echo "=== Export: backfill_attraction_visit_counts ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_backfill_attraction_visit_counts.png

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

# Check VisitCount property on Attractions
attr_cls = classes.get("Attractions", {})
attr_props = {p.get("name"): p for p in attr_cls.get("properties", [])}
visit_count_property_exists = "VisitCount" in attr_props

# AttractionVisitAudit schema
ava_cls = classes.get("AttractionVisitAudit", {})
ava_props = {p.get("name"): p for p in ava_cls.get("properties", [])}
ava_mandatory = {k: bool(v.get("mandatory", False)) for k, v in ava_props.items()}
ava_indexes = []
for idx in ava_cls.get("indexes", []):
    ava_indexes.append({
        "name": idx.get("name", ""),
        "type": (idx.get("type") or "").upper(),
        "fields": idx.get("fields", []) or [],
    })

# Fetch VisitCount values for all attractions (polymorphic)
visit_rows = sql("SELECT Name, VisitCount FROM Attractions").get("result", [])
visit_counts = {}
for r in visit_rows:
    name = r.get("Name")
    if name:
        vc = r.get("VisitCount")
        visit_counts[name] = int(vc) if vc is not None else None

# Fetch AttractionVisitAudit rows
audit_rows_raw = sql("SELECT AttractionName, NewVisitCount, AuditBatch FROM AttractionVisitAudit").get("result", [])
audit_rows = {}
for r in audit_rows_raw:
    name = r.get("AttractionName")
    if name:
        audit_rows[name] = {
            "NewVisitCount": int(r.get("NewVisitCount", 0) or 0),
            "AuditBatch": r.get("AuditBatch"),
        }

# Load baseline
baseline = {}
try:
    with open("/tmp/backfill_attraction_visit_counts_baseline.json", "r", encoding="utf-8") as f:
        baseline = json.load(f)
except Exception:
    baseline = {}

result = {
    "export_timestamp": datetime.utcnow().isoformat() + "Z",
    "visit_count_property_exists": visit_count_property_exists,
    "attraction_visit_audit_exists": bool(ava_cls),
    "attraction_visit_audit_properties": sorted(ava_props.keys()),
    "attraction_visit_audit_mandatory": ava_mandatory,
    "attraction_visit_audit_indexes": ava_indexes,
    "visit_counts": visit_counts,
    "audit_rows": audit_rows,
    "audit_row_count": len(audit_rows),
    "baseline_has_visited_count": int(baseline.get("has_visited_edge_count", 0) or 0),
    "baseline_audit_row_count": int(baseline.get("audit_row_count", 0) or 0),
}

with open("/tmp/backfill_attraction_visit_counts_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
