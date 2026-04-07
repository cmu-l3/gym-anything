#!/bin/bash
echo "=== Setting up pneumonia_care_correction task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Clean stale outputs from any previous run
rm -f /tmp/task_start.png 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true
rm -f /tmp/pneumonia_care_result.json 2>/dev/null || true
rm -f /tmp/pcc_*.txt 2>/dev/null || true
rm -f /tmp/pcc_*.json 2>/dev/null || true

# 2. Record task start timestamp BEFORE any data creation
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# 3. Wait for Bahmni/OpenMRS to be ready
if ! wait_for_bahmni 900; then
    echo "ERROR: Bahmni API is not reachable."
    exit 1
fi

# 4. Run comprehensive setup via Python
# This creates the patient, seeds clinical data (erroneous weight, drug orders, allergy),
# and records all baselines needed for verification.
cat > /tmp/pcc_setup.py << 'PYEOF'
#!/usr/bin/env python3
"""Setup script for pneumonia_care_correction task.

Creates patient Amina Nyong'o (BAH000030) with:
- Active OPD visit and consultation encounter
- Erroneous weight (185 kg), correct height (163 cm), pulse (102 bpm)
- Penicillin allergy documented
- Active Amoxicillin 500mg drug order (contraindicated)
- Active Paracetamol 1g drug order (correct)
"""

import json
import sys
import time
import requests
from requests.auth import HTTPBasicAuth
from datetime import datetime, timezone

requests.packages.urllib3.disable_warnings()

BASE = "https://localhost/openmrs/ws/rest/v1"
AUTH = HTTPBasicAuth("superman", "Admin123")
HDR = {"Content-Type": "application/json"}
VERIFY = False

PATIENT_ID = "BAH000030"
GIVEN_NAME = "Amina"
FAMILY_NAME = "Nyong'o"


def api_get(endpoint, params=None):
    r = requests.get(f"{BASE}{endpoint}", auth=AUTH, headers=HDR,
                     verify=VERIFY, params=params, timeout=30)
    r.raise_for_status()
    return r.json()


def api_post(endpoint, data):
    r = requests.post(f"{BASE}{endpoint}", auth=AUTH, headers=HDR,
                      json=data, verify=VERIFY, timeout=30)
    if r.status_code not in (200, 201):
        print(f"POST {endpoint} failed ({r.status_code}): {r.text[:500]}")
        r.raise_for_status()
    return r.json()


def api_delete(endpoint):
    r = requests.delete(f"{BASE}{endpoint}", auth=AUTH, headers=HDR,
                        verify=VERIFY, timeout=30)
    return r.status_code


def find_or_create_concept(name, datatype_uuid, concept_class_uuid):
    """Find concept by name or create it."""
    resp = api_get("/concept", params={"q": name, "v": "default"})
    for c in resp.get("results", []):
        if c.get("display", "").lower() == name.lower():
            return c["uuid"]
    # Create it
    payload = {
        "names": [{"name": name, "locale": "en", "conceptNameType": "FULLY_SPECIFIED"}],
        "datatype": datatype_uuid,
        "conceptClass": concept_class_uuid,
    }
    result = api_post("/concept", payload)
    print(f"  Created concept '{name}': {result['uuid']}")
    return result["uuid"]


def find_or_create_drug(drug_name, concept_uuid, strength=""):
    """Find drug by name or create it."""
    # The /drug endpoint may not support query search in all OpenMRS versions.
    # Use a paginated list scan instead.
    try:
        resp = requests.get(f"{BASE}/drug", auth=AUTH, headers=HDR,
                           verify=VERIFY, params={"v": "default", "limit": 100},
                           timeout=30)
        if resp.status_code == 200:
            for d in resp.json().get("results", []):
                if drug_name.lower() in d.get("display", "").lower():
                    return d["uuid"]
    except Exception:
        pass
    # Create it
    payload = {
        "name": drug_name,
        "concept": concept_uuid,
        "combination": False,
    }
    if strength:
        payload["strength"] = strength
    result = api_post("/drug", payload)
    print(f"  Created drug '{drug_name}': {result['uuid']}")
    return result["uuid"]


def main():
    print("--- Step 1: Find or create patient ---")
    resp = api_get("/patient", params={"identifier": PATIENT_ID, "v": "default"})
    patients = resp.get("results", [])

    if patients:
        patient_uuid = patients[0]["uuid"]
        print(f"  Patient {PATIENT_ID} exists: {patient_uuid}")
    else:
        # Create patient
        # Get identifier type UUID
        id_types = api_get("/patientidentifiertype", params={"v": "default"})
        id_type_uuid = id_types["results"][0]["uuid"]

        # Get location UUID
        locations = api_get("/location", params={"tag": "Login Location", "v": "default"})
        if not locations["results"]:
            locations = api_get("/location", params={"v": "default", "limit": 1})
        location_uuid = locations["results"][0]["uuid"]

        patient_payload = {
            "person": {
                "names": [{"givenName": GIVEN_NAME, "familyName": FAMILY_NAME}],
                "gender": "F",
                "birthdate": "1978-08-14",
                "addresses": [{
                    "address1": "45 Uhuru Highway",
                    "cityVillage": "Nairobi",
                    "stateProvince": "Nairobi County",
                    "country": "Kenya",
                    "postalCode": "00100"
                }]
            },
            "identifiers": [{
                "identifier": PATIENT_ID,
                "identifierType": id_type_uuid,
                "location": location_uuid,
                "preferred": True
            }]
        }
        result = api_post("/patient", patient_payload)
        patient_uuid = result["uuid"]
        print(f"  Created patient {PATIENT_ID}: {patient_uuid}")

    # Save patient UUID for later use
    with open("/tmp/pcc_patient_uuid.txt", "w") as f:
        f.write(patient_uuid)
    with open("/tmp/pcc_patient_identifier.txt", "w") as f:
        f.write(PATIENT_ID)

    print("--- Step 1b: Clean up any existing data from prior runs ---")
    # Void all existing encounters for this patient (ensures clean slate)
    existing_encs = api_get("/encounter", params={
        "patient": patient_uuid, "v": "default"
    })
    for enc in existing_encs.get("results", []):
        api_delete(f"/encounter/{enc['uuid']}")
        print(f"  Voided old encounter: {enc['uuid']}")

    # Close/stop any existing active visits
    all_visits = api_get("/visit", params={
        "patient": patient_uuid, "v": "default"
    })
    for v in all_visits.get("results", []):
        if not v.get("stopDatetime"):
            now_str = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000+0000")
            api_post(f"/visit/{v['uuid']}", {"stopDatetime": now_str})
            print(f"  Closed old visit: {v['uuid']}")

    # Clear existing allergies (so we re-seed fresh)
    try:
        r = requests.delete(
            f"{BASE}/patient/{patient_uuid}/allergy",
            auth=AUTH, headers=HDR, verify=VERIFY, timeout=30
        )
        if r.status_code in (200, 204):
            print("  Cleared old allergies")
    except Exception:
        pass

    print("--- Step 2: Create active OPD visit ---")
    # Get visit type (OPD)
    visit_types = api_get("/visittype", params={"v": "default"})
    visit_type_uuid = visit_types["results"][0]["uuid"]

    # Get location
    locations = api_get("/location", params={"tag": "Login Location", "v": "default"})
    if not locations["results"]:
        locations = api_get("/location", params={"v": "default", "limit": 1})
    location_uuid = locations["results"][0]["uuid"]

    now_str = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000+0000")
    visit_payload = {
        "patient": patient_uuid,
        "visitType": visit_type_uuid,
        "location": location_uuid,
        "startDatetime": now_str
    }
    visit = api_post("/visit", visit_payload)
    visit_uuid = visit["uuid"]
    print(f"  Created OPD visit: {visit_uuid}")

    with open("/tmp/pcc_visit_uuid.txt", "w") as f:
        f.write(visit_uuid)

    print("--- Step 3: Create consultation encounter with vitals ---")
    # Get encounter type (use "Consultation")
    enc_types = api_get("/encountertype", params={"v": "default"})
    enc_type_uuid = None
    for et in enc_types.get("results", []):
        if "consultation" in et.get("display", "").lower():
            enc_type_uuid = et["uuid"]
            break
    if not enc_type_uuid:
        enc_type_uuid = enc_types["results"][0]["uuid"]

    # Get provider UUID
    providers = api_get("/provider", params={"v": "default"})
    provider_uuid = providers["results"][0]["uuid"]

    # Create encounter WITHOUT embedded obs (OpenMRS rejects obs without obsDatetime)
    encounter_payload = {
        "patient": patient_uuid,
        "encounterType": enc_type_uuid,
        "visit": visit_uuid,
    }
    encounter = api_post("/encounter", encounter_payload)
    encounter_uuid = encounter["uuid"]
    print(f"  Created encounter: {encounter_uuid}")

    # Add vitals as separate obs with obsDatetime
    # CIEL concept UUIDs
    WEIGHT_UUID = "5089AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    HEIGHT_UUID = "5090AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    PULSE_UUID  = "5087AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

    now_str = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000+0000")

    vitals_to_create = [
        (WEIGHT_UUID, 185, "weight-185kg-ERRONEOUS"),
        (HEIGHT_UUID, 163, "height-163cm"),
        (PULSE_UUID,  102, "pulse-102bpm"),
    ]
    for concept_uuid, value, label in vitals_to_create:
        obs_payload = {
            "person": patient_uuid,
            "concept": concept_uuid,
            "value": value,
            "obsDatetime": now_str,
            "encounter": encounter_uuid
        }
        result = api_post("/obs", obs_payload)
        print(f"  Created obs {label}: {result['uuid']}")

    with open("/tmp/pcc_encounter_uuid.txt", "w") as f:
        f.write(encounter_uuid)

    print("--- Step 4: Ensure drug concepts and drug entries exist ---")
    # Datatype N/A and class Drug
    DT_NA = "8d4a4c94-c2cc-11de-8d13-0010c6dffd0f"
    CC_DRUG = "8d490dfc-c2cc-11de-8d13-0010c6dffd0f"
    CC_MISC = "8d492774-c2cc-11de-8d13-0010c6dffd0f"

    # Try Drug class first, fall back to Misc
    try:
        api_get(f"/conceptclass/{CC_DRUG}")
    except Exception:
        CC_DRUG = CC_MISC

    amoxicillin_concept = find_or_create_concept("Amoxicillin", DT_NA, CC_DRUG)
    paracetamol_concept = find_or_create_concept("Paracetamol", DT_NA, CC_DRUG)
    azithromycin_concept = find_or_create_concept("Azithromycin", DT_NA, CC_DRUG)
    levofloxacin_concept = find_or_create_concept("Levofloxacin", DT_NA, CC_DRUG)

    amox_drug = find_or_create_drug("Amoxicillin 500mg", amoxicillin_concept, "500mg")
    para_drug = find_or_create_drug("Paracetamol 1g", paracetamol_concept, "1g")
    # Create safe alternatives so they exist in the drug list for the agent to find
    find_or_create_drug("Azithromycin 500mg", azithromycin_concept, "500mg")
    find_or_create_drug("Levofloxacin 500mg", levofloxacin_concept, "500mg")

    print("--- Step 5: Create drug orders ---")
    # Get care setting (Outpatient)
    care_settings = api_get("/caresetting")
    care_setting_uuid = None
    for cs in care_settings.get("results", []):
        if "outpatient" in cs.get("display", "").lower():
            care_setting_uuid = cs["uuid"]
            break
    if not care_setting_uuid:
        care_setting_uuid = care_settings["results"][0]["uuid"]

    # Check if orders already exist for this encounter
    existing_orders = api_get("/order", params={
        "patient": patient_uuid, "t": "drugorder", "v": "default"
    })
    has_amox = any("amoxicillin" in o.get("display", "").lower()
                    for o in existing_orders.get("results", []))
    has_para = any("paracetamol" in o.get("display", "").lower()
                    for o in existing_orders.get("results", []))

    # Get quantity units (Tablet concept)
    tablet_concepts = api_get("/concept", params={"q": "Tablet", "v": "default"})
    tablet_uuid = None
    for tc in tablet_concepts.get("results", []):
        if tc.get("display", "").lower() in ("tablet", "tablet(s)"):
            tablet_uuid = tc["uuid"]
            break
    if not tablet_uuid:
        tablet_uuid = tablet_concepts["results"][0]["uuid"]

    def create_drug_order(drug_uuid, concept_uuid, dosing_instructions, qty=21):
        order_payload = {
            "type": "drugorder",
            "patient": patient_uuid,
            "encounter": encounter_uuid,
            "concept": concept_uuid,
            "drug": drug_uuid,
            "careSetting": care_setting_uuid,
            "orderer": provider_uuid,
            "dosingType": "org.openmrs.FreeTextDosingInstructions",
            "dosingInstructions": dosing_instructions,
            "quantity": qty,
            "quantityUnits": tablet_uuid,
            "numRefills": 0,
            "action": "NEW",
            "urgency": "ROUTINE"
        }
        return api_post("/order", order_payload)

    if not has_amox:
        order = create_drug_order(amox_drug, amoxicillin_concept,
                                  "500mg three times daily for 7 days")
        print(f"  Created Amoxicillin order: {order['uuid']}")
        with open("/tmp/pcc_amoxicillin_order_uuid.txt", "w") as f:
            f.write(order["uuid"])
    else:
        print("  Amoxicillin order already exists")

    if not has_para:
        order = create_drug_order(para_drug, paracetamol_concept,
                                  "1g four times daily as needed for fever", qty=28)
        print(f"  Created Paracetamol order: {order['uuid']}")
    else:
        print("  Paracetamol order already exists")

    print("--- Step 6: Document Penicillin allergy ---")
    # Check existing allergies
    allergy_resp = requests.get(
        f"{BASE}/patient/{patient_uuid}/allergy",
        auth=AUTH, headers=HDR, verify=VERIFY, timeout=30
    )
    existing_allergies = allergy_resp.json() if allergy_resp.status_code == 200 else []
    # Handle both list and dict responses
    if isinstance(existing_allergies, dict):
        existing_allergies = existing_allergies.get("results", [])

    has_penicillin_allergy = any(
        "penicillin" in str(a).lower() for a in existing_allergies
    )

    if not has_penicillin_allergy:
        # Use coded allergen with Penicillin concept (CIEL:81724)
        PENICILLIN_CONCEPT = "81724AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        allergy_payload = {
            "allergen": {
                "allergenType": "DRUG",
                "codedAllergen": {"uuid": PENICILLIN_CONCEPT}
            },
            "comment": "Known drug allergy - documented on admission"
        }
        try:
            r = requests.post(
                f"{BASE}/patient/{patient_uuid}/allergy",
                auth=AUTH, headers=HDR, json=allergy_payload,
                verify=VERIFY, timeout=30
            )
            if r.status_code in (200, 201):
                print(f"  Documented Penicillin allergy (coded)")
            else:
                print(f"  WARNING: Could not create allergy ({r.status_code}): {r.text[:300]}")
        except Exception as e:
            print(f"  WARNING: Allergy creation failed: {e}")
    else:
        print("  Penicillin allergy already documented")

    print("--- Step 7: Record baselines ---")
    # Count encounters
    enc_resp = api_get("/encounter", params={"patient": patient_uuid, "v": "default"})
    initial_enc_count = len(enc_resp.get("results", []))

    # Count observations
    obs_resp = api_get("/obs", params={"patient": patient_uuid, "v": "default"})
    initial_obs_count = len(obs_resp.get("results", []))

    # Count drug orders
    order_resp = api_get("/order", params={
        "patient": patient_uuid, "t": "drugorder", "v": "default"
    })
    initial_order_count = len(order_resp.get("results", []))

    # Count allergies
    allergy_resp2 = requests.get(
        f"{BASE}/patient/{patient_uuid}/allergy",
        auth=AUTH, headers=HDR, verify=VERIFY, timeout=30
    )
    allergy_data = allergy_resp2.json() if allergy_resp2.status_code == 200 else []
    if isinstance(allergy_data, dict):
        allergy_data = allergy_data.get("results", [])
    initial_allergy_count = len(allergy_data) if isinstance(allergy_data, list) else 0

    with open("/tmp/pcc_initial_encounter_count.txt", "w") as f:
        f.write(str(initial_enc_count))
    with open("/tmp/pcc_initial_obs_count.txt", "w") as f:
        f.write(str(initial_obs_count))
    with open("/tmp/pcc_initial_order_count.txt", "w") as f:
        f.write(str(initial_order_count))
    with open("/tmp/pcc_initial_allergy_count.txt", "w") as f:
        f.write(str(initial_allergy_count))

    print(f"  Baselines: encounters={initial_enc_count}, obs={initial_obs_count}, "
          f"orders={initial_order_count}, allergies={initial_allergy_count}")

    print("--- Setup complete ---")
    print(f"  Patient: {GIVEN_NAME} {FAMILY_NAME} ({PATIENT_ID})")
    print(f"  UUID: {patient_uuid}")
    print(f"  Visit: {visit_uuid}")
    print(f"  Encounter: {encounter_uuid}")
    print(f"  State: 185kg weight (erroneous), 163cm height, 102 pulse")
    print(f"  Active orders: Amoxicillin 500mg (CONTRAINDICATED), Paracetamol 1g")
    print(f"  Allergy: Penicillin")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"CRITICAL ERROR in setup: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
PYEOF

python3 /tmp/pcc_setup.py
SETUP_EXIT=$?

if [ "$SETUP_EXIT" -ne 0 ]; then
    echo "ERROR: Setup Python script failed with exit code $SETUP_EXIT"
    exit 1
fi

# 5. Verify critical files were created
if [ ! -f /tmp/pcc_patient_uuid.txt ]; then
    echo "ERROR: Patient UUID file not created"
    exit 1
fi

# 6. Launch browser at Bahmni login page
echo "Launching browser..."
if ! restart_firefox "${BAHMNI_LOGIN_URL}" 4; then
    echo "WARNING: Browser may not have started cleanly"
fi

focus_firefox || true
sleep 2

# 7. Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== pneumonia_care_correction task setup complete ==="
echo "Patient: Amina Nyong'o (BAH000030)"
echo "Agent should: correct weight, add missing vitals, discontinue Amoxicillin,"
echo "  prescribe safe antibiotic, add diagnoses, set disposition, schedule follow-up, write note"
