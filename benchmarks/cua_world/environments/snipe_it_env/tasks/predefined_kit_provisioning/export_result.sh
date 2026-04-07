#!/bin/bash
echo "=== Exporting predefined_kit_provisioning results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Dynamically query all kits and their relationships using Python
python3 << 'PYEOF'
import subprocess
import json
import os

def query(sql):
    cmd = ["docker", "exec", "snipeit-db", "mysql", "-u", "snipeit", "-psnipeit_pass", "snipeit", "-N", "-e", sql]
    try:
        return subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode('utf-8').strip()
    except:
        return ""

# Resolve correct table names for Predefined Kits
kits_table = query("SELECT table_name FROM information_schema.tables WHERE table_name IN ('kits', 'predefined_kits') AND table_schema='snipeit' LIMIT 1")
if not kits_table: kits_table = "predefined_kits"

km_table = query("SELECT table_name FROM information_schema.tables WHERE table_name IN ('kits_models', 'kit_models', 'predefined_kits_models', 'predefined_kit_models') AND table_schema='snipeit' LIMIT 1") or "kits_models"
ka_table = query("SELECT table_name FROM information_schema.tables WHERE table_name IN ('kits_accessories', 'kit_accessories', 'predefined_kits_accessories', 'predefined_kit_accessories') AND table_schema='snipeit' LIMIT 1") or "kits_accessories"
kl_table = query("SELECT table_name FROM information_schema.tables WHERE table_name IN ('kits_licenses', 'kit_licenses', 'predefined_kits_licenses', 'predefined_kit_licenses') AND table_schema='snipeit' LIMIT 1") or "kits_licenses"
kc_table = query("SELECT table_name FROM information_schema.tables WHERE table_name IN ('kits_consumables', 'kit_consumables', 'predefined_kits_consumables', 'predefined_kit_consumables') AND table_schema='snipeit' LIMIT 1") or "kits_consumables"

# Resolve Foreign Key Column names
def get_fk_col(table):
    cols = query(f"SELECT column_name FROM information_schema.columns WHERE table_name='{table}' AND table_schema='snipeit'")
    if 'predefined_kit_id' in cols.split(): return 'predefined_kit_id'
    return 'kit_id'

km_fk = get_fk_col(km_table)
ka_fk = get_fk_col(ka_table)
kl_fk = get_fk_col(kl_table)
kc_fk = get_fk_col(kc_table)

kits_raw = query(f"SELECT id, name, UNIX_TIMESTAMP(created_at) FROM {kits_table} WHERE deleted_at IS NULL")
kits = []

if kits_raw:
    for line in kits_raw.split('\n'):
        if not line.strip(): continue
        parts = line.split('\t')
        if len(parts) >= 3:
            kid, name, created_at = parts[0], parts[1], parts[2]
            
            # Models
            models_raw = query(f"SELECT m.name, km.quantity FROM {km_table} km JOIN models m ON km.model_id = m.id WHERE km.{km_fk}={kid}")
            models = [{"name": r.split('\t')[0], "quantity": int(r.split('\t')[1])} for r in models_raw.split('\n') if '\t' in r]
            
            # Accessories
            acc_raw = query(f"SELECT a.name, ka.quantity FROM {ka_table} ka JOIN accessories a ON ka.accessory_id = a.id WHERE ka.{ka_fk}={kid}")
            accessories = [{"name": r.split('\t')[0], "quantity": int(r.split('\t')[1])} for r in acc_raw.split('\n') if '\t' in r]
            
            # Licenses
            lic_raw = query(f"SELECT l.name, kl.quantity FROM {kl_table} kl JOIN licenses l ON kl.license_id = l.id WHERE kl.{kl_fk}={kid}")
            licenses = [{"name": r.split('\t')[0], "quantity": int(r.split('\t')[1])} for r in lic_raw.split('\n') if '\t' in r]
            
            # Consumables
            cons_raw = query(f"SELECT c.name, kc.quantity FROM {kc_table} kc JOIN consumables c ON kc.consumable_id = c.id WHERE kc.{kc_fk}={kid}")
            consumables = [{"name": r.split('\t')[0], "quantity": int(r.split('\t')[1])} for r in cons_raw.split('\n') if '\t' in r]

            kits.append({
                "id": kid,
                "name": name,
                "created_at": int(created_at) if created_at.isdigit() else 0,
                "models": models,
                "accessories": accessories,
                "licenses": licenses,
                "consumables": consumables
            })

# Get start time and initial count
try:
    with open("/tmp/task_start_time.txt", "r") as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

try:
    with open("/tmp/initial_kit_count.txt", "r") as f:
        initial_count = int(f.read().strip())
except:
    initial_count = 0

result = {
    "kits": kits,
    "task_start": task_start,
    "initial_kit_count": initial_count,
    "current_kit_count": len(kits)
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="