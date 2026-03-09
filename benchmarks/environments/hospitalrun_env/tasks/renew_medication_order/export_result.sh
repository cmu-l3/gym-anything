#!/bin/bash
echo "=== Exporting renew_medication_order result ==="

source /workspace/scripts/task_utils.sh

# Capture final state
take_screenshot /tmp/renew_med_final.png

# Get Task Start Time
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
# Convert to milliseconds for JS comparison if needed, or keeping unix timestamp for processing
START_TIME_MS=$(($START_TIME * 1000))

# Query CouchDB for NEW medication orders for Martha Kent
# We look for documents of type 'medication' created/modified recently
# AND linked to patient_p1_000006
# AND status is Active/Requested (not the old Completed one)

echo "Querying new medication orders..."

# Use python to filter complex JSON logic from _all_docs
# We fetch all docs, look for medications linked to P006, check if they are NOT the old one.
RESULTS_JSON=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | python3 -c "
import sys, json, time
try:
    data = json.load(sys.stdin)
    rows = data.get('rows', [])
    new_orders = []
    
    target_patient = 'patient_p1_000006'
    start_time_sec = $START_TIME
    
    for row in rows:
        doc = row.get('doc', {})
        # HospitalRun wraps content in 'data' usually, but sometimes top level
        d = doc.get('data', doc)
        
        # Check if it's a medication/prescription
        # Heuristics: has 'medication' field OR type='medication'
        is_med = d.get('type') == 'medication' or 'medication' in d or 'prescription' in d
        
        if not is_med:
            continue
            
        # Check link to patient
        p_ref = d.get('patient', '')
        if target_patient not in p_ref and 'Martha' not in str(d) and 'Kent' not in str(d):
            continue
            
        # Check status (should be active/new)
        status = d.get('status', '').lower()
        if status in ['completed', 'expired', 'discontinued']:
            continue
            
        # Check if created/modified after task start
        # CouchDB doesn't strictly enforce created_at, so we rely on:
        # 1. It's not the specific historical ID we seeded
        # 2. OR explicit date fields if present
        
        doc_id = row.get('id', '')
        if doc_id == 'medication_p1_000006_old':
            continue
            
        new_orders.append({
            'id': doc_id,
            'medication': d.get('medication', d.get('inventoryItem', '')),
            'dosage': d.get('prescription', d.get('dosage', '')),
            'frequency': d.get('frequency', ''),
            'status': d.get('status', ''),
            'startDate': d.get('startDate', '')
        })
        
    print(json.dumps(new_orders))
except Exception as e:
    print(json.dumps({'error': str(e)}))
")

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start_time": $START_TIME,
    "timestamp": "$(date -Iseconds)",
    "new_orders": $RESULTS_JSON,
    "screenshot_path": "/tmp/renew_med_final.png"
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json