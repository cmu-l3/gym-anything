#!/bin/bash
echo "=== Exporting configure_bidirectional_metering result ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_bidir_final.png

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
    with open('/tmp/initial_feed_count_bidir') as f:
        initial_feed_count = int(f.read().strip() or 0)
except Exception:
    initial_feed_count = 0

# -----------------------------------------------------------------------
# Get process lists for both inputs
# -----------------------------------------------------------------------
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

def get_process_arg(pl, pid):
    """Extract the argument value for a given process ID."""
    if not pl:
        return None
    for step in pl.split(','):
        step = step.strip()
        if step.startswith(f'{pid}:'):
            try:
                return float(step.split(':')[1])
            except (ValueError, IndexError):
                pass
    return None

def get_process_order(pl):
    """Return list of process IDs in order."""
    if not pl:
        return []
    order = []
    for step in pl.split(','):
        step = step.strip()
        if ':' in step:
            try:
                order.append(int(step.split(':')[0]))
            except ValueError:
                pass
    return order

grid_pl = get_pl('building', 'grid_meter')
solar_pl = get_pl('building', 'solar_pv')

grid_steps = count_steps(grid_pl)
solar_steps = count_steps(solar_pl)

# Solar PV checks
solar_has_scale     = has_process_id(solar_pl, 2)
solar_scale_value   = get_process_arg(solar_pl, 2)
solar_has_log       = has_process_id(solar_pl, 1)
solar_has_kwh       = has_process_id(solar_pl, 4)

# Grid meter checks — branching pipeline processes
grid_has_allow_pos  = has_process_id(grid_pl, 24)   # Allow Positive
grid_has_reset_orig = has_process_id(grid_pl, 37)   # Reset to Original
grid_has_allow_neg  = has_process_id(grid_pl, 25)   # Allow Negative
grid_has_scale      = has_process_id(grid_pl, 2)     # Scale (for x-1)
grid_scale_value    = get_process_arg(grid_pl, 2)
grid_has_log        = has_process_id(grid_pl, 1)     # Log to Feed
grid_has_kwh        = has_process_id(grid_pl, 4)     # Power to kWh
grid_process_order  = get_process_order(grid_pl)

# -----------------------------------------------------------------------
# Check for expected feeds by name
# -----------------------------------------------------------------------
def feed_exists(name):
    result = db(f"SELECT id FROM feeds WHERE userid=1 AND name='{name}'")
    return result != '' and result != 'NULL'

solar_power_exists     = feed_exists('solar_power')
solar_kwh_exists       = feed_exists('solar_energy_kwh')
import_power_exists    = feed_exists('grid_import_power')
import_kwh_exists      = feed_exists('grid_import_kwh')
export_power_exists    = feed_exists('grid_export_power')
export_kwh_exists      = feed_exists('grid_export_kwh')

# Count all target feeds
target_feed_count = sum([
    solar_power_exists, solar_kwh_exists,
    import_power_exists, import_kwh_exists,
    export_power_exists, export_kwh_exists
])

current_feed_count = int(db("SELECT COUNT(*) FROM feeds WHERE userid=1") or 0)
new_feed_count = current_feed_count - initial_feed_count

# -----------------------------------------------------------------------
# Dashboard check
# -----------------------------------------------------------------------
dash_rows = db(
    "SELECT name, COALESCE(json,'') FROM dashboard WHERE userid=1 AND ("
    "name LIKE '%Net Zero%' OR name LIKE '%net zero%' OR name LIKE '%Net_Zero%' "
    "OR name LIKE '%NetZero%' OR name LIKE '%netzero%' "
    "OR name LIKE '%Tracker%' OR name LIKE '%tracker%'"
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

# -----------------------------------------------------------------------
# Write result JSON
# -----------------------------------------------------------------------
result = {
    'task_start': task_start,
    'grid_meter_processlist': grid_pl,
    'solar_pv_processlist': solar_pl,
    'grid_step_count': grid_steps,
    'solar_step_count': solar_steps,

    'solar_has_scale': solar_has_scale,
    'solar_scale_value': solar_scale_value,
    'solar_has_log': solar_has_log,
    'solar_has_kwh': solar_has_kwh,

    'grid_has_allow_positive': grid_has_allow_pos,
    'grid_has_reset_to_original': grid_has_reset_orig,
    'grid_has_allow_negative': grid_has_allow_neg,
    'grid_has_scale': grid_has_scale,
    'grid_scale_value': grid_scale_value,
    'grid_has_log': grid_has_log,
    'grid_has_kwh': grid_has_kwh,
    'grid_process_order': grid_process_order,

    'solar_power_feed_exists': solar_power_exists,
    'solar_energy_kwh_feed_exists': solar_kwh_exists,
    'grid_import_power_feed_exists': import_power_exists,
    'grid_import_kwh_feed_exists': import_kwh_exists,
    'grid_export_power_feed_exists': export_power_exists,
    'grid_export_kwh_feed_exists': export_kwh_exists,
    'target_feed_count': target_feed_count,
    'new_feed_count': new_feed_count,

    'dashboard_exists': dashboard_exists,
    'dashboard_name': dashboard_name,
    'dashboard_widget_count': widget_count,
}

with open('/tmp/configure_bidirectional_metering_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
