#!/bin/bash
# Export: metabolic_syndrome_complication task

echo "=== Exporting metabolic_syndrome_complication result ==="
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/metabolic_syndrome_complication_start_ts 2>/dev/null || echo "0")
PATIENT_UUID=$(cat /tmp/metabolic_syndrome_complication_patient_uuid 2>/dev/null || echo "")
INITIAL_APPT_COUNT=$(cat /tmp/metabolic_syndrome_complication_initial_appt_count 2>/dev/null || echo "0")

if [ -z "$PATIENT_UUID" ]; then
    PATIENT_UUID=$(get_patient_uuid "Yolando Flatley")
fi

DISPLAY=:1 import -window root /tmp/metabolic_syndrome_complication_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/metabolic_syndrome_complication_end_screenshot.png 2>/dev/null || true

export EXPORT_PATIENT_UUID="$PATIENT_UUID"
export EXPORT_TASK_START="$TASK_START"
export EXPORT_INITIAL_APPT_COUNT="$INITIAL_APPT_COUNT"

python3 - << 'PYEOF' > /tmp/metabolic_syndrome_complication_result.json
import os, json, urllib.request, base64, re
from datetime import datetime

BASE_URL = "http://localhost/openmrs/ws/rest/v1"
AUTH = base64.b64encode(b"admin:Admin123").decode()
PATIENT_UUID = os.environ.get('EXPORT_PATIENT_UUID', '')
TASK_START = int(os.environ.get('EXPORT_TASK_START', '0'))
INITIAL_APPT_COUNT = int(os.environ.get('EXPORT_INITIAL_APPT_COUNT', '0'))
APPT_WINDOW_DAYS = 21

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
    "obesity_condition_added": False,
    "appointment_added": False
}

# --- Check 1: Vitals ---
VITAL_CONCEPTS = {
    "bp_systolic":  ("5085AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", 150, 166),
    "weight":       ("5089AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", 97.0, 107.0),
    "pulse":        ("5087AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", 70, 86),
    "temperature":  ("5088AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", 36.7, 37.3),
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

# --- Check 2: Obesity condition ---
try:
    conditions = api_get(f"/condition?patient={PATIENT_UUID}&v=default")
    for cond in conditions.get("results", []):
        cond_name = ""
        concept = cond.get("condition", {})
        if isinstance(concept, dict):
            cond_name = (concept.get("display", "") or "").lower()
        if not cond_name:
            cond_name = str(cond.get("conditionNonCoded", "") or "").lower()
        if any(k in cond_name for k in ("obes", "overweight", "bmi")):
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
                result["obesity_condition_added"] = True
except Exception:
    pass

# --- Check 3: New appointment ---
try:
    appts_data = api_get(f"/appointment?patientUuid={PATIENT_UUID}&v=default")
    appt_list = appts_data if isinstance(appts_data, list) else appts_data.get("results", [])
    current_count = len(appt_list)
    if current_count > INITIAL_APPT_COUNT:
        result["appointment_added"] = True
    else:
        window_end = TASK_START + (APPT_WINDOW_DAYS * 86400)
        for appt in appt_list:
            start_dt = appt.get("startDateTime") or appt.get("startDate") or ""
            if isinstance(start_dt, (int, float)):
                appt_ts = float(start_dt) / 1000.0
            else:
                try:
                    clean = re.sub(r'\.\d{3}', '', str(start_dt).replace("+0000", "+00:00"))
                    dt = datetime.fromisoformat(clean)
                    appt_ts = dt.timestamp()
                except Exception:
                    continue
            if TASK_START <= appt_ts <= window_end:
                result["appointment_added"] = True
                break
except Exception:
    pass

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
cat /tmp/metabolic_syndrome_complication_result.json
