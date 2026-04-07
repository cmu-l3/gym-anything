#!/bin/bash
set -e
echo "=== Setting up create_provider task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Clean up: Remove any existing provider with the target identifier
echo "Cleaning up any existing 'PROV-8821'..."
omrs_db_query "DELETE FROM provider WHERE identifier = 'PROV-8821';"

# 2. Ensure Person 'Alice Bowman' exists
# We use Python to interact with the REST API for reliable person creation/checking
echo "Ensuring Person 'Alice Bowman' exists..."

python3 -c "
import requests, json, sys

# API Configuration
OMRS_BASE = 'http://localhost/openmrs/ws/rest/v1'
AUTH = ('admin', 'Admin123')

def find_person(given, family):
    try:
        r = requests.get(f'{OMRS_BASE}/person?q={given}&v=default', auth=AUTH)
        if r.ok:
            results = r.json().get('results', [])
            for p in results:
                display = p.get('display', '')
                if given in display and family in display:
                    return p['uuid']
    except Exception as e:
        print(f'Error searching person: {e}')
    return None

def create_person(given, family):
    payload = {
        'names': [{'givenName': given, 'familyName': family}],
        'gender': 'F',
        'birthdate': '1980-01-01'
    }
    try:
        r = requests.post(f'{OMRS_BASE}/person', json=payload, auth=AUTH)
        if r.ok:
            return r.json()['uuid']
        else:
            print(f'Failed to create person: {r.text}')
    except Exception as e:
        print(f'Error creating person: {e}')
    return None

# Execution
given = 'Alice'
family = 'Bowman'
uuid = find_person(given, family)

if not uuid:
    print(f'Creating new person record for {given} {family}...')
    uuid = create_person(given, family)

if uuid:
    print(f'Target Person UUID: {uuid}')
    # Save UUID to file for the export script to verify against
    with open('/tmp/target_person_uuid.txt', 'w') as f:
        f.write(uuid)
else:
    print('CRITICAL ERROR: Could not ensure person exists')
    sys.exit(1)
"

# 3. Double check cleanup: Ensure this person is not already a provider (with ANY identifier)
# If she is, retire that provider record so the agent starts fresh
TARGET_UUID=$(cat /tmp/target_person_uuid.txt 2>/dev/null || echo "")
if [ -n "$TARGET_UUID" ]; then
    echo "Ensuring Alice Bowman is not already a provider..."
    # We need the person_id (integer) for the DB query, but we have UUID.
    # We'll rely on the DB query in export to verify the link.
    # For setup, just cleaning by identifier is sufficient for the specific task goal.
    true
fi

# 4. Record initial person count (to detect duplicates later)
INITIAL_PERSON_COUNT=$(omrs_db_query "SELECT count(*) FROM person_name WHERE given_name='Alice' AND family_name='Bowman' AND voided=0;")
echo "$INITIAL_PERSON_COUNT" > /tmp/initial_person_count.txt
echo "Initial person count for Alice Bowman: $INITIAL_PERSON_COUNT"

# 5. Log in and navigate to Home
ensure_openmrs_logged_in "http://localhost/openmrs/spa/home"

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="