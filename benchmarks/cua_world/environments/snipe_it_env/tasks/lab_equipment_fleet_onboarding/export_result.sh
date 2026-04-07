#!/bin/bash
echo "=== Exporting lab_equipment_fleet_onboarding results ==="

source /workspace/scripts/task_utils.sh

# Capture final UI state
take_screenshot /tmp/task_final_state.png

# Query MariaDB container directly via a Python wrapper to elegantly construct complex JSON
cat > /tmp/export.py << 'EOF'
import subprocess
import json

def query(sql):
    try:
        res = subprocess.check_output(
            ["docker", "exec", "snipeit-db", "mysql", "-u", "snipeit", "-psnipeit_pass", "snipeit", "-N", "-B", "-e", sql],
            universal_newlines=True
        )
        return [line.split('\t') for line in res.strip().split('\n') if line]
    except Exception as e:
        return []

data = {}

# Supplier check
s = query("SELECT id, address, email, phone FROM suppliers WHERE name='Fisher Scientific' AND deleted_at IS NULL LIMIT 1")
if s:
    data['supplier'] = {'found': True, 'id': s[0][0], 'address': s[0][1], 'email': s[0][2], 'phone': s[0][3]}
else:
    data['supplier'] = {'found': False}

# Manufacturer check
m = query("SELECT id FROM manufacturers WHERE name='Keysight Technologies' AND deleted_at IS NULL LIMIT 1")
if m:
    data['manufacturer'] = {'found': True, 'id': m[0][0]}
else:
    data['manufacturer'] = {'found': False}

# Category check
c = query("SELECT id, category_type FROM categories WHERE name='Lab Instruments' AND deleted_at IS NULL LIMIT 1")
if c:
    data['category'] = {'found': True, 'id': c[0][0], 'type': c[0][1]}
else:
    data['category'] = {'found': False}

# Location check
l = query("SELECT id FROM locations WHERE name='Engineering Lab 204' AND deleted_at IS NULL LIMIT 1")
if l:
    data['location'] = {'found': True, 'id': l[0][0]}
else:
    data['location'] = {'found': False}

# Models check
data['models'] = {}
for m_name in ['DSOX1204G Oscilloscope', '34465A Digital Multimeter']:
    mod = query(f"SELECT id, model_number, manufacturer_id, category_id FROM models WHERE name='{m_name}' AND deleted_at IS NULL LIMIT 1")
    if mod:
        data['models'][m_name] = {'found': True, 'id': mod[0][0], 'model_number': mod[0][1], 'mfr_id': mod[0][2], 'cat_id': mod[0][3]}
    else:
        data['models'][m_name] = {'found': False}

# Assets Check
data['assets'] = {}
for tag in ['LAB-0001', 'LAB-0002', 'LAB-0003', 'LAB-0004']:
    a = query(f"SELECT id, serial, model_id, purchase_date, purchase_cost, warranty_months, supplier_id, rtd_location_id, order_number, status_id FROM assets WHERE asset_tag='{tag}' AND deleted_at IS NULL LIMIT 1")
    if a:
        status_name = "unknown"
        if len(a[0]) > 9 and a[0][9] and a[0][9] != "NULL":
            st = query(f"SELECT name FROM status_labels WHERE id={a[0][9]}")
            if st:
                status_name = st[0][0]
                
        data['assets'][tag] = {
            'found': True,
            'id': a[0][0],
            'serial': a[0][1] if len(a[0]) > 1 else '',
            'model_id': a[0][2] if len(a[0]) > 2 else '',
            'purchase_date': a[0][3] if len(a[0]) > 3 else '',
            'purchase_cost': a[0][4] if len(a[0]) > 4 else '',
            'warranty_months': a[0][5] if len(a[0]) > 5 else '',
            'supplier_id': a[0][6] if len(a[0]) > 6 else '',
            'location_id': a[0][7] if len(a[0]) > 7 else '',
            'order_number': a[0][8] if len(a[0]) > 8 else '',
            'status_name': status_name
        }
    else:
        data['assets'][tag] = {'found': False}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=2)
EOF

python3 /tmp/export.py

chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Results stored in /tmp/task_result.json"
cat /tmp/task_result.json