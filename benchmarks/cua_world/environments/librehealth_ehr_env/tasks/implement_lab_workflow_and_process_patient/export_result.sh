#!/bin/bash
echo "=== Exporting Lab Workflow Results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Check ground truth exists
GT_FILE="/tmp/lh_lab_workflow_gt.json"
if [ ! -f "$GT_FILE" ]; then
    echo "ERROR: Ground truth file not found"
    cat > /tmp/task_result.json << 'EOF'
{"error": "ground_truth_missing"}
EOF
    exit 0
fi

# Use Python for robust JSON construction and DB queries
python3 << 'PYEOF'
import json
import subprocess
import sys

def query(sql):
    """Execute a MySQL query via docker exec and return stripped output."""
    try:
        out = subprocess.check_output(
            ['docker', 'exec', 'librehealth-db', 'mysql',
             '-h', '127.0.0.1', '-u', 'libreehr', '-ps3cret', 'libreehr',
             '-N', '-e', sql],
            stderr=subprocess.DEVNULL
        ).decode('utf-8', errors='replace').strip()
        return out
    except Exception:
        return ''

def safe_int(val, default=0):
    """Safely convert a string to int."""
    try:
        return int(val.strip())
    except (ValueError, AttributeError):
        return default

def safe_json(raw):
    """Safely parse a JSON string, returning None on failure."""
    if not raw or raw == 'NULL' or raw == 'null':
        return None
    try:
        return json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        return None

# Load ground truth
with open('/tmp/lh_lab_workflow_gt.json') as f:
    gt = json.load(f)

pid = gt['patient']['pid']
baselines = gt['baselines']
bpt = baselines['max_procedure_type_id']

result = {
    "ground_truth": gt,
    "phase1_infrastructure": {},
    "phase2_order_and_results": {},
    "phase3_clinical_response": {}
}

# ========== Phase 1: Procedure Type Hierarchy ==========

# Look for order group
group_raw = query(
    f"SELECT JSON_OBJECT('id', procedure_type_id, 'parent', parent, "
    f"'name', name, 'code', procedure_code, 'type', procedure_type) "
    f"FROM procedure_type "
    f"WHERE name LIKE '%Endocrine%' AND procedure_type IN ('grp','group') "
    f"AND procedure_type_id > {bpt} LIMIT 1"
)

# Look for procedure order
order_raw = query(
    f"SELECT JSON_OBJECT('id', procedure_type_id, 'parent', parent, "
    f"'name', name, 'code', procedure_code, "
    f"'standard_code', standard_code, 'type', procedure_type) "
    f"FROM procedure_type "
    f"WHERE (name LIKE '%A1c%' OR name LIKE '%Hemoglobin%') "
    f"AND procedure_type IN ('ord','order') "
    f"AND procedure_type_id > {bpt} LIMIT 1"
)

# Count discrete result types created
res_count_raw = query(
    f"SELECT COUNT(*) FROM procedure_type "
    f"WHERE procedure_type IN ('res','result') "
    f"AND procedure_type_id > {bpt}"
)

result['phase1_infrastructure'] = {
    'group': safe_json(group_raw),
    'order': safe_json(order_raw),
    'result_types_count': safe_int(res_count_raw)
}

# ========== Phase 2: Lab Order and Results ==========

# Count new procedure orders for this patient
po_count_raw = query(
    f"SELECT COUNT(*) FROM procedure_order WHERE patient_id={pid}"
)
po_new = safe_int(po_count_raw) - baselines['procedure_order_count']

# Get lab results via join
lab_results_raw = query(
    f"SELECT JSON_ARRAYAGG(JSON_OBJECT("
    f"'result_text', pr.result, "
    f"'units', pr.units, "
    f"'result_status', pr.result_status, "
    f"'type_name', pt.name)) "
    f"FROM procedure_result pr "
    f"JOIN procedure_report prp ON pr.procedure_report_id = prp.procedure_report_id "
    f"JOIN procedure_order po ON prp.procedure_order_id = po.procedure_order_id "
    f"LEFT JOIN procedure_type pt ON pr.procedure_type_id = pt.procedure_type_id "
    f"WHERE po.patient_id = {pid}"
)

# Get report status
report_status_raw = query(
    f"SELECT report_status FROM procedure_report prp "
    f"JOIN procedure_order po ON prp.procedure_order_id = po.procedure_order_id "
    f"WHERE po.patient_id = {pid} "
    f"ORDER BY prp.procedure_report_id DESC LIMIT 1"
)

result['phase2_order_and_results'] = {
    'new_orders': po_new,
    'lab_results': safe_json(lab_results_raw) or [],
    'report_status': report_status_raw.strip() if report_status_raw else None
}

# ========== Phase 3: Clinical Response ==========

# New medical problems
prob_count_raw = query(
    f"SELECT COUNT(*) FROM lists WHERE pid={pid} AND type='medical_problem'"
)
prob_new = safe_int(prob_count_raw) - baselines['problems_count']

# Recent problem titles
prob_titles_raw = query(
    f"SELECT title FROM lists WHERE pid={pid} AND type='medical_problem' "
    f"ORDER BY id DESC LIMIT 5"
)
prob_titles = [t.strip() for t in prob_titles_raw.split('\n') if t.strip()] if prob_titles_raw else []

# New prescriptions
rx_count_raw = query(
    f"SELECT COUNT(*) FROM prescriptions WHERE patient_id={pid}"
)
rx_new = safe_int(rx_count_raw) - baselines['prescriptions_count']

# Recent prescription details
rx_details_raw = query(
    f"SELECT JSON_ARRAYAGG(JSON_OBJECT("
    f"'drug', drug, 'dosage', dosage, "
    f"'quantity', quantity, 'refills', refills)) "
    f"FROM (SELECT drug, dosage, quantity, refills "
    f"FROM prescriptions WHERE patient_id={pid} "
    f"ORDER BY id DESC LIMIT 5) sub"
)

# New appointments
appt_count_raw = query(
    f"SELECT COUNT(*) FROM libreehr_postcalendar_events WHERE pc_pid={pid}"
)
appt_new = safe_int(appt_count_raw) - baselines['appointments_count']

result['phase3_clinical_response'] = {
    'new_problems': prob_new,
    'problem_titles': prob_titles,
    'new_prescriptions': rx_new,
    'prescription_details': safe_json(rx_details_raw) or [],
    'new_appointments': appt_new
}

# Write result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete. Contents:")
print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
