#!/bin/bash
set -euo pipefail

echo "=== Export: build_high_value_order_escalations ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_build_high_value_order_escalations.png

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

esc_rows = sql("SELECT OrderedId, EscalationTier, Reason, OwnerEmail, SnapshotPrice FROM OrderEscalation ORDER BY OrderedId").get("result", [])
edge_rows = sql("SELECT out.OrderedId as escalation_ordered_id, in.OrderedId as order_ordered_id FROM EscalatesOrder ORDER BY out.OrderedId").get("result", [])

escalations = {}
for r in esc_rows:
    oid = r.get("OrderedId")
    if oid is None:
        continue
    escalations[str(int(oid))] = {
        "EscalationTier": r.get("EscalationTier"),
        "Reason": r.get("Reason"),
        "OwnerEmail": r.get("OwnerEmail"),
        "SnapshotPrice": float(r.get("SnapshotPrice", 0.0)),
    }

edge_pairs = []
for r in edge_rows:
    out_id = r.get("escalation_ordered_id")
    in_id = r.get("order_ordered_id")
    if out_id is None or in_id is None:
        continue
    edge_pairs.append(f"{int(out_id)}->{int(in_id)}")

schema_data = schema()
classes = {c.get("name"): c for c in schema_data.get("classes", [])}

esc_cls = classes.get("OrderEscalation", {})
esc_props = {p.get("name"): p for p in esc_cls.get("properties", [])}
esc_mandatory = {k: bool(v.get("mandatory", False)) for k, v in esc_props.items()}

esc_indexes = []
for idx in esc_cls.get("indexes", []):
    esc_indexes.append({
        "name": idx.get("name", ""),
        "type": (idx.get("type") or "").upper(),
        "fields": idx.get("fields", []) or [],
    })

baseline = {}
try:
    with open("/tmp/build_high_value_order_escalations_baseline.json", "r", encoding="utf-8") as f:
        baseline = json.load(f)
except Exception:
    baseline = {}

result = {
    "export_timestamp": datetime.utcnow().isoformat() + "Z",
    "order_escalation_exists": bool(esc_cls),
    "order_escalation_properties": sorted(esc_props.keys()),
    "order_escalation_mandatory": esc_mandatory,
    "order_escalation_indexes": esc_indexes,
    "escalates_order_class_exists": "EscalatesOrder" in classes,
    "escalations": escalations,
    "escalation_edges": sorted(edge_pairs),
    "baseline_escalation_count": int(baseline.get("escalation_count", 0) or 0),
    "baseline_escalation_edge_count": int(baseline.get("escalation_edge_count", 0) or 0),
    "unexpected_order_ids": sorted([k for k in escalations.keys() if k not in {"3", "7"}]),
}

with open("/tmp/build_high_value_order_escalations_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
