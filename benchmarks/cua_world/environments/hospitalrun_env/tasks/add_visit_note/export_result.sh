#!/bin/bash
echo "=== Exporting add_visit_note results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_NOTE_COUNT=$(cat /tmp/initial_note_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query CouchDB for all documents to find the note
# We dump all docs and filter in python for robustness against schema variations
echo "Querying database for results..."
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" > /tmp/all_docs.json

# Analyze results with Python
python3 -c "
import json
import sys
import time
import re

try:
    with open('/tmp/all_docs.json', 'r') as f:
        data = json.load(f)
except Exception as e:
    print(json.dumps({'error': str(e)}))
    sys.exit(1)

task_start = $TASK_START
target_patient_id = 'patient_p1_ev001'
target_visit_id = 'visit_p1_ev001'
required_phrases = [
    'Day 3 progress note',
    'improved breathing',
    'reduced cough',
    'SpO2 96%',
    'diminished crackles',
    'right lower lobe',
    'azithromycin 500mg',
    'discharge evaluation tomorrow',
    'completing full antibiotic course'
]

found_note = None
match_score = 0
phrases_found = []
is_new = False
linked_correctly = False

rows = data.get('rows', [])
for row in rows:
    doc = row.get('doc', {})
    d = doc.get('data', doc) # HospitalRun often wraps data in 'data' key
    
    # Check if this look like a note or contains our text
    doc_str = json.dumps(doc).lower()
    
    # Quick filter: must contain at least the title phrase
    if 'day 3 progress note' not in doc_str:
        continue
        
    # Analyze specific content
    current_phrases = []
    for phrase in required_phrases:
        if phrase.lower() in doc_str:
            current_phrases.append(phrase)
            
    # If we found significant content match
    if len(current_phrases) >= 3:
        found_note = doc
        phrases_found = current_phrases
        
        # Check linkage
        # HospitalRun notes often have 'patient' or 'visit' fields, OR are embedded in visits
        p_ref = d.get('patient', '')
        v_ref = d.get('visit', '')
        
        if target_patient_id in p_ref or target_visit_id in v_ref:
            linked_correctly = True
        elif target_patient_id in doc_str: # Fallback loose check
            linked_correctly = True
            
        # Check timestamp/newness
        # Since CouchDB doesn't strictly enforce create time, we check if it wasn't there before
        # (handled by initial count check in caller) or if it has a timestamp field
        # Most HR docs have 'date' or 'dateEntered'
        
        # We assume it's new if we found it and it matches criteria, 
        # relying on the initial_count check in the bash script to confirm net increase
        is_new = True 
        break

result = {
    'note_found': found_note is not None,
    'phrases_found_count': len(phrases_found),
    'phrases_found': phrases_found,
    'linked_correctly': linked_correctly,
    'is_new': is_new,
    'task_timestamp': task_start
}

print(json.dumps(result))
" > /tmp/analysis_result.json

# Check if note count increased
CURRENT_NOTE_COUNT=$(grep -c "Day 3 progress note" /tmp/all_docs.json || echo "0")
COUNT_INCREASED="false"
if [ "$CURRENT_NOTE_COUNT" -gt "$INITIAL_NOTE_COUNT" ]; then
    COUNT_INCREASED="true"
fi

# Combine results
jq -n --slurpfile analysis /tmp/analysis_result.json \
    --arg count_increased "$COUNT_INCREASED" \
    --arg screenshot "/tmp/task_final.png" \
    '{
        analysis: $analysis[0],
        count_increased: ($count_increased == "true"),
        screenshot_path: $screenshot
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="