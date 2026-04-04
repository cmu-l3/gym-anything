#!/bin/bash
# Export: anticoagulation_safety_review task
# Features: allergy + vitals + condition

echo "=== Exporting anticoagulation_safety_review result ==="
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/anticoagulation_safety_review_start_ts 2>/dev/null || echo "0")
PATIENT_UUID=$(cat /tmp/anticoagulation_safety_review_patient_uuid 2>/dev/null || echo "")

if [ -z "$PATIENT_UUID" ]; then
    PATIENT_UUID=$(get_patient_uuid "Rosario Ortiz")
fi

DISPLAY=:1 import -window root /tmp/anticoagulation_safety_review_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/anticoagulation_safety_review_end_screenshot.png 2>/dev/null || true

export EXPORT_PATIENT_UUID="$PATIENT_UUID"
export EXPORT_TASK_START="$TASK_START"

python3 - << 'PYEOF' > /tmp/anticoagulation_safety_review_result.json
import os, json, urllib.request, base64, re
from datetime import datetime

BASE_URL = "http://localhost/openmrs/ws/rest/v1"
AUTH = base64.b64encode(b"admin:Admin123").decode()
PATIENT_UUID = os.environ.get('EXPORT_PATIENT_UUID', '')
TASK_START = int(os.environ.get('EXPORT_TASK_START', '0'))

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
    "aspirin_allergy_added": False,
    "allergy_severity_severe": False,
    "allergy_reaction_anaphylaxis": False,
    "vitals_recorded": False,
    "vitals_details": {
        "bp_systolic": False,
        "weight": False,
        "pulse": False,
        "temperature": False
    },
    "ckd_condition_added": False
}

# --- Check 1: Aspirin allergy ---
try:
    allergies = api_get(f"/allergy?patient={PATIENT_UUID}&v=default")
    for a in allergies.get("results", []):
        allergen = a.get("allergen", {})
        coded_name = ((allergen.get("codedAllergen", {}) or {}).get("display", "") or "").lower()
        noncoded_name = (allergen.get("nonCodedAllergen", "") or "").lower()
        full_name = coded_name + " " + noncoded_name
        if "aspirin" in full_name or "acetylsalicylic" in full_name:
            result["aspirin_allergy_added"] = True
            severity_display = ((a.get("severity", {}) or {}).get("display", "") or "").lower()
            if "severe" in severity_display:
                result["allergy_severity_severe"] = True
            for rx in (a.get("reactions", []) or []):
                rx_name = ((rx.get("reaction", {}) or {}).get("display", "") or "").lower()
                if "anaphylax" in rx_name or "anaphyl" in rx_name:
                    result["allergy_reaction_anaphylaxis"] = True
except Exception:
    pass

# --- Check 2: Vitals recorded after task start ---
VITAL_CONCEPTS = {
    "bp_systolic":  ("5085AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", 140, 156),
    "weight":       ("5089AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", 82.0, 92.0),
    "pulse":        ("5087AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", 84, 100),
    "temperature":  ("5088AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", 37.1, 37.7),
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

# --- Check 3: CKD condition added after task start ---
try:
    conditions = api_get(f"/condition?patient={PATIENT_UUID}&v=default")
    for cond in conditions.get("results", []):
        cond_name = ""
        concept = cond.get("condition", {})
        if isinstance(concept, dict):
            cond_name = (concept.get("display", "") or "").lower()
        if not cond_name:
            cond_name = str(cond.get("conditionNonCoded", "") or "").lower()
        if any(k in cond_name for k in ("kidney", "renal", "ckd", "chronic kidney", "nephropathy")):
            audit_created = (cond.get("auditInfo", {}) or {}).get("dateCreated", "") or ""
            onset = cond.get("onsetDate", "") or ""
            date_str = audit_created or onset
            try:
                clean = re.sub(r'\.\d{3}', '', date_str.replace("+0000", "+00:00"))
                dt = datetime.fromisoformat(clean)
                cond_ts = dt.timestamp()
            except Exception:
                cond_ts = TASK_START + 1
            if cond_ts >= TASK_START:
                result["ckd_condition_added"] = True
except Exception:
    pass

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
cat /tmp/anticoagulation_safety_review_result.json
