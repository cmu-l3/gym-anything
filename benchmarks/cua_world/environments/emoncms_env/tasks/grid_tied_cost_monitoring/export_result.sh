#!/bin/bash
echo "=== Exporting grid_tied_cost_monitoring result ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_grid_final.png

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
    with open('/tmp/initial_feed_count_grid') as f:
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

def get_multiply_value(pl):
    """Extract the multiplier value from a process-3 step."""
    if not pl:
        return None
    for step in pl.split(','):
        step = step.strip()
        if step.startswith('3:'):
            try:
                return float(step.split(':')[1])
            except (ValueError, IndexError):
                pass
    return None

import_pl = get_pl('smartmeter', 'import_w')
export_pl = get_pl('smartmeter', 'export_w')

import_steps      = count_steps(import_pl)
export_steps      = count_steps(export_pl)
import_has_multiply = has_process_id(import_pl, 3)
import_has_log    = has_process_id(import_pl, 1)
import_has_kwh    = has_process_id(import_pl, 4)
export_has_log    = has_process_id(export_pl, 1)
export_has_kwh    = has_process_id(export_pl, 4)
multiply_value    = get_multiply_value(import_pl)

# Count grid/smartmeter feeds
grid_feed_count = int(db(
    "SELECT COUNT(*) FROM feeds WHERE userid=1 AND ("
    "tag='smartmeter' OR tag='grid' OR tag='import' OR tag='export' "
    "OR name LIKE '%Grid%' OR name LIKE '%Import%' OR name LIKE '%Export%' "
    "OR name LIKE '%grid%' OR name LIKE '%import%' OR name LIKE '%export%')"
) or 0)

current_feed_count = int(db("SELECT COUNT(*) FROM feeds WHERE userid=1") or 0)
new_feed_count = current_feed_count - initial_feed_count

# Dashboard check
dash_rows = db(
    "SELECT name, COALESCE(json,'') FROM dashboard WHERE userid=1 AND ("
    "name LIKE '%Grid%' OR name LIKE '%grid%' "
    "OR name LIKE '%Energy Monitor%' OR name LIKE '%Net Meter%' "
    "OR name LIKE '%Import%' OR name LIKE '%import%'"
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
    'import_w_processlist': import_pl,
    'export_w_processlist': export_pl,
    'import_steps': import_steps,
    'export_steps': export_steps,
    'import_has_multiply': import_has_multiply,
    'import_has_log': import_has_log,
    'import_has_kwh': import_has_kwh,
    'export_has_log': export_has_log,
    'export_has_kwh': export_has_kwh,
    'multiply_value': multiply_value,
    'grid_feed_count': grid_feed_count,
    'new_feed_count': new_feed_count,
    'dashboard_exists': dashboard_exists,
    'dashboard_name': dashboard_name,
    'dashboard_widget_count': widget_count,
}

with open('/tmp/grid_tied_cost_monitoring_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
