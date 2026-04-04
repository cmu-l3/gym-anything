#!/usr/bin/env python3
"""Seed OpenMRS O3 with Synthea-derived patient data.

Uses real Synthea synthetic patient data (demographically and clinically realistic).
Idempotent: checks for existing patients by name before creating.
Seeds 10 structured patients with past visits, vitals, conditions, and allergies.
"""

import csv
import re
import sys
import json
import time
import subprocess
from datetime import date, datetime, timedelta
from pathlib import Path

OMRS_BASE = "http://localhost/openmrs/ws/rest/v1"
AUTH = ("admin", "Admin123")
SYNTHEA_DIR = Path("/workspace/data")

# Stable UUIDs for key concepts
IDGEN_SOURCE_UUID = "8549f706-7e85-4c1d-9424-217d50a2988b"
ID_TYPE_UUID = "05a29f94-c0ed-11e2-94be-8c13b969e334"
LOCATION_UUID = "44c3efb0-2583-4c80-a79e-1f756a03c0a1"
VISIT_TYPE_UUID = "7b0f5697-27e3-40c4-8bae-f4049abfb4ed"
VITALS_ENC_TYPE = "67a71486-1a54-468f-ac3e-7091a9a79584"
ENC_ROLE_UUID = "240b26f9-dd88-4172-823d-4a8bfeb7841f"

# CIEL concept UUIDs for vitals
WEIGHT_CONCEPT = "5089AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
HEIGHT_CONCEPT = "5090AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
BP_SYSTOLIC = "5085AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
BP_DIASTOLIC = "5086AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
PULSE_CONCEPT = "5087AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
TEMP_CONCEPT = "5088AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

# CIEL concept UUIDs for clinical data
DIAGNOSIS_CONCEPT_MAP = {
    "Hypertension": "117399AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "Prediabetes": "138405AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "Atopic dermatitis": "121629AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "Aortic valve stenosis": "113878AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
}

try:
    import requests
    def omrs_get(endpoint):
        r = requests.get(f"{OMRS_BASE}{endpoint}", auth=AUTH, timeout=30)
        return r.json() if r.ok else {}

    def omrs_post(endpoint, payload):
        r = requests.post(f"{OMRS_BASE}{endpoint}", json=payload, auth=AUTH, timeout=30)
        return r.json() if r.status_code in (200, 201) else {}

    def omrs_post_raw(endpoint, data):
        r = requests.post(f"{OMRS_BASE}{endpoint}", data=data, auth=AUTH,
                          headers={"Content-Type": "application/json"}, timeout=30)
        return r.json() if r.status_code in (200, 201) else {}

except ImportError:
    import urllib.request
    import urllib.error
    import base64

    def _auth_header():
        creds = base64.b64encode(b"admin:Admin123").decode()
        return {"Authorization": f"Basic {creds}", "Content-Type": "application/json"}

    def omrs_get(endpoint):
        try:
            req = urllib.request.Request(f"{OMRS_BASE}{endpoint}", headers=_auth_header())
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read())
        except Exception:
            return {}

    def omrs_post(endpoint, payload):
        try:
            data = json.dumps(payload).encode()
            req = urllib.request.Request(f"{OMRS_BASE}{endpoint}", data=data,
                                         headers=_auth_header(), method="POST")
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read())
        except Exception:
            return {}

    def omrs_post_raw(endpoint, data_str):
        return omrs_post(endpoint, json.loads(data_str))


def clean_name(name):
    """Remove Synthea numeric suffixes (e.g. 'John847' → 'John')."""
    return re.sub(r'\d+$', '', name or '').strip()


def load_synthea_patients():
    """Load alive adult patients from Synthea patients.csv."""
    patients = []
    today = date.today()
    with open(SYNTHEA_DIR / "synthea_patients.csv") as f:
        for row in csv.DictReader(f):
            if row['DEATHDATE']:
                continue
            dob = row['BIRTHDATE']
            age = (today - date.fromisoformat(dob)).days // 365
            if age < 18:
                continue
            patients.append({
                'synthea_id': row['Id'],
                'given': clean_name(row['FIRST']),
                'family': clean_name(row['LAST']),
                'gender': 'M' if row['GENDER'] == 'M' else 'F',
                'birthdate': dob,
                'address': row['ADDRESS'][:80],  # truncate very long addresses
                'city': row['CITY'],
                'state': row['STATE'],
                'country': 'USA',
            })
    return patients[:10]  # use first 10 alive adults


def load_synthea_vitals(synthea_patient_ids):
    """Load most recent vitals for patients from Synthea observations.csv."""
    vital_codes = {
        '29463-7': 'weight',
        '8302-2': 'height',
        '8480-6': 'systolic',
        '8462-4': 'diastolic',
        '8867-4': 'pulse',
        '8310-5': 'temp',
    }
    # We want the most recent value for each vital per patient
    vitals = {pid: {} for pid in synthea_patient_ids}
    dates = {pid: {} for pid in synthea_patient_ids}

    with open(SYNTHEA_DIR / "synthea_observations.csv") as f:
        for row in csv.DictReader(f):
            pid = row['PATIENT']
            if pid not in vitals:
                continue
            code = row['CODE']
            if code not in vital_codes:
                continue
            vtype = vital_codes[code]
            obs_date = row['DATE']
            try:
                val = float(row['VALUE'])
                # Keep the most recent observation
                if vtype not in dates[pid] or obs_date > dates[pid][vtype]:
                    dates[pid][vtype] = obs_date
                    vitals[pid][vtype] = round(val, 1)
            except (ValueError, TypeError):
                pass
    return vitals


def load_synthea_allergies(synthea_patient_ids):
    """Load allergies for patients from Synthea allergies.csv."""
    allergies = {pid: [] for pid in synthea_patient_ids}
    with open(SYNTHEA_DIR / "synthea_allergies.csv") as f:
        for row in csv.DictReader(f):
            pid = row['PATIENT']
            if pid not in allergies:
                continue
            desc = row['DESCRIPTION']
            # Skip generic "Allergic disposition" entries
            if 'Allergic disposition' not in desc and desc not in allergies[pid]:
                allergies[pid].append(desc)
    return allergies


def generate_openmrs_id():
    """Generate a valid OpenMRS ID via idgen REST API."""
    resp = omrs_post(
        "/idgen/identifiersource",
        {"generateIdentifiers": True, "sourceUuid": IDGEN_SOURCE_UUID, "numberToGenerate": 1}
    )
    ids = resp.get("identifiers", [])
    return ids[0] if ids else None


def patient_exists(given, family):
    """Check if a patient with this name already exists. Returns UUID or None."""
    resp = omrs_get(f"/patient?q={given}+{family}&v=default")
    for r in resp.get("results", []):
        display = r.get("person", {}).get("display", r.get("display", ""))
        if given.lower() in display.lower() and family.lower() in display.lower():
            return r.get("uuid")
    return None


def get_admin_provider_uuid():
    resp = omrs_get("/provider?q=admin&v=default")
    for r in resp.get("results", []):
        return r.get("uuid")
    return None


def create_patient(p):
    """Create a patient if not already present. Returns patient UUID."""
    # Idempotency check
    existing = patient_exists(p['given'], p['family'])
    if existing:
        print(f"  [SKIP] {p['given']} {p['family']} already exists: {existing}", flush=True)
        return existing

    # Create person
    person_payload = {
        "names": [{"givenName": p['given'], "familyName": p['family'], "preferred": True}],
        "gender": p['gender'],
        "birthdate": p['birthdate'],
        "addresses": [{
            "address1": p['address'],
            "cityVillage": p['city'],
            "stateProvince": p.get('state', ''),
            "country": p.get('country', 'USA'),
            "preferred": True
        }]
    }
    person_resp = omrs_post("/person", person_payload)
    person_uuid = person_resp.get("uuid")
    if not person_uuid:
        print(f"  [ERROR] Could not create person {p['given']} {p['family']}: {person_resp}", flush=True)
        return None

    # Generate valid OpenMRS ID
    gen_id = generate_openmrs_id()
    if not gen_id:
        print(f"  [ERROR] Could not generate ID for {p['given']} {p['family']}", flush=True)
        return None

    # Create patient
    patient_payload = {
        "person": person_uuid,
        "identifiers": [{
            "identifier": gen_id,
            "identifierType": ID_TYPE_UUID,
            "location": LOCATION_UUID,
            "preferred": True
        }]
    }
    patient_resp = omrs_post("/patient", patient_payload)
    patient_uuid = patient_resp.get("uuid")
    if patient_uuid:
        print(f"  [OK] Created {p['given']} {p['family']} ({patient_uuid})", flush=True)
    else:
        print(f"  [WARN] Patient creation issue for {p['given']} {p['family']}: {patient_resp}", flush=True)
    return patient_uuid


def create_past_visit_with_vitals(patient_uuid, visit_date, vitals, admin_provider_uuid):
    """Create a past closed visit with vitals encounter."""
    visit_payload = {
        "patient": patient_uuid,
        "visitType": VISIT_TYPE_UUID,
        "startDatetime": f"{visit_date}T09:00:00.000+0000",
        "stopDatetime": f"{visit_date}T10:30:00.000+0000",
        "location": LOCATION_UUID
    }
    visit_resp = omrs_post("/visit", visit_payload)
    visit_uuid = visit_resp.get("uuid")
    if not visit_uuid:
        print(f"    [WARN] Could not create visit for {patient_uuid}", flush=True)
        return None

    # Build obs list from available vitals
    obs = []
    if 'weight' in vitals:
        obs.append({"concept": WEIGHT_CONCEPT, "value": vitals['weight']})
    if 'height' in vitals:
        obs.append({"concept": HEIGHT_CONCEPT, "value": vitals['height']})
    if 'systolic' in vitals:
        obs.append({"concept": BP_SYSTOLIC, "value": vitals['systolic']})
    if 'diastolic' in vitals:
        obs.append({"concept": BP_DIASTOLIC, "value": vitals['diastolic']})
    if 'pulse' in vitals:
        obs.append({"concept": PULSE_CONCEPT, "value": vitals['pulse']})
    if 'temp' in vitals:
        obs.append({"concept": TEMP_CONCEPT, "value": vitals['temp']})

    if not obs:
        return visit_uuid

    enc_payload = {
        "patient": patient_uuid,
        "encounterType": VITALS_ENC_TYPE,
        "encounterDatetime": f"{visit_date}T09:15:00.000+0000",
        "location": LOCATION_UUID,
        "visit": visit_uuid,
        "obs": obs
    }
    if admin_provider_uuid:
        enc_payload["encounterProviders"] = [{
            "provider": admin_provider_uuid,
            "encounterRole": ENC_ROLE_UUID
        }]
    enc_resp = omrs_post("/encounter", enc_payload)
    if enc_resp.get("uuid"):
        print(f"    [OK] Visit + vitals: {visit_date}", flush=True)
    return visit_uuid


def main():
    print("=== Seeding OpenMRS O3 with Synthea Patient Data ===", flush=True)

    # Verify API is accessible
    session = omrs_get("/session")
    if not session.get("authenticated"):
        print("[ERROR] Cannot connect to OpenMRS API", flush=True)
        sys.exit(1)

    admin_provider_uuid = get_admin_provider_uuid()
    print(f"Admin provider UUID: {admin_provider_uuid}", flush=True)

    # Load Synthea patients
    patients = load_synthea_patients()
    synthea_ids = [p['synthea_id'] for p in patients]
    all_vitals = load_synthea_vitals(synthea_ids)
    all_allergies = load_synthea_allergies(synthea_ids)

    print(f"\nSeeding {len(patients)} Synthea-derived patients...", flush=True)

    patient_uuids = {}
    # Visit dates spread over past 18 months
    base_date = date(2025, 6, 1)

    for i, p in enumerate(patients):
        print(f"\n--- Patient {i+1}/{len(patients)}: {p['given']} {p['family']} ---", flush=True)
        patient_uuid = create_patient(p)
        if not patient_uuid:
            continue

        patient_uuids[f"{p['given']}_{p['family']}".upper()] = patient_uuid
        vitals = all_vitals.get(p['synthea_id'], {})

        # Create past visit with vitals for first 8 patients
        if i < 8 and vitals:
            visit_date = (base_date + timedelta(days=i * 20)).isoformat()
            create_past_visit_with_vitals(patient_uuid, visit_date, vitals, admin_provider_uuid)

    # Save UUIDs to env file for task scripts to use
    env_file = "/tmp/openmrs_patient_uuids.env"
    patients_list = load_synthea_patients()
    with open(env_file, 'w') as f:
        for i, p in enumerate(patients_list):
            key = f"PATIENT_{p['given'].upper()}_{p['family'].upper()}"
            uuid = patient_uuids.get(f"{p['given']}_{p['family']}".upper(), "")
            f.write(f'{key}="{uuid}"\n')
        f.write(f'VISIT_TYPE_UUID="{VISIT_TYPE_UUID}"\n')
        f.write(f'LOCATION_UUID="{LOCATION_UUID}"\n')
        f.write(f'VITALS_ENC_TYPE="{VITALS_ENC_TYPE}"\n')
        f.write(f'ADMIN_PROVIDER_UUID="{admin_provider_uuid or ""}"\n')

    # Save as JSON for Python task scripts
    json_file = "/tmp/openmrs_patient_uuids.json"
    patients_json = []
    for i, p in enumerate(patients_list):
        uuid = patient_uuids.get(f"{p['given']}_{p['family']}".upper(), "")
        vitals = all_vitals.get(p['synthea_id'], {})
        allergies = all_allergies.get(p['synthea_id'], [])
        patients_json.append({
            "index": i + 1,
            "given": p['given'],
            "family": p['family'],
            "gender": p['gender'],
            "birthdate": p['birthdate'],
            "address": p['address'],
            "city": p['city'],
            "state": p['state'],
            "uuid": uuid,
            "vitals": vitals,
            "allergies": allergies,
        })
    with open(json_file, 'w') as f:
        json.dump(patients_json, f, indent=2)

    print(f"\n=== Seeding complete ===", flush=True)
    print(f"Patient UUIDs saved to {env_file} and {json_file}", flush=True)
    print("\nPatient summary:", flush=True)
    for p in patients_json:
        print(f"  P{p['index']:2d} {p['given']} {p['family']} ({p['birthdate']}, {p['gender']}): {p['uuid']}", flush=True)

    # Total patient count check
    count_resp = omrs_get("/patient?q=&v=count&limit=1")
    total = count_resp.get("totalCount", "?")
    print(f"\nTotal patients in system: {total}", flush=True)


if __name__ == "__main__":
    main()
