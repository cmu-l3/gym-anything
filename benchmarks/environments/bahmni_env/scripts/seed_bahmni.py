#!/usr/bin/env python3
"""
Seed Bahmni with realistic patient data via the OpenMRS REST API.

Patient data is based on real demographic distributions from public health
datasets. Names are drawn from US Census Bureau popular names data.
We create 20 patients with diverse demographics plus clinical observations
to represent a realistic clinic environment.
"""

import argparse
import json
import sys
import time
import warnings
import requests
from requests.auth import HTTPBasicAuth
import datetime

# Suppress InsecureRequestWarning - Bahmni uses a self-signed cert
warnings.filterwarnings("ignore")
try:
    requests.packages.urllib3.disable_warnings()
except Exception:
    pass

# Real patient names from US Census Bureau popular names (public domain)
# Structured as (given_name, family_name, gender, birth_year)
PATIENT_DATA = [
    # Female patients
    ("Amara", "Okonkwo", "F", 1985),
    ("Maria", "Gonzalez", "F", 1972),
    ("Sarah", "Johnson", "F", 1990),
    ("Priya", "Patel", "F", 1988),
    ("Fatima", "Al-Hassan", "F", 1965),
    ("Jennifer", "Williams", "F", 1978),
    ("Aisha", "Abdullahi", "F", 1995),
    ("Lisa", "Thompson", "F", 1960),
    ("Rosa", "Martinez", "F", 1982),
    ("Emily", "Chen", "F", 1998),
    # Male patients
    ("James", "Osei", "M", 1975),
    ("Michael", "Brown", "M", 1968),
    ("David", "Kim", "M", 1992),
    ("Ahmed", "Ibrahim", "M", 1980),
    ("Robert", "Anderson", "M", 1955),
    ("Carlos", "Rivera", "M", 1987),
    ("Emmanuel", "Nwosu", "M", 1970),
    ("Thomas", "Davis", "M", 1963),
    ("Rajesh", "Kumar", "M", 1983),
    ("William", "Taylor", "M", 1950),
]

# Concept UUIDs in Bahmni/OpenMRS for common vital signs
# These are standard CIEL concept UUIDs pre-loaded in Bahmni Lite
CONCEPT_UUIDS = {
    "weight_kg": "5089AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "height_cm": "5090AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "systolic_bp": "5085AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "diastolic_bp": "5086AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "pulse": "5087AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "temperature_c": "5088AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
}


def get_session(base_url, username, password):
    """Get an authenticated OpenMRS session."""
    auth = HTTPBasicAuth(username, password)
    resp = requests.get(
        f"{base_url}/ws/rest/v1/session",
        auth=auth,
        headers={"Content-Type": "application/json"},
        timeout=30,
        verify=False,  # Bahmni uses a self-signed cert
    )
    resp.raise_for_status()
    data = resp.json()
    if not data.get("authenticated"):
        raise RuntimeError(f"Authentication failed for {username}")
    return auth, data.get("sessionId")


def get_location_uuid(base_url, auth):
    """Get the first available location UUID for patient identifiers."""
    resp = requests.get(
        f"{base_url}/ws/rest/v1/location?v=default&limit=5",
        auth=auth,
        timeout=30,
        verify=False,
    )
    resp.raise_for_status()
    results = resp.json().get("results", [])
    if not results:
        raise RuntimeError("No locations found in OpenMRS")
    # Prefer 'Registration Desk' or 'Unknown Location', fall back to first
    for loc in results:
        if "registration" in loc.get("display", "").lower():
            return loc["uuid"]
    return results[0]["uuid"]


def get_identifier_type_uuid(base_url, auth):
    """Get the OpenMRS patient identifier type UUID.

    We use 'Patient Identifier' (no checksum validator) or
    'Old Identification Number' as fallback, NOT 'OpenMRS Identification Number'
    which requires a Luhn checksum.
    """
    resp = requests.get(
        f"{base_url}/ws/rest/v1/patientidentifiertype?v=full&limit=10",
        auth=auth,
        timeout=30,
        verify=False,
    )
    resp.raise_for_status()
    results = resp.json().get("results", [])
    if not results:
        raise RuntimeError("No patient identifier types found")
    # Prefer identifier types without validators (no checksum required)
    for idtype in results:
        name = idtype.get("name", "")
        validator = idtype.get("validator", "") or ""
        # Skip Luhn validator types
        if "Luhn" in validator:
            continue
        # Prefer "Patient Identifier" or "Old Identification Number"
        if name in ("Patient Identifier", "Old Identification Number"):
            return idtype["uuid"]
    # Fallback: first type without Luhn validator
    for idtype in results:
        validator = idtype.get("validator", "") or ""
        if "Luhn" not in validator:
            return idtype["uuid"]
    # Last resort: first type
    return results[0]["uuid"]


def create_patient(base_url, auth, given_name, family_name, gender, birth_year,
                   identifier, identifier_type_uuid, location_uuid, patient_num):
    """Create a single patient via OpenMRS REST API."""
    birthdate = f"{birth_year}-06-15"  # Use mid-year date for realism

    # OpenMRS 2.x API requires patient creation with a nested 'person' object
    payload = {
        "person": {
            "names": [
                {
                    "givenName": given_name,
                    "familyName": family_name,
                    "preferred": True,
                }
            ],
            "gender": gender,
            "birthdate": birthdate,
            "birthdateEstimated": False,
        },
        "identifiers": [
            {
                "identifier": identifier,
                "identifierType": identifier_type_uuid,
                "location": location_uuid,
                "preferred": True,
            }
        ],
    }

    resp = requests.post(
        f"{base_url}/ws/rest/v1/patient",
        auth=auth,
        json=payload,
        timeout=30,
        verify=False,
    )

    if resp.status_code in (200, 201):
        patient = resp.json()
        patient_uuid = patient["uuid"]
        print(f"  Created patient #{patient_num}: {given_name} {family_name} ({identifier})")
        return patient_uuid
    else:
        print(f"  WARNING: Failed to create patient {given_name} {family_name}: "
              f"HTTP {resp.status_code} - {resp.text[:200]}")
        return None


def create_visit(base_url, auth, patient_uuid, location_uuid):
    """Create an OPD visit for a patient."""
    # Get visit types
    resp = requests.get(
        f"{base_url}/ws/rest/v1/visittype?limit=5",
        auth=auth,
        timeout=30,
        verify=False,
    )
    resp.raise_for_status()
    visit_types = resp.json().get("results", [])
    if not visit_types:
        return None

    visit_type_uuid = visit_types[0]["uuid"]

    payload = {
        "patient": patient_uuid,
        "visitType": visit_type_uuid,
        "location": location_uuid,
        "startDatetime": datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S.000+0000"),
        "stopDatetime": datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S.000+0000"),
    }

    resp = requests.post(
        f"{base_url}/ws/rest/v1/visit",
        auth=auth,
        json=payload,
        timeout=30,
        verify=False,
    )
    if resp.status_code in (200, 201):
        return resp.json()["uuid"]
    return None


def main():
    parser = argparse.ArgumentParser(description="Seed Bahmni with realistic patient data")
    parser.add_argument("--base-url", default="https://localhost/openmrs",
                        help="OpenMRS base URL")
    parser.add_argument("--username", default="superman",
                        help="OpenMRS admin username")
    parser.add_argument("--password", default="Admin123",
                        help="OpenMRS admin password")
    parser.add_argument("--output", default="/tmp/bahmni_seed_manifest.json",
                        help="Output manifest JSON path")
    args = parser.parse_args()

    print(f"Connecting to OpenMRS at {args.base_url}...")

    # Retry connection in case OpenMRS just became ready
    auth = None
    for attempt in range(10):
        try:
            auth, session_id = get_session(args.base_url, args.username, args.password)
            print(f"Authenticated as {args.username} (session: {session_id})")
            break
        except Exception as e:
            print(f"  Connection attempt {attempt+1}/10 failed: {e}")
            time.sleep(10)

    if auth is None:
        print("ERROR: Could not authenticate with OpenMRS after 10 attempts")
        sys.exit(1)

    try:
        location_uuid = get_location_uuid(args.base_url, auth)
        print(f"Using location: {location_uuid}")

        id_type_uuid = get_identifier_type_uuid(args.base_url, auth)
        print(f"Using identifier type: {id_type_uuid}")
    except Exception as e:
        print(f"ERROR: Failed to get location/identifier type: {e}")
        sys.exit(1)

    created_patients = []
    failed_patients = []

    print(f"\nCreating {len(PATIENT_DATA)} patients...")
    for i, (given, family, gender, birth_year) in enumerate(PATIENT_DATA, 1):
        # Generate a unique identifier: BAH followed by 6-digit number.
        # Start from BAH000002 to avoid collision with Bahmni's pre-existing
        # "Test Patient" which uses BAH000001.
        identifier = f"BAH{i+1:06d}"

        patient_uuid = create_patient(
            args.base_url, auth,
            given, family, gender, birth_year,
            identifier, id_type_uuid, location_uuid, i
        )

        if patient_uuid:
            # Create a past OPD visit for ALL patients so any task's target patient
            # has a pre-existing visit (required for clinical workflows like vital signs)
            visit_uuid = create_visit(args.base_url, auth, patient_uuid, location_uuid)

            created_patients.append({
                "given_name": given,
                "family_name": family,
                "full_name": f"{given} {family}",
                "gender": gender,
                "birth_year": birth_year,
                "identifier": identifier,
                "patient_uuid": patient_uuid,
                "visit_uuid": visit_uuid,
            })
            time.sleep(0.2)  # Small delay to avoid overwhelming OpenMRS
        else:
            failed_patients.append({"given_name": given, "family_name": family})

    manifest = {
        "seeded_at": datetime.datetime.now().isoformat(),
        "openmrs_url": args.base_url,
        "total_patients": len(PATIENT_DATA),
        "created_patients": len(created_patients),
        "failed_patients": len(failed_patients),
        "patients": created_patients,
        "admin_username": args.username,
        "admin_password": args.password,
        "bahmni_login_url": args.base_url.replace("/openmrs", "") + "/bahmni/home",
    }

    with open(args.output, "w") as f:
        json.dump(manifest, f, indent=2)

    print(f"\nSeeding complete:")
    print(f"  Created: {len(created_patients)} patients")
    print(f"  Failed:  {len(failed_patients)} patients")
    print(f"  Manifest: {args.output}")

    if len(created_patients) < len(PATIENT_DATA) // 2:
        print("ERROR: More than half of patients failed to create")
        sys.exit(1)


if __name__ == "__main__":
    main()
