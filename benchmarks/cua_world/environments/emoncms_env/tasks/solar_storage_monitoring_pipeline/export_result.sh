#!/bin/bash
echo "=== Exporting solar_storage_monitoring_pipeline result ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_solar_storage_final.png

python3 << 'PYEOF'
import subprocess, json, sys

def db(sql):
    r = subprocess.run(
        ['docker', 'exec', 'emoncms-db', 'mysql', '-u', 'emoncms', '-pemoncms', 'emoncms', '-N', '-e', sql],
        capture_output=True, text=True
    )
    return r.stdout.strip()

# Read baseline values from setup files
try:
    with open('/tmp/task_start_timestamp') as f:
        task_start = int(f.read().strip() or 0)
except Exception:
    task_start = 0

try:
    with open('/tmp/initial_feed_count_pvbms') as f:
        initial_feed_count = int(f.read().strip() or 0)
except Exception:
    initial_feed_count = 0

# Get pvbms input processlists
def get_pl(name):
    return db(f"SELECT processList FROM input WHERE userid=1 AND nodeid='pvbms' AND name='{name}'").split('\n')[0]

solar_pl = get_pl('solar_w')
soc_pl   = get_pl('battery_soc')
chg_pl   = get_pl('battery_charge_w')
dis_pl   = get_pl('battery_discharge_w')

def count_steps(pl):
    if not pl:
        return 0
    return sum(1 for s in pl.split(',') if ':' in s.strip())

def has_process_id(pl, pid):
    if not pl:
        return False
    return any(s.strip().startswith(f'{pid}:') for s in pl.split(','))

solar_steps        = count_steps(solar_pl)
solar_has_log      = has_process_id(solar_pl, 1)
solar_has_kwh      = has_process_id(solar_pl, 4)
soc_has_process    = count_steps(soc_pl) > 0
chg_has_process    = count_steps(chg_pl) > 0
dis_has_process    = count_steps(dis_pl) > 0

# Count pvbms/solar/battery related feeds
pvbms_feed_count = int(db(
    "SELECT COUNT(*) FROM feeds WHERE userid=1 AND ("
    "tag='pvbms' OR tag='solar' OR tag='battery' OR tag='pv' "
    "OR name LIKE '%solar%' OR name LIKE '%Solar%' "
    "OR name LIKE '%battery%' OR name LIKE '%Battery%' "
    "OR name LIKE '%PV%' OR name LIKE '%kWh%')"
) or 0)

current_feed_count = int(db("SELECT COUNT(*) FROM feeds WHERE userid=1") or 0)
new_feed_count = current_feed_count - initial_feed_count

# Dashboard check — look for solar/battery/pv dashboard
dash_rows = db(
    "SELECT name, COALESCE(json,'') FROM dashboard WHERE userid=1 AND ("
    "name LIKE '%Solar%' OR name LIKE '%solar%' "
    "OR name LIKE '%PV%' OR name LIKE '%pv%' "
    "OR name LIKE '%Battery%' OR name LIKE '%battery%'"
    ")"
).split('\n')

dashboard_exists  = False
dashboard_name    = ''
widget_count      = 0

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
    'solar_w_processlist': solar_pl,
    'battery_soc_processlist': soc_pl,
    'battery_charge_processlist': chg_pl,
    'battery_discharge_processlist': dis_pl,
    'solar_process_count': solar_steps,
    'solar_has_log_process': solar_has_log,
    'solar_has_kwh_process': solar_has_kwh,
    'battery_soc_has_process': soc_has_process,
    'battery_charge_has_process': chg_has_process,
    'battery_discharge_has_process': dis_has_process,
    'pvbms_feed_count': pvbms_feed_count,
    'new_feed_count': new_feed_count,
    'dashboard_exists': dashboard_exists,
    'dashboard_name': dashboard_name,
    'dashboard_widget_count': widget_count,
}

with open('/tmp/solar_storage_monitoring_pipeline_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
