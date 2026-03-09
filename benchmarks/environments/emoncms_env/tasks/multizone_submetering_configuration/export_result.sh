#!/bin/bash
echo "=== Exporting multizone_submetering_configuration result ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_zones_final.png

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
    with open('/tmp/initial_feed_count_zones') as f:
        initial_feed_count = int(f.read().strip() or 0)
except Exception:
    initial_feed_count = 0

def get_pl(node, name):
    return db(f"SELECT processList FROM input WHERE userid=1 AND nodeid='{node}' AND name='{name}'").split('\n')[0]

def count_steps(pl):
    if not pl:
        return 0
    return sum(1 for s in pl.split(',') if ':' in s.strip())

def has_process_id(pl, pid):
    if not pl:
        return False
    return any(s.strip().startswith(f'{pid}:') for s in pl.split(','))

hvac_pl     = get_pl('zone_hvac', 'power_w')
lighting_pl = get_pl('zone_lighting', 'power_w')
sockets_pl  = get_pl('zone_sockets', 'power_w')

hvac_steps     = count_steps(hvac_pl)
lighting_steps = count_steps(lighting_pl)
sockets_steps  = count_steps(sockets_pl)

hvac_has_kwh     = has_process_id(hvac_pl, 4)
lighting_has_kwh = has_process_id(lighting_pl, 4)
sockets_has_kwh  = has_process_id(sockets_pl, 4)

# Count zone-related feeds
zone_feed_count = int(db(
    "SELECT COUNT(*) FROM feeds WHERE userid=1 AND ("
    "tag IN ('hvac','lighting','sockets','zone','HVAC','Lighting','Sockets','Zone') "
    "OR name LIKE '%HVAC%' OR name LIKE '%Lighting%' OR name LIKE '%Socket%' "
    "OR name LIKE '%hvac%' OR name LIKE '%lighting%' OR name LIKE '%socket%' "
    "OR name LIKE '%zone%' OR name LIKE '%Zone%')"
) or 0)

current_feed_count = int(db("SELECT COUNT(*) FROM feeds WHERE userid=1") or 0)
new_feed_count = current_feed_count - initial_feed_count

# Dashboard check
dash_rows = db(
    "SELECT name, COALESCE(json,'') FROM dashboard WHERE userid=1 AND ("
    "name LIKE '%Submeter%' OR name LIKE '%submeter%' "
    "OR name LIKE '%Building%' OR name LIKE '%building%' "
    "OR name LIKE '%Zone%' OR name LIKE '%zone%'"
    ")"
).split('\n')

dashboard_exists = False
dashboard_name   = ''
widget_count     = 0

for row in dash_rows:
    if row.strip():
        parts = row.split('\t')
        dashboard_exists = True
        dashboard_name   = parts[0] if parts else ''
        dash_json        = parts[1] if len(parts) > 1 else ''
        widget_count     = dash_json.count('"type"')
        break

result = {
    'task_start': task_start,
    'hvac_processlist': hvac_pl,
    'lighting_processlist': lighting_pl,
    'sockets_processlist': sockets_pl,
    'hvac_process_steps': hvac_steps,
    'lighting_process_steps': lighting_steps,
    'sockets_process_steps': sockets_steps,
    'hvac_has_kwh': hvac_has_kwh,
    'lighting_has_kwh': lighting_has_kwh,
    'sockets_has_kwh': sockets_has_kwh,
    'zone_feed_count': zone_feed_count,
    'new_feed_count': new_feed_count,
    'dashboard_exists': dashboard_exists,
    'dashboard_name': dashboard_name,
    'dashboard_widget_count': widget_count,
}

with open('/tmp/multizone_submetering_configuration_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
