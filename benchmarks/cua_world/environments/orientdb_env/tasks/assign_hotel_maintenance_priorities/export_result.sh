#!/bin/bash
set -euo pipefail

echo "=== Export: assign_hotel_maintenance_priorities ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_assign_hotel_maintenance_priorities.png

python3 << 'PYEOF'
import json
import urllib.request
import base64
from datetime import datetime

auth = base64.b64encode(b"root:GymAnything123!").decode()
headers = {"Authorization": f"Basic {auth}", "Content-Type": "application/json"}

VALID_PRIORITIES = {"CRITICAL", "HIGH", "STANDARD"}

# Ground-truth priority mapping derived from seed data
EXPECTED_PRIORITIES = {
    "Hotel Adlon Kempinski":   "CRITICAL",
    "Hotel de Crillon":        "CRITICAL",
    "The Savoy":               "CRITICAL",
    "Park Hyatt Tokyo":        "CRITICAL",
    "Four Seasons Sydney":     "CRITICAL",
    "Intercontinental Amsterdam": "CRITICAL",
    "The Plaza Hotel":         "HIGH",
    "Copacabana Palace":       "HIGH",
    "Hotel Arts Barcelona":    "HIGH",
    "Grande Bretagne Hotel":   "HIGH",
    "Hotel Villa d Este":      "HIGH",
    "Baglioni Hotel Luna":     "HIGH",
    "Hotel Artemide":          "STANDARD",
    "Fairmont Le Manoir":      "STANDARD",
    "Melia Berlin":            "STANDARD",
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

hmf_cls = classes.get("HotelMaintenanceFlag", {})
hmf_props = {p.get("name"): p for p in hmf_cls.get("properties", [])}
hmf_mandatory = {k: bool(v.get("mandatory", False)) for k, v in hmf_props.items()}
hmf_indexes = []
for idx in hmf_cls.get("indexes", []):
    hmf_indexes.append({
        "name": idx.get("name", ""),
        "type": (idx.get("type") or "").upper(),
        "fields": idx.get("fields", []) or [],
    })

# Fetch all flag rows
flag_rows_raw = sql("SELECT HotelName, Priority, LastInspectionYear, MaintenanceBatch FROM HotelMaintenanceFlag").get("result", [])
flag_rows = {}
for r in flag_rows_raw:
    name = r.get("HotelName")
    if name:
        flag_rows[name] = {
            "Priority": r.get("Priority"),
            "LastInspectionYear": int(r.get("LastInspectionYear", 0) or 0),
            "MaintenanceBatch": r.get("MaintenanceBatch"),
        }

# Priority distribution
priority_counts = {"CRITICAL": 0, "HIGH": 0, "STANDARD": 0}
for v in flag_rows.values():
    p = v.get("Priority")
    if p in priority_counts:
        priority_counts[p] += 1

# Detect wrong-priority assignments
wrong_priority_hotels = []
for hotel, actual in flag_rows.items():
    expected_p = EXPECTED_PRIORITIES.get(hotel)
    if expected_p and actual.get("Priority") != expected_p:
        wrong_priority_hotels.append({
            "hotel": hotel,
            "expected": expected_p,
            "actual": actual.get("Priority"),
        })

# Edge count
edge_count_raw = sql("SELECT COUNT(*) as cnt FROM RequiresMaintenance").get("result", [{}])
edge_count = int(edge_count_raw[0].get("cnt", 0) if edge_count_raw else 0)

# Load baseline
baseline = {}
try:
    with open("/tmp/assign_hotel_maintenance_priorities_baseline.json", "r", encoding="utf-8") as f:
        baseline = json.load(f)
except Exception:
    baseline = {}

result = {
    "export_timestamp": datetime.utcnow().isoformat() + "Z",
    "maintenance_flag_exists": bool(hmf_cls),
    "maintenance_flag_properties": sorted(hmf_props.keys()),
    "maintenance_flag_mandatory": hmf_mandatory,
    "maintenance_flag_indexes": hmf_indexes,
    "requires_maintenance_exists": "RequiresMaintenance" in classes,
    "flag_rows": flag_rows,
    "flag_row_count": len(flag_rows),
    "priority_counts": priority_counts,
    "wrong_priority_hotels": wrong_priority_hotels,
    "edge_count": edge_count,
    "baseline_flag_count": int(baseline.get("maintenance_flag_count", 0) or 0),
    "baseline_edge_count": int(baseline.get("maintenance_edge_count", 0) or 0),
}

with open("/tmp/assign_hotel_maintenance_priorities_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
