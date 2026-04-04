#!/bin/bash
echo "=== Exporting order_lab_test results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state evidence
take_screenshot /tmp/task_final.png

# 2. Get Timing Data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Identify Patient
PATIENT_ID="BAH000012"
PATIENT_UUID=$(get_patient_uuid_by_identifier "$PATIENT_ID")

if [ -z "$PATIENT_UUID" ]; then
  echo "ERROR: Could not resolve patient UUID for $PATIENT_ID"
  # Dump empty result to avoid crash
  echo '{"error": "Patient not found"}' > /tmp/task_result.json
  exit 0
fi

# 4. Query OpenMRS for Orders
# We get 'testorder' types for this patient
# We fetch 'full' view to see concept names and dates
echo "Querying orders for patient $PATIENT_UUID..."
ORDERS_JSON=$(openmrs_api_get "/order?patient=${PATIENT_UUID}&t=testorder&v=full")

# 5. Process Orders with Python to handle logic robustly
# We pass the JSON and the Task Start Time to a python one-liner or script
# to filter for orders created AFTER the task started.

python3 -c "
import sys, json, datetime

try:
    task_start_ts = int('$TASK_START')
    orders_data = json.loads('''$ORDERS_JSON''')
    
    results = orders_data.get('results', [])
    
    found_haemoglobin = False
    found_esr = False
    new_order_count = 0
    
    created_orders = []

    for order in results:
        # Date format in OpenMRS: '2023-10-27T10:00:00.000+0000'
        date_str = order.get('dateActivated', '') or order.get('auditInfo', {}).get('dateCreated', '')
        
        # Simple string comparison isn't enough, need parsing
        # But we can approximate with timestamp if available or strict parsing
        # Let's rely on the fact that standard python iso parsing might need 3.7+ for timezone
        # We'll use basic string parsing for the example format
        
        is_new = False
        if date_str:
             # loose parse: 2023-10-27T10:00:00
             try:
                 dt_str = date_str.split('.')[0]
                 dt = datetime.datetime.strptime(dt_str, '%Y-%m-%dT%H:%M:%S')
                 # OpenMRS dates are usually UTC. Task start is UTC (unix ts).
                 # We treat both as naive or UTC.
                 # Adjust task_start to dt
                 if dt.timestamp() > task_start_ts:
                     is_new = True
             except Exception as e:
                 # Fallback: if we can't parse, assume False to be safe
                 pass
        
        if is_new:
            new_order_count += 1
            concept_name = order.get('concept', {}).get('display', '').lower()
            order_uuid = order.get('uuid')
            
            created_orders.append({
                'uuid': order_uuid,
                'concept': concept_name,
                'date': date_str
            })
            
            if 'haemoglobin' in concept_name:
                found_haemoglobin = True
            
            if 'erythrocyte sedimentation rate' in concept_name or 'esr' in concept_name:
                found_esr = True

    output = {
        'task_start': task_start_ts,
        'patient_uuid': '$PATIENT_UUID',
        'found_haemoglobin': found_haemoglobin,
        'found_esr': found_esr,
        'new_order_count': new_order_count,
        'created_orders': created_orders,
        'screenshot_path': '/tmp/task_final.png'
    }
    
    print(json.dumps(output))

except Exception as e:
    print(json.dumps({'error': str(e)}))
" > /tmp/task_result.json

# 6. Secure the result file
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json