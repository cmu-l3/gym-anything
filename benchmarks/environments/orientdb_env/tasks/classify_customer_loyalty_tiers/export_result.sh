#!/bin/bash
set -euo pipefail

echo "=== Export: classify_customer_loyalty_tiers ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_classify_customer_loyalty_tiers.png

python3 << 'PYEOF'
import json
import urllib.request
import base64
from datetime import datetime

auth = base64.b64encode(b"root:GymAnything123!").decode()
headers = {"Authorization": f"Basic {auth}", "Content-Type": "application/json"}

COHORT = [
    "yuki.tanaka@example.com",
    "carlos.lopez@example.com",
    "thomas.schafer@example.com",
    "piet.vanderberg@example.com",
]


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

lt_cls = classes.get("LoyaltyTier", {})
lt_props = {p.get("name"): p for p in lt_cls.get("properties", [])}
lt_mandatory = {k: bool(v.get("mandatory", False)) for k, v in lt_props.items()}
lt_indexes = []
for idx in lt_cls.get("indexes", []):
    lt_indexes.append({
        "name": idx.get("name", ""),
        "type": (idx.get("type") or "").upper(),
        "fields": idx.get("fields", []) or [],
    })

# Fetch all LoyaltyTier rows
rows = sql("SELECT CustomerEmail, Tier, TotalSpend, CompletedOrderCount FROM LoyaltyTier").get("result", [])

tier_rows = {}
for r in rows:
    email = r.get("CustomerEmail")
    if not email:
        continue
    tier_rows[email] = {
        "Tier": r.get("Tier"),
        "TotalSpend": float(r.get("TotalSpend", 0.0) or 0.0),
        "CompletedOrderCount": int(r.get("CompletedOrderCount", 0) or 0),
    }

# Detect emails outside the expected cohort
unexpected_emails = [e for e in tier_rows if e not in COHORT]

# Load baseline
baseline = {}
try:
    with open("/tmp/classify_customer_loyalty_tiers_baseline.json", "r", encoding="utf-8") as f:
        baseline = json.load(f)
except Exception:
    baseline = {}

result = {
    "export_timestamp": datetime.utcnow().isoformat() + "Z",
    "loyalty_tier_exists": bool(lt_cls),
    "loyalty_tier_properties": sorted(lt_props.keys()),
    "loyalty_tier_mandatory": lt_mandatory,
    "loyalty_tier_indexes": lt_indexes,
    "tier_rows": tier_rows,
    "unexpected_emails": unexpected_emails,
    "baseline_tier_count": int(baseline.get("loyalty_tier_count", 0) or 0),
}

with open("/tmp/classify_customer_loyalty_tiers_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
