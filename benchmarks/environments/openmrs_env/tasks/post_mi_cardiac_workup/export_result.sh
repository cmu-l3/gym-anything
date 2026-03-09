#!/bin/bash
# Export: post_mi_cardiac_workup task

echo "=== Exporting post_mi_cardiac_workup result ==="
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/post_mi_cardiac_workup_start_ts 2>/dev/null || echo "0")
PATIENT_UUID=$(cat /tmp/post_mi_cardiac_workup_patient_uuid 2>/dev/null || echo "")
INITIAL_ORDER_COUNT=$(cat /tmp/post_mi_cardiac_workup_initial_order_count 2>/dev/null || echo "0")

if [ -z "$PATIENT_UUID" ]; then
    PATIENT_UUID=$(get_patient_uuid "Jesse Becker")
fi

DISPLAY=:1 import -window root /tmp/post_mi_cardiac_workup_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/post_mi_cardiac_workup_end_screenshot.png 2>/dev/null || true

export EXPORT_PATIENT_UUID="$PATIENT_UUID"
export EXPORT_TASK_START="$TASK_START"
export EXPORT_INITIAL_ORDER_COUNT="$INITIAL_ORDER_COUNT"

python3 - << 'PYEOF' > /tmp/post_mi_cardiac_workup_result.json
import os, json, urllib.request, base64, re
from datetime import datetime

BASE_URL = "http://localhost/openmrs/ws/rest/v1"
AUTH = base64.b64encode(b"admin:Admin123").decode()
PATIENT_UUID = os.environ.get('EXPORT_PATIENT_UUID', '')
TASK_START = int(os.environ.get('EXPORT_TASK_START', '0'))
INITIAL_ORDER_COUNT = int(os.environ.get('EXPORT_INITIAL_ORDER_COUNT', '0'))

def api_get(path):
    req = urllib.request.Request(
        f"{BASE_URL}{path}",
        headers={"Authorization": f"Basic {AUTH}", "Accept": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return json.loads(r.read())
    except Exception:
        return {}

result = {
    "task_start": TASK_START,
    "patient_uuid": PATIENT_UUID,
    "codeine_allergy_added": False,
    "allergy_severity_moderate": False,
    "allergy_reaction_nausea": False,
    "diabetes_condition_added": False,
    "creatinine_ordered": False
}

# --- Check 1: Codeine allergy ---
try:
    allergies = api_get(f"/allergy?patient={PATIENT_UUID}&v=default")
    for a in allergies.get("results", []):
        allergen = a.get("allergen", {})
        coded_name = ((allergen.get("codedAllergen", {}) or {}).get("display", "") or "").lower()
        noncoded_name = (allergen.get("nonCodedAllergen", "") or "").lower()
        full_name = coded_name + " " + noncoded_name
        if "codeine" in full_name:
            result["codeine_allergy_added"] = True
            severity_display = ((a.get("severity", {}) or {}).get("display", "") or "").lower()
            if "moderate" in severity_display:
                result["allergy_severity_moderate"] = True
            for rx in (a.get("reactions", []) or []):
                rx_name = ((rx.get("reaction", {}) or {}).get("display", "") or "").lower()
                if "nausea" in rx_name or "vomit" in rx_name or "emesis" in rx_name:
                    result["allergy_reaction_nausea"] = True
except Exception:
    pass

# --- Check 2: Type 2 diabetes condition ---
try:
    conditions = api_get(f"/condition?patient={PATIENT_UUID}&v=default")
    for cond in conditions.get("results", []):
        cond_name = ""
        concept = cond.get("condition", {})
        if isinstance(concept, dict):
            cond_name = (concept.get("display", "") or "").lower()
        if not cond_name:
            cond_name = str(cond.get("conditionNonCoded", "") or "").lower()
        if any(k in cond_name for k in ("diabet", "type 2", "t2dm", "dm2", "type ii")):
            try:
                audit_created = (cond.get("auditInfo", {}) or {}).get("dateCreated", "") or ""
                onset = cond.get("onsetDate", "") or ""
                date_str = audit_created or onset
                clean = re.sub(r'\.\d{3}', '', date_str.replace("+0000", "+00:00"))
                dt = datetime.fromisoformat(clean)
                cond_ts = dt.timestamp()
            except Exception:
                cond_ts = TASK_START + 1
            if cond_ts >= TASK_START:
                result["diabetes_condition_added"] = True
except Exception:
    pass

# --- Check 3: Creatinine lab order ---
try:
    orders = api_get(f"/order?patient={PATIENT_UUID}&v=default&limit=100")
    current_count = len(orders.get("results", []))
    for order in orders.get("results", []):
        concept_name = ((order.get("concept", {}) or {}).get("display", "") or "").lower()
        drug = (order.get("drug", {}) or {})
        drug_name = (drug.get("display", "") or "").lower()
        full_name = concept_name + " " + drug_name
        if any(k in full_name for k in ("creatinine", "serum creatinine", "renal")):
            date_activated = order.get("dateActivated") or order.get("scheduledDate") or ""
            try:
                clean = re.sub(r'\.\d{3}', '', str(date_activated).replace("+0000", "+00:00"))
                dt = datetime.fromisoformat(clean)
                order_ts = dt.timestamp()
            except Exception:
                order_ts = TASK_START + 1
            if order_ts >= TASK_START:
                result["creatinine_ordered"] = True
                break
    # Fallback: any new order with creatinine in name
    if not result["creatinine_ordered"] and current_count > INITIAL_ORDER_COUNT:
        for order in orders.get("results", []):
            concept_name = ((order.get("concept", {}) or {}).get("display", "") or "").lower()
            if any(k in concept_name for k in ("creatinine", "serum creatinine")):
                result["creatinine_ordered"] = True
                break
except Exception:
    pass

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
cat /tmp/post_mi_cardiac_workup_result.json
