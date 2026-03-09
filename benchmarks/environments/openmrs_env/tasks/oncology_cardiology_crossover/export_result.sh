#!/bin/bash
# Export: oncology_cardiology_crossover task

echo "=== Exporting oncology_cardiology_crossover result ==="
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/oncology_cardiology_crossover_start_ts 2>/dev/null || echo "0")
PATIENT_UUID=$(cat /tmp/oncology_cardiology_crossover_patient_uuid 2>/dev/null || echo "")
INITIAL_APPT_COUNT=$(cat /tmp/oncology_cardiology_crossover_initial_appt_count 2>/dev/null || echo "0")

if [ -z "$PATIENT_UUID" ]; then
    PATIENT_UUID=$(get_patient_uuid "Mateo Matias")
fi

DISPLAY=:1 import -window root /tmp/oncology_cardiology_crossover_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/oncology_cardiology_crossover_end_screenshot.png 2>/dev/null || true

export EXPORT_PATIENT_UUID="$PATIENT_UUID"
export EXPORT_TASK_START="$TASK_START"
export EXPORT_INITIAL_APPT_COUNT="$INITIAL_APPT_COUNT"

python3 - << 'PYEOF' > /tmp/oncology_cardiology_crossover_result.json
import os, json, urllib.request, base64, re
from datetime import datetime

BASE_URL = "http://localhost/openmrs/ws/rest/v1"
AUTH = base64.b64encode(b"admin:Admin123").decode()
PATIENT_UUID = os.environ.get('EXPORT_PATIENT_UUID', '')
TASK_START = int(os.environ.get('EXPORT_TASK_START', '0'))
INITIAL_APPT_COUNT = int(os.environ.get('EXPORT_INITIAL_APPT_COUNT', '0'))
APPT_WINDOW_DAYS = 28

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
    "contrast_allergy_added": False,
    "allergy_severity_moderate": False,
    "allergy_reaction_urticaria": False,
    "vitals_recorded": False,
    "vitals_details": {
        "bp_systolic": False,
        "weight": False,
        "pulse": False,
        "temperature": False
    },
    "appointment_added": False
}

# --- Check 1: Iodinated contrast allergy ---
try:
    allergies = api_get(f"/allergy?patient={PATIENT_UUID}&v=default")
    for a in allergies.get("results", []):
        allergen = a.get("allergen", {})
        coded_name = ((allergen.get("codedAllergen", {}) or {}).get("display", "") or "").lower()
        noncoded_name = (allergen.get("nonCodedAllergen", "") or "").lower()
        full_name = coded_name + " " + noncoded_name
        if "contrast" in full_name or "iodine" in full_name or "iodinated" in full_name:
            result["contrast_allergy_added"] = True
            severity_display = ((a.get("severity", {}) or {}).get("display", "") or "").lower()
            if "moderate" in severity_display:
                result["allergy_severity_moderate"] = True
            for rx in (a.get("reactions", []) or []):
                rx_name = ((rx.get("reaction", {}) or {}).get("display", "") or "").lower()
                if "urticaria" in rx_name or "hive" in rx_name or "rash" in rx_name or "wheals" in rx_name:
                    result["allergy_reaction_urticaria"] = True
except Exception:
    pass

# --- Check 2: Vitals ---
VITAL_CONCEPTS = {
    "bp_systolic":  ("5085AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", 120, 136),
    "weight":       ("5089AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", 67.0, 77.0),
    "pulse":        ("5087AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", 58, 74),
    "temperature":  ("5088AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", 36.9, 37.5),
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
cat /tmp/oncology_cardiology_crossover_result.json
