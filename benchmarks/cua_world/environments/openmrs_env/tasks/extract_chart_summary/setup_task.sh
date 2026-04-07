#!/bin/bash
# Setup script for extract_chart_summary
# Selects a patient with rich data, fetches ground truth, and prepares the environment.

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up extract_chart_summary task ==="

# 1. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Find a suitable patient (must have allergies, conditions, and vitals)
echo "Searching for a suitable patient..."

# Get list of patients
PATIENTS_JSON=$(omrs_get "/patient?v=full&limit=20")

# Helper python script to find a patient with data
# We query details for each until we find a match
SELECTED_PATIENT=$(python3 -c "
import sys, json, requests

auth = ('admin', 'Admin123')
base_url = 'http://localhost/openmrs/ws/rest/v1'

def check_patient(pt):
    uuid = pt['uuid']
    name = pt['person']['display']
    
    # Check Allergies
    r_alg = requests.get(f'{base_url}/allergy', params={'patient': uuid}, auth=auth)
    allergies = r_alg.json().get('results', [])
    if not allergies: return None
    
    # Check Conditions
    r_cond = requests.get(f'{base_url}/condition', params={'patient': uuid, 'v': 'default'}, auth=auth)
    conditions = [c for c in r_cond.json().get('results', []) if c.get('clinicalStatus') == 'ACTIVE']
    if not conditions: return None
    
    # Check Vitals (via Visits -> Encounters -> Obs)
    # This is expensive, so we check this last
    r_visit = requests.get(f'{base_url}/visit', params={'patient': uuid, 'v': 'custom:(encounters:(obs:(concept:(uuid),value,display),encounterDatetime))'}, auth=auth)
    visits = r_visit.json().get('results', [])
    
    recent_vitals = {}
    
    # Concepts (CIEL/Synthea UUIDs)
    SYS_BP = '5085AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    DIA_BP = '5086AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    WEIGHT = '5089AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    HEIGHT = '5090AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    
    found_sys = False
    found_dia = False
    found_wt = False
    found_ht = False

    # Iterate visits to find most recent vitals
    for v in visits:
        for enc in v.get('encounters', []):
            for obs in enc.get('obs', []):
                concept = obs.get('concept', {}).get('uuid')
                if concept == SYS_BP: found_sys = True
                if concept == DIA_BP: found_dia = True
                if concept == WEIGHT: found_wt = True
                if concept == HEIGHT: found_ht = True
    
    if found_sys and found_dia and found_wt and found_ht:
        return {
            'uuid': uuid,
            'name': name,
            'dob': pt['person']['birthdate'][:10], # YYYY-MM-DD
            'raw_allergies': allergies,
            'raw_conditions': conditions,
            'visits': visits
        }
    return None

try:
    data = json.loads('$PATIENTS_JSON')
    results = data.get('results', [])
    for p in results:
        match = check_patient(p)
        if match:
            print(json.dumps(match))
            sys.exit(0)
except Exception as e:
    pass
print('')
")

if [ -z "$SELECTED_PATIENT" ]; then
    echo "ERROR: No suitable patient found with Allergies, Conditions, and Vitals."
    echo "Running seed script to ensure data exists..."
    bash /workspace/scripts/seed_data.sh
    # Retry selection logic (simplified for fallback - picking first patient)
    PATIENT_UUID=$(get_patient_uuid "John") # Fallback
else
    PATIENT_UUID=$(echo "$SELECTED_PATIENT" | jq -r '.uuid')
    PATIENT_NAME=$(echo "$SELECTED_PATIENT" | jq -r '.name')
fi

if [ -z "$PATIENT_UUID" ] || [ "$PATIENT_UUID" == "null" ]; then
    # Emergency fallback if python script failed silently or seed didn't work
    PATIENT_UUID=$(omrs_get "/patient?v=default&limit=1" | jq -r '.results[0].uuid')
    PATIENT_NAME=$(omrs_get "/patient/$PATIENT_UUID" | jq -r '.person.display')
fi

echo "Selected Patient: $PATIENT_NAME ($PATIENT_UUID)"

# 3. Generate Ground Truth JSON
# We extract the specific data points we expect the agent to find.
python3 -c "
import sys, json, requests
from datetime import datetime

auth = ('admin', 'Admin123')
base_url = 'http://localhost/openmrs/ws/rest/v1'
uuid = '$PATIENT_UUID'

# Fetch fresh data to be sure
pt = requests.get(f'{base_url}/patient/{uuid}?v=full', auth=auth).json()
allergies = requests.get(f'{base_url}/allergy', params={'patient': uuid}, auth=auth).json().get('results', [])
conditions = requests.get(f'{base_url}/condition', params={'patient': uuid, 'v': 'default'}, auth=auth).json().get('results', [])
visits = requests.get(f'{base_url}/visit', params={'patient': uuid, 'v': 'custom:(encounters:(encounterDatetime,obs:(concept:(uuid),value,display)))'}, auth=auth).json().get('results', [])

# Process Allergies
parsed_allergies = []
for a in allergies:
    allergen = a.get('allergen', {})
    name = (allergen.get('codedAllergen', {}) or {}).get('display') or allergen.get('nonCodedAllergen')
    
    # Severity
    severity = 'Unknown'
    sev_obj = a.get('severity')
    if sev_obj:
        severity = sev_obj.get('display', 'Unknown')
        
    parsed_allergies.append({'name': name, 'severity': severity})

# Process Conditions
parsed_conditions = []
for c in conditions:
    if c.get('clinicalStatus') == 'ACTIVE':
        # Condition name usually in 'condition.coded.display' or 'condition.nonCoded'
        cond_obj = c.get('condition', {})
        name = (cond_obj.get('coded', {}) or {}).get('display') or cond_obj.get('nonCoded')
        parsed_conditions.append(name)

# Process Vitals (Find most recent for each type)
SYS_BP = '5085AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
DIA_BP = '5086AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
WEIGHT = '5089AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
HEIGHT = '5090AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'

vitals = {}
vitals_dates = {}

def update_vital(k, val, date_str):
    if k not in vitals_dates or date_str > vitals_dates[k]:
        vitals[k] = val
        vitals_dates[k] = date_str

for v in visits:
    for enc in v.get('encounters', []):
        date_str = enc.get('encounterDatetime')
        for obs in enc.get('obs', []):
            concept = obs.get('concept', {}).get('uuid')
            val = obs.get('value')
            if concept == SYS_BP: update_vital('systolic', val, date_str)
            if concept == DIA_BP: update_vital('diastolic', val, date_str)
            if concept == WEIGHT: update_vital('weight', val, date_str)
            if concept == HEIGHT: update_vital('height', val, date_str)

ground_truth = {
    'name_given': pt['person']['preferredName']['givenName'],
    'name_family': pt['person']['preferredName']['familyName'],
    'dob': pt['person']['birthdate'][:10],
    'allergies': parsed_allergies,
    'conditions': parsed_conditions,
    'vitals': vitals
}

with open('/tmp/ground_truth.json', 'w') as f:
    json.dump(ground_truth, f, indent=2)
"

chmod 600 /tmp/ground_truth.json # Restrict access
chown root:root /tmp/ground_truth.json # Ensure agent cannot read it

# 4. Write patient info for agent
echo "Patient Name: $PATIENT_NAME" > /tmp/task_patient_info.txt
chmod 644 /tmp/task_patient_info.txt
chown ga:ga /tmp/task_patient_info.txt

# 5. Launch Firefox and login
# We navigate to the specific patient's chart to save the agent search time,
# but they still need to navigate tabs.
TARGET_URL="http://localhost/openmrs/spa/patient/$PATIENT_UUID/chart/Patient%20Summary"
ensure_openmrs_logged_in "$TARGET_URL"

# 6. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="