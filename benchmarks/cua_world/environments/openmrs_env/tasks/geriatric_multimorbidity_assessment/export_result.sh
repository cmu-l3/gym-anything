#!/bin/bash
# Export: geriatric_multimorbidity_assessment task

echo "=== Exporting geriatric_multimorbidity_assessment result ==="
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/geriatric_multimorbidity_assessment_start_ts 2>/dev/null || echo "0")
PATIENT_UUID=$(cat /tmp/geriatric_multimorbidity_assessment_patient_uuid 2>/dev/null || echo "")
INITIAL_ORDER_COUNT=$(cat /tmp/geriatric_multimorbidity_assessment_initial_order_count 2>/dev/null || echo "0")

if [ -z "$PATIENT_UUID" ]; then
    PATIENT_UUID=$(get_patient_uuid "Corie Bergnaum")
fi

DISPLAY=:1 import -window root /tmp/geriatric_multimorbidity_assessment_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/geriatric_multimorbidity_assessment_end_screenshot.png 2>/dev/null || true

export EXPORT_PATIENT_UUID="$PATIENT_UUID"
export EXPORT_TASK_START="$TASK_START"
export EXPORT_INITIAL_ORDER_COUNT="$INITIAL_ORDER_COUNT"

python3 - << 'PYEOF' > /tmp/geriatric_multimorbidity_assessment_result.json
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
    "vitals_recorded": False,
    "vitals_details": {
        "bp_systolic": False,
        "weight": False,
        "pulse": False,
        "temperature": False
    },
    "migraine_condition_added": False,
    "acetaminophen_ordered": False
}

# --- Check 1: Vitals ---
VITAL_CONCEPTS = {
    "bp_systolic":  ("5085AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", 154, 170),
    "weight":       ("5089AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", 57.0, 67.0),
    "pulse":        ("5087AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", 64, 80),
    "temperature":  ("5088AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", 36.5, 37.1),
}
for vital_key, (concept_uuid, low, high) in VITAL_CONCEPTS.items():
    try:
        obs_data = api_get(f"/obs?patient={PATIENT_UUID}&concept={concept_uuid}&limit=10&v=default")
        for obs in obs_data.get("results", []):
            obs_dt_str = obs.get("obsDatetime", "") or ""
            val = obs.get("value")
            if val is None:
                continue
            try:
                val = float(val) if not isinstance(val, dict) else float(val.get("display", 0))
            except Exception:
                continue
            try:
                clean = re.sub(r'\.\d{3}', '', obs_dt_str.replace("+0000", "+00:00"))
                dt = datetime.fromisoformat(clean)
                obs_ts = dt.timestamp()
            except Exception:
                obs_ts = 0
            if obs_ts >= TASK_START and low <= val <= high:
                result["vitals_details"][vital_key] = True
                break
    except Exception:
        pass
result["vitals_recorded"] = all(result["vitals_details"].values())

# --- Check 2: Migraine condition ---
try:
    conditions = api_get(f"/condition?patient={PATIENT_UUID}&v=default")
    for cond in conditions.get("results", []):
        cond_name = ""
        concept = cond.get("condition", {})
        if isinstance(concept, dict):
            cond_name = (concept.get("display", "") or "").lower()
        if not cond_name:
            cond_name = str(cond.get("conditionNonCoded", "") or "").lower()
        if any(k in cond_name for k in ("migraine", "headache")):
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
                result["migraine_condition_added"] = True
except Exception:
    pass

# --- Check 3: Acetaminophen medication order ---
try:
    orders = api_get(f"/order?patient={PATIENT_UUID}&v=default&limit=100")
    current_count = len(orders.get("results", []))
    for order in orders.get("results", []):
        drug = (order.get("drug", {}) or {})
        drug_name = (drug.get("display", "") or "").lower()
        concept_name = ((order.get("concept", {}) or {}).get("display", "") or "").lower()
        full_name = drug_name + " " + concept_name
        if any(k in full_name for k in ("acetaminophen", "paracetamol", "tylenol")):
            # Check if this order was placed after task start
            date_activated = order.get("dateActivated") or order.get("scheduledDate") or ""
            try:
                clean = re.sub(r'\.\d{3}', '', str(date_activated).replace("+0000", "+00:00"))
                dt = datetime.fromisoformat(clean)
                order_ts = dt.timestamp()
            except Exception:
                order_ts = TASK_START + 1
            if order_ts >= TASK_START:
                result["acetaminophen_ordered"] = True
                break
    # Also accept if total order count increased
    if not result["acetaminophen_ordered"] and current_count > INITIAL_ORDER_COUNT:
        # Check the newest orders for acetaminophen
        for order in orders.get("results", []):
            drug = (order.get("drug", {}) or {})
            drug_name = (drug.get("display", "") or "").lower()
            concept_name = ((order.get("concept", {}) or {}).get("display", "") or "").lower()
            full_name = drug_name + " " + concept_name
            if any(k in full_name for k in ("acetaminophen", "paracetamol", "tylenol")):
                result["acetaminophen_ordered"] = True
                break
except Exception:
    pass

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
cat /tmp/geriatric_multimorbidity_assessment_result.json
