#!/bin/bash
set -euo pipefail

echo "=== Export: reconcile_country_hotel_governance ==="
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_reconcile_country_hotel_governance.png

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


def get_schema():
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

schema = get_schema()
classes = {c.get("name"): c for c in schema.get("classes", [])}

country_rows = sql("SELECT Name, Type FROM Countries WHERE Name in ['United Kingdom','Netherlands']").get("result", [])
hotel_rows = sql("SELECT Name, Country FROM Hotels WHERE Name in ['The Savoy','Intercontinental Amsterdam']").get("result", [])
log_rows = sql("SELECT IssueKey, ResolvedBy FROM GovernanceFixLog ORDER BY IssueKey").get("result", [])

countries = {r.get("Name"): r.get("Type") for r in country_rows if r.get("Name")}
hotels = {r.get("Name"): r.get("Country") for r in hotel_rows if r.get("Name")}

countries_cls = classes.get("Countries", {})
country_indexes = countries_cls.get("indexes", [])
index_info = []
for idx in country_indexes:
    index_info.append({
        "name": idx.get("name", ""),
        "type": (idx.get("type") or "").upper(),
        "fields": idx.get("fields", []) or [],
    })

fix_cls = classes.get("GovernanceFixLog", {})
props = {p.get("name"): p for p in fix_cls.get("properties", [])}
prop_mandatory = {k: bool(v.get("mandatory", False)) for k, v in props.items()}

baseline = {}
try:
    with open("/tmp/reconcile_country_hotel_governance_baseline.json", "r", encoding="utf-8") as f:
        baseline = json.load(f)
except Exception:
    baseline = {}

baseline_countries = {
    r.get("Name"): r.get("Type")
    for r in baseline.get("countries", [])
    if r.get("Name")
}
baseline_hotels = {
    r.get("Name"): r.get("Country")
    for r in baseline.get("hotels", [])
    if r.get("Name")
}

result = {
    "export_timestamp": datetime.utcnow().isoformat() + "Z",
    "countries": countries,
    "hotels": hotels,
    "baseline_countries": baseline_countries,
    "baseline_hotels": baseline_hotels,
    "country_indexes": index_info,
    "governance_fixlog_exists": bool(fix_cls),
    "governance_fixlog_properties": sorted(props.keys()),
    "governance_fixlog_mandatory": prop_mandatory,
    "governance_log_rows": [
        {
            "IssueKey": r.get("IssueKey"),
            "ResolvedBy": r.get("ResolvedBy"),
        }
        for r in log_rows
    ],
}

with open("/tmp/reconcile_country_hotel_governance_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
