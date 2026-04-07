#!/bin/bash
set -e
echo "=== Setting up correct_patient_relationship task ==="
source /workspace/scripts/task_utils.sh

# 1. Record Start Time
date +%s > /tmp/task_start_time.txt

# 2. Define Patients
CHILD_GIVEN="Bobby"
CHILD_FAMILY="Tables"
PARENT_GIVEN="Martha"
PARENT_FAMILY="Tables"

# 3. Create/Find Patients via REST API
# We use Python for cleaner JSON handling with the API
echo "Ensuring patients exist..."
python3 -c "
import requests, json, sys

auth = ('admin', 'Admin123')
base_url = 'http://localhost/openmrs/ws/rest/v1'
headers = {'Content-Type': 'application/json'}

def create_person(given, family, gender, age_years):
    # Check existing
    r = requests.get(f'{base_url}/person?q={given}&v=default', auth=auth)
    for p in r.json().get('results', []):
        if family in p.get('display', ''):
            return p['uuid']
            
    # Create new
    from datetime import date
    birth_year = date.today().year - age_years
    payload = {
        'names': [{'givenName': given, 'familyName': family}],
        'gender': gender,
        'birthdate': f'{birth_year}-01-01'
    }
    r = requests.post(f'{base_url}/person', json=payload, auth=auth, headers=headers)
    return r.json()['uuid']

def create_patient(person_uuid):
    # Check if already patient
    r = requests.get(f'{base_url}/patient/{person_uuid}', auth=auth)
    if r.status_code == 200:
        return r.json()['uuid']
        
    # Get ID Type and Location (hardcoded from standard RefApp or queried)
    # Using 'OpenMRS ID' and 'Unknown Location' or defaults
    id_gen = requests.post(f'{base_url}/idgen/identifiersource', 
        json={'generateIdentifiers': True, 'sourceUuid': '8549f706-7e85-4c1d-9424-217d50a2988b', 'numberToGenerate': 1}, 
        auth=auth, headers=headers).json()
    ident = id_gen['identifiers'][0]
    
    payload = {
        'person': person_uuid,
        'identifiers': [{
            'identifier': ident,
            'identifierType': '05a29f94-c0ed-11e2-94be-8c13b969e334',
            'location': '44c3efb0-2583-4c80-a79e-1f756a03c0a1',
            'preferred': True
        }]
    }
    r = requests.post(f'{base_url}/patient', json=payload, auth=auth, headers=headers)
    return r.json()['uuid']

# Create Child (Bobby)
p1_uuid = create_person('$CHILD_GIVEN', '$CHILD_FAMILY', 'M', 12)
pat1_uuid = create_patient(p1_uuid)
print(f'CHILD_UUID={pat1_uuid}')
print(f'CHILD_PERSON_UUID={p1_uuid}')

# Create Parent (Martha)
p2_uuid = create_person('$PARENT_GIVEN', '$PARENT_FAMILY', 'F', 40)
pat2_uuid = create_patient(p2_uuid)
print(f'PARENT_UUID={pat2_uuid}')
print(f'PARENT_PERSON_UUID={p2_uuid}')
" > /tmp/patient_setup.txt

# Source the UUIDs
source /tmp/patient_setup.txt

echo "Child: $CHILD_UUID ($CHILD_PERSON_UUID)"
echo "Parent: $PARENT_UUID ($PARENT_PERSON_UUID)"

# Save UUIDs for verifier/exporter
echo "$CHILD_UUID" > /tmp/child_uuid.txt
echo "$PARENT_UUID" > /tmp/parent_uuid.txt
echo "$CHILD_PERSON_UUID" > /tmp/child_person_uuid.txt
echo "$PARENT_PERSON_UUID" > /tmp/parent_person_uuid.txt

# 4. Set up the ERRONEOUS Relationship (Sibling)
# Sibling UUID: 8d91a01c-c2cc-11de-8d13-0010c6dffd0f
# Parent UUID: 8d91a210-c2cc-11de-8d13-0010c6dffd0f

echo "Resetting relationships..."
# Delete any existing relationships between these two
omrs_get "/relationship?person=$CHILD_PERSON_UUID&v=default" | \
python3 -c "
import sys, json, requests
auth = ('admin', 'Admin123')
data = json.load(sys.stdin)
target = '$PARENT_PERSON_UUID'
for r in data.get('results', []):
    # Check if the other person is the parent
    pa = r.get('personA', {}).get('uuid')
    pb = r.get('personB', {}).get('uuid')
    if pa == target or pb == target:
        print(f'Deleting {r[\"uuid\"]}')
        requests.delete(f'http://localhost/openmrs/ws/rest/v1/relationship/{r[\"uuid\"]}', auth=auth)
"

# Create Sibling Relationship
# Person A is Sibling of Person B (Symmetric usually, but A-B direction matters for some types)
echo "Creating erroneous Sibling relationship..."
omrs_post "/relationship" "{
    \"personA\": \"$CHILD_PERSON_UUID\",
    \"personB\": \"$PARENT_PERSON_UUID\",
    \"relationshipType\": \"8d91a01c-c2cc-11de-8d13-0010c6dffd0f\"
}" > /dev/null

# 5. Launch Firefox to the Child's Chart
# URL format: /spa/patient/{uuid}/chart/Relationships (if deep link exists) or just Chart
TARGET_URL="http://localhost/openmrs/spa/patient/${CHILD_UUID}/chart/Patient%20Summary"

echo "Navigating to patient chart..."
ensure_openmrs_logged_in "$TARGET_URL"

# 6. Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="