#!/bin/bash
echo "=== Exporting Record Disposition Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final State
take_screenshot /tmp/task_final.png

# 2. Get Task Context
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_encounter_count.txt 2>/dev/null || echo "0")
PATIENT_ID="BAH000002"
PATIENT_UUID=$(get_patient_uuid_by_identifier "$PATIENT_ID")

if [ -z "$PATIENT_UUID" ]; then
    echo "ERROR: Could not resolve patient UUID during export."
    # Dump minimal fail result
    echo '{"error": "Patient not found"}' > /tmp/task_result.json
    exit 0
fi

# 3. Query Post-Task State
# Get all encounters for patient with full details to see Obs
# We fetch full details (v=full) to inspect the disposition observations
ALL_ENCOUNTERS_RESP=$(openmrs_api_get "/encounter?patient=${PATIENT_UUID}&v=full")
CURRENT_COUNT=$(echo "$ALL_ENCOUNTERS_RESP" | jq '.results | length')

# 4. Find the relevant encounter
# We look for an encounter that:
# - Was created AFTER the task start time
# - Contains a Disposition observation
# 
# Note: In Bahmni, "Disposition" is usually a specific Concept Group.
# The structure is often: Obs(Disposition) -> GroupMembers [Obs(Disposition Code), Obs(Disposition Note)]
# Or flat structure depending on config. We will search broadly for "Admit" in display strings.

# We use python to parse the complex JSON response robustly
python3 -c "
import json
import sys
import datetime

try:
    data = json.load(sys.stdin)
    results = data.get('results', [])
    task_start_ts = int($TASK_START_TIME)
    
    found_encounter = None
    disposition_found = False
    disposition_value = None
    disposition_note = None
    
    # Process encounters from newest to oldest
    for enc in sorted(results, key=lambda x: x.get('encounterDatetime', ''), reverse=True):
        # Check timestamp (approximate check, relying on encounterDatetime)
        enc_time_str = enc.get('encounterDatetime', '')
        # Parse ISO format: 2023-10-25T10:00:00.000+0000
        # Simple string comparison is often enough for ordering, but let's be safe
        # We'll just check if it's one of the new ones based on count if timestamps are tricky
        
        obs_list = enc.get('obs', [])
        
        # Look for Disposition obs
        # Bahmni 'Disposition' concept usually has display name 'Disposition'
        for obs in obs_list:
            display = obs.get('display', '').lower()
            concept_name = obs.get('concept', {}).get('display', '').lower()
            
            # Check for the Disposition grouping or direct value
            # Structure A: Concept 'Disposition' with group members
            if 'disposition' in concept_name:
                group_members = obs.get('groupMembers', [])
                if group_members:
                    # It's a group, look inside
                    for member in group_members:
                        member_concept = member.get('concept', {}).get('display', '').lower()
                        member_val = member.get('value', {})
                        
                        # Handle value being an object (concept) or string
                        member_val_display = ''
                        if isinstance(member_val, dict):
                            member_val_display = member_val.get('display', '')
                        else:
                            member_val_display = str(member_val)
                            
                        # Check for Admit/Discharge etc
                        if 'admit' in member_val_display.lower():
                            disposition_found = True
                            disposition_value = member_val_display
                            found_encounter = enc
                        
                        # Check for notes
                        if 'note' in member_concept:
                            disposition_note = member_val_display
                else:
                    # Structure B: Flat obs (less common for disposition but possible)
                    val_display = ''
                    val = obs.get('value', {})
                    if isinstance(val, dict):
                        val_display = val.get('display', '')
                    else:
                        val_display = str(val)
                        
                    if 'admit' in val_display.lower():
                        disposition_found = True
                        disposition_value = val_display
                        found_encounter = enc

        if disposition_found:
            break

    output = {
        'initial_count': int($INITIAL_COUNT),
        'current_count': len(results),
        'encounter_found': bool(found_encounter),
        'encounter_uuid': found_encounter.get('uuid') if found_encounter else None,
        'disposition_value': disposition_value,
        'disposition_note': disposition_note,
        'timestamp': datetime.datetime.now().isoformat()
    }
    print(json.dumps(output))

except Exception as e:
    print(json.dumps({'error': str(e)}))
" <<< "$ALL_ENCOUNTERS_RESP" > /tmp/task_result.json

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json