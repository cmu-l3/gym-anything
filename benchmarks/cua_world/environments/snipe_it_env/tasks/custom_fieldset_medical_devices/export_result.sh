#!/bin/bash
echo "=== Exporting custom_fieldset_medical_devices results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Write a Python script to extract all necessary DB and API state
cat << 'EOF' > /tmp/gather_results.py
import json
import subprocess

def db_query(q):
    cmd = ['docker', 'exec', 'snipeit-db', 'mysql', '-u', 'snipeit', '-psnipeit_pass', 'snipeit', '-N', '-e', q]
    try:
        res = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode('utf-8').strip()
        return [line.split('\t') for line in res.split('\n') if line]
    except Exception as e:
        return []

def api_query(endpoint):
    try:
        with open('/home/ga/snipeit/api_token.txt', 'r') as f:
            token = f.read().strip()
        cmd = ['curl', '-s', '-X', 'GET', f'http://localhost:8000/api/v1/{endpoint}',
               '-H', 'Accept: application/json', '-H', f'Authorization: Bearer {token}']
        res = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode('utf-8')
        return json.loads(res)
    except Exception as e:
        return {}

result = {}

# 1. Fieldset
fs = db_query("SELECT id, name FROM custom_fieldsets WHERE name='Medical Device Compliance' AND deleted_at IS NULL")
result['fieldset'] = {'found': len(fs) > 0, 'id': fs[0][0] if fs else None}

# 2. Fields
fields = db_query("SELECT id, name, format, element FROM custom_fields WHERE deleted_at IS NULL")
target_fields = ['FDA 510(k) Number', 'Next Calibration Due', 'Patient Contact Class', 'Biomedical Cert Expiry']
result['fields'] = {}
for f in fields:
    if f[1] in target_fields:
        result['fields'][f[1]] = {'id': f[0], 'format': f[2], 'element': f[3]}

# 3. Pivot (Associations & Required Flags)
if result['fieldset']['found']:
    fs_id = result['fieldset']['id']
    pivot = db_query(f"SELECT custom_field_id, required FROM custom_field_custom_fieldset WHERE custom_fieldset_id={fs_id}")
    result['pivot'] = {p[0]: p[1] for p in pivot}
else:
    result['pivot'] = {}

# 4. Category
cat = db_query("SELECT id, name FROM categories WHERE name='Medical Devices' AND deleted_at IS NULL")
result['category'] = {'found': len(cat) > 0, 'id': cat[0][0] if cat else None}

# 5. Manufacturer
mfg = db_query("SELECT id, name FROM manufacturers WHERE name='GE Healthcare' AND deleted_at IS NULL")
result['manufacturer'] = {'found': len(mfg) > 0, 'id': mfg[0][0] if mfg else None}

# 6. Model
mod = db_query("SELECT id, category_id, manufacturer_id, fieldset_id, model_number FROM models WHERE name='GE Carescape B650' AND deleted_at IS NULL")
if mod:
    result['model'] = {
        'found': True,
        'id': mod[0][0],
        'category_id': mod[0][1],
        'manufacturer_id': mod[0][2],
        'fieldset_id': mod[0][3],
        'model_number': mod[0][4]
    }
else:
    result['model'] = {'found': False}

# 7. Asset
asset_api = api_query("hardware/bytag/MED-001")
if asset_api and 'id' in asset_api:
    result['asset_api'] = asset_api
else:
    # Try searching
    search_api = api_query("hardware?search=MED-001")
    if search_api and search_api.get('total', 0) > 0:
        result['asset_api'] = search_api['rows'][0]
    else:
        result['asset_api'] = {}

asset_db = db_query("SELECT id, model_id, serial FROM assets WHERE asset_tag='MED-001' AND deleted_at IS NULL")
if asset_db:
    result['asset_db'] = {'found': True, 'id': asset_db[0][0], 'model_id': asset_db[0][1], 'serial': asset_db[0][2]}
else:
    result['asset_db'] = {'found': False}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

# Execute python script
python3 /tmp/gather_results.py

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result JSON:"
cat /tmp/task_result.json
echo "=== Export complete ==="