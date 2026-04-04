#!/bin/bash
echo "=== Exporting emoncms_data_audit_remediation result ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_audit_final.png

python3 << 'PYEOF'
import subprocess, json

def db(sql):
    r = subprocess.run(
        ['docker', 'exec', 'emoncms-db', 'mysql', '-u', 'emoncms', '-pemoncms', 'emoncms', '-N', '-e', sql],
        capture_output=True, text=True
    )
    return r.stdout.strip()

try:
    with open('/tmp/task_start_timestamp') as f:
        task_start = int(f.read().strip() or 0)
except Exception:
    task_start = 0

try:
    with open('/tmp/audit_house_power_feed_id') as f:
        house_power_id = int(f.read().strip() or 0)
except Exception:
    house_power_id = 0

try:
    with open('/tmp/audit_solar_pv_feed_id') as f:
        solar_pv_id = int(f.read().strip() or 0)
except Exception:
    solar_pv_id = 0

# --- Check 1: power1 input processlist references a valid feed ID ---
power1_pl = db("SELECT processList FROM input WHERE userid=1 AND name='power1'").split('\n')[0]
power1_feed_ids = []
for step in power1_pl.split(','):
    step = step.strip()
    if ':' in step:
        parts = step.split(':')
        try:
            power1_feed_ids.append(int(parts[1]))
        except (ValueError, IndexError):
            pass

# Check each referenced feed ID actually exists
power1_valid = False
for fid in power1_feed_ids:
    exists = db(f"SELECT COUNT(*) FROM feeds WHERE id={fid} AND userid=1").strip()
    if exists == '1':
        power1_valid = True
        break

# --- Check 2: solar input processlist references a valid feed ID ---
solar_pl = db("SELECT processList FROM input WHERE userid=1 AND name='solar'").split('\n')[0]
solar_feed_ids = []
for step in solar_pl.split(','):
    step = step.strip()
    if ':' in step:
        parts = step.split(':')
        try:
            solar_feed_ids.append(int(parts[1]))
        except (ValueError, IndexError):
            pass

solar_valid = False
for fid in solar_feed_ids:
    exists = db(f"SELECT COUNT(*) FROM feeds WHERE id={fid} AND userid=1").strip()
    if exists == '1':
        solar_valid = True
        break

# --- Check 3: House Power feed interval > 0 ---
house_power_row = db("SELECT interval, engine FROM feeds WHERE userid=1 AND name='House Power'").split('\n')[0]
house_power_interval = 0
house_power_engine   = 0
if house_power_row:
    parts = house_power_row.split('\t')
    try:
        house_power_interval = int(parts[0])
    except (ValueError, IndexError):
        pass
    try:
        house_power_engine = int(parts[1])
    except (ValueError, IndexError):
        pass

# --- Check 4: House Temperature feed engine > 0 ---
house_temp_row = db("SELECT interval, engine FROM feeds WHERE userid=1 AND name='House Temperature'").split('\n')[0]
house_temp_interval = 0
house_temp_engine   = 0
if house_temp_row:
    parts = house_temp_row.split('\t')
    try:
        house_temp_interval = int(parts[0])
    except (ValueError, IndexError):
        pass
    try:
        house_temp_engine = int(parts[1])
    except (ValueError, IndexError):
        pass

# --- Check 5: Solar PV feed tag is non-empty ---
solar_pv_row = db("SELECT tag FROM feeds WHERE userid=1 AND name='Solar PV'").split('\n')[0]
solar_pv_tag = solar_pv_row.strip() if solar_pv_row else ''

result = {
    'task_start': task_start,
    'power1_processlist': power1_pl,
    'power1_feed_ids_referenced': power1_feed_ids,
    'power1_references_valid_feed': power1_valid,
    'solar_processlist': solar_pl,
    'solar_feed_ids_referenced': solar_feed_ids,
    'solar_references_valid_feed': solar_valid,
    'house_power_interval': house_power_interval,
    'house_power_interval_valid': house_power_interval > 0,
    'house_temp_engine': house_temp_engine,
    'house_temp_engine_valid': house_temp_engine > 0,
    'solar_pv_tag': solar_pv_tag,
    'solar_pv_tag_valid': len(solar_pv_tag) > 0,
    # Reference IDs (stored at setup time)
    'known_house_power_feed_id': house_power_id,
    'known_solar_pv_feed_id': solar_pv_id,
}

with open('/tmp/emoncms_data_audit_remediation_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
