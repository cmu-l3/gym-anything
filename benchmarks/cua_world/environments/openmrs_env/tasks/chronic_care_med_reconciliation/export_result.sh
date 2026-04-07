#!/bin/bash
# Export: chronic_care_med_reconciliation task
# Collects all verification data via REST API and DB queries.

echo "=== Exporting chronic_care_med_reconciliation result ==="
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/chronic_care_med_reconciliation_start_ts 2>/dev/null || echo "0")
PATIENT_UUID=$(cat /tmp/chronic_care_med_reconciliation_patient_uuid 2>/dev/null || echo "")
INITIAL_ORDER_COUNT=$(cat /tmp/chronic_care_med_reconciliation_initial_order_count.txt 2>/dev/null || echo "0")
INITIAL_APPT_COUNT=$(cat /tmp/chronic_care_med_reconciliation_initial_appt_count.txt 2>/dev/null || echo "0")

if [ -z "$PATIENT_UUID" ]; then
    PATIENT_UUID=$(get_patient_uuid "Elena Vasquez")
    [ -z "$PATIENT_UUID" ] && PATIENT_UUID=$(get_patient_uuid "Elena Vasques")
fi

# Final screenshot
take_screenshot /tmp/chronic_care_med_reconciliation_end_screenshot.png

# Pass context to Python via environment
export EXPORT_PATIENT_UUID="$PATIENT_UUID"
export EXPORT_TASK_START="$TASK_START"
export EXPORT_INITIAL_ORDER_COUNT="$INITIAL_ORDER_COUNT"
export EXPORT_INITIAL_APPT_COUNT="$INITIAL_APPT_COUNT"

python3 - << 'PYEOF' > /tmp/chronic_care_med_reconciliation_result.json
import os, json, urllib.request, base64, re
from datetime import datetime, timedelta, timezone

BASE_URL = "http://localhost/openmrs/ws/rest/v1"
AUTH = base64.b64encode(b"admin:Admin123").decode()
PATIENT_UUID = os.environ.get("EXPORT_PATIENT_UUID", "")
TASK_START = int(os.environ.get("EXPORT_TASK_START", "0"))
INITIAL_ORDER_COUNT = int(os.environ.get("EXPORT_INITIAL_ORDER_COUNT", "0"))
INITIAL_APPT_COUNT = int(os.environ.get("EXPORT_INITIAL_APPT_COUNT", "0"))

def api_get(path):
    req = urllib.request.Request(
        f"{BASE_URL}{path}",
        headers={"Authorization": f"Basic {AUTH}", "Accept": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return json.loads(r.read())
    except Exception:
        return {}

def parse_ts(date_str):
    """Parse an OpenMRS datetime string to epoch seconds."""
    try:
        clean = re.sub(r"\.\d{3}", "", str(date_str).replace("+0000", "+00:00"))
        dt = datetime.fromisoformat(clean)
        return dt.timestamp()
    except Exception:
        return 0

result = {
    "task_start": TASK_START,
    "patient_uuid": PATIENT_UUID,
    # Demographics
    "family_name": "",
    "address1": "",
    "city": "",
    "state": "",
    "postal_code": "",
    "country": "",
    # Visit
    "active_visit_exists": False,
    # Allergy
    "morphine_allergy_added": False,
    "morphine_allergy_severity_severe": False,
    "morphine_allergy_reaction_anaphylaxis": False,
    # Vitals
    "vitals": {},
    # Medications
    "codeine_discontinued": False,
    "acetaminophen_prescribed": False,
    # Lab orders
    "hba1c_ordered": False,
    "creatinine_ordered": False,
    # Appointment
    "appointment_scheduled_within_14_days": False,
}

if not PATIENT_UUID:
    print(json.dumps(result, indent=2))
    exit()

# ── 1. Demographics (name + address) ────────────────────────────────────────
try:
    patient = api_get(f"/patient/{PATIENT_UUID}?v=full")
    person = patient.get("person", {})
    preferred_name = person.get("preferredName", {})
    result["family_name"] = preferred_name.get("familyName", "")

    preferred_addr = person.get("preferredAddress", {}) or {}
    result["address1"] = preferred_addr.get("address1", "")
    result["city"] = preferred_addr.get("cityVillage", "")
    result["state"] = preferred_addr.get("stateProvince", "")
    result["postal_code"] = preferred_addr.get("postalCode", "")
    result["country"] = preferred_addr.get("country", "")
except Exception:
    pass

# ── 2. Active visit ─────────────────────────────────────────────────────────
try:
    visits = api_get(f"/visit?patient={PATIENT_UUID}&includeInactive=false&v=default")
    for v in visits.get("results", []):
        if not v.get("stopDatetime"):
            result["active_visit_exists"] = True
            break
except Exception:
    pass

# ── 3. Morphine allergy ─────────────────────────────────────────────────────
try:
    allergy_data = api_get(f"/patient/{PATIENT_UUID}/allergy")
    allergy_list = allergy_data if isinstance(allergy_data, list) else allergy_data.get("results", allergy_data.get("data", []))
    if not isinstance(allergy_list, list):
        allergy_list = []

    for a in allergy_list:
        allergen = a.get("allergen", {})
        coded = ((allergen.get("codedAllergen", {}) or {}).get("display", "") or "").lower()
        noncoded = (allergen.get("nonCodedAllergen", "") or "").lower()
        full_name = coded + " " + noncoded
        if "morphine" in full_name:
            result["morphine_allergy_added"] = True
            sev = ((a.get("severity", {}) or {}).get("display", "") or "").lower()
            if "severe" in sev:
                result["morphine_allergy_severity_severe"] = True
            for rx in a.get("reactions", []) or []:
                rx_name = ((rx.get("reaction", {}) or {}).get("display", "") or "").lower()
                if "anaphyla" in rx_name:
                    result["morphine_allergy_reaction_anaphylaxis"] = True
except Exception:
    pass

# ── 4. Vitals ────────────────────────────────────────────────────────────────
# CIEL concept UUIDs for vital signs
VITALS_MAP = {
    "systolic_bp":  "5085AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "diastolic_bp": "5086AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "pulse":        "5087AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "temperature":  "5088AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "weight":       "5089AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "height":       "5090AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
}
# SpO2 concept — CIEL 5092
SPO2_CONCEPT = "5092AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
VITALS_ENC_TYPE = "67a71486-1a54-468f-ac3e-7091a9a79584"

try:
    encounters = api_get(
        f"/encounter?patient={PATIENT_UUID}&encounterType={VITALS_ENC_TYPE}&v=full&limit=5"
    )
    # Find the most recent vitals encounter created after task start
    best_enc = None
    best_ts = 0
    for enc in encounters.get("results", []):
        enc_ts = parse_ts(enc.get("encounterDatetime", ""))
        if enc_ts >= TASK_START and enc_ts > best_ts:
            best_enc = enc
            best_ts = enc_ts
    # Fallback: just take the most recent
    if not best_enc and encounters.get("results"):
        best_enc = encounters["results"][0]

    if best_enc:
        for obs in best_enc.get("obs", []):
            concept_uuid = (obs.get("concept", {}) or {}).get("uuid", "")
            value = obs.get("value")
            if isinstance(value, dict):
                value = value.get("display", value.get("uuid", ""))
            for vital_name, vital_uuid in VITALS_MAP.items():
                if concept_uuid == vital_uuid:
                    try:
                        result["vitals"][vital_name] = float(value)
                    except (ValueError, TypeError):
                        result["vitals"][vital_name] = str(value)
            if concept_uuid == SPO2_CONCEPT:
                try:
                    result["vitals"]["spo2"] = float(value)
                except (ValueError, TypeError):
                    result["vitals"]["spo2"] = str(value)
except Exception:
    pass

# ── 5. Medication orders (Codeine discontinued, Acetaminophen prescribed) ────
try:
    orders = api_get(f"/order?patient={PATIENT_UUID}&v=full&limit=100")
    for order in orders.get("results", []):
        order_type = (order.get("type", "") or "").lower()
        if "drug" not in order_type:
            continue

        concept_name = ((order.get("concept", {}) or {}).get("display", "") or "").lower()
        drug_name = ((order.get("drug", {}) or {}).get("display", "") or "").lower()
        full_name = concept_name + " " + drug_name
        action = (order.get("action", "") or "").upper()

        # Check for Codeine discontinuation
        if "codeine" in full_name:
            # A DISCONTINUE action means agent created a discontinuation order
            if action == "DISCONTINUE":
                disc_ts = parse_ts(order.get("dateActivated", ""))
                if disc_ts >= TASK_START:
                    result["codeine_discontinued"] = True
            # Also check if the original order's dateStopped is set
            if order.get("dateStopped"):
                result["codeine_discontinued"] = True

        # Check for Acetaminophen/Paracetamol prescription
        if any(kw in full_name for kw in ("acetaminophen", "paracetamol", "tylenol")):
            if action in ("NEW", "RENEW", "REVISE"):
                order_ts = parse_ts(order.get("dateActivated", ""))
                if order_ts >= TASK_START:
                    result["acetaminophen_prescribed"] = True
except Exception:
    pass

# ── 6. Lab orders (HbA1c + Creatinine) ──────────────────────────────────────
try:
    orders = api_get(f"/order?patient={PATIENT_UUID}&v=full&limit=100")
    for order in orders.get("results", []):
        order_type = (order.get("type", "") or "").lower()
        if "test" not in order_type and "drug" in order_type:
            continue

        concept_name = ((order.get("concept", {}) or {}).get("display", "") or "").lower()
        action = (order.get("action", "") or "").upper()
        order_ts = parse_ts(order.get("dateActivated", ""))

        if order_ts >= TASK_START or (order_ts == 0 and action in ("NEW", "")):
            # HbA1c
            if any(kw in concept_name for kw in ("hba1c", "hemoglobin a1c", "glycated", "glycosylated", "a1c")):
                result["hba1c_ordered"] = True

            # Creatinine
            if "creatinine" in concept_name:
                result["creatinine_ordered"] = True
except Exception:
    pass

# ── 7. Appointment within 14 days ───────────────────────────────────────────
try:
    appt_data = api_get(f"/appointment?patientUuid={PATIENT_UUID}")
    appt_list = appt_data if isinstance(appt_data, list) else appt_data.get("results", appt_data.get("data", []))
    if not isinstance(appt_list, list):
        appt_list = []

    now = datetime.now(timezone.utc)
    cutoff = now + timedelta(days=14)

    for appt in appt_list:
        start_str = appt.get("startDateTime", "") or appt.get("timeSlot", {}).get("startDate", "") or ""
        if start_str:
            appt_ts = parse_ts(start_str)
            if appt_ts > 0:
                appt_dt = datetime.fromtimestamp(appt_ts, tz=timezone.utc)
                if now <= appt_dt <= cutoff:
                    result["appointment_scheduled_within_14_days"] = True
                    break

    # Fallback: check if any NEW appointment exists after task start
    if not result["appointment_scheduled_within_14_days"] and len(appt_list) > INITIAL_APPT_COUNT:
        result["appointment_scheduled_within_14_days"] = True
except Exception:
    pass

print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/chronic_care_med_reconciliation_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/chronic_care_med_reconciliation_result.json
