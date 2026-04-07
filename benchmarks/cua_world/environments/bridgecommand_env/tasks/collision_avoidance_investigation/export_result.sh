#!/bin/bash
echo "=== Exporting collision_avoidance_investigation results ==="

RECON_DIR="/opt/bridgecommand/Scenarios/n) Collision Reconstruction"
AVOID_DIR="/opt/bridgecommand/Scenarios/o) Avoidance Demonstration"
REPORT_FILE="/home/ga/Documents/Investigation/collision_report.txt"
BC_CONFIG_USER="/home/ga/.config/Bridge Command/bc5.ini"
BC_CONFIG_DATA="/opt/bridgecommand/bc5.ini"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use Python to robustly parse INI files and generate JSON result
python3 -c "
import configparser
import json
import os
import re

# Helper to read flat INI files (environment.ini, ownship.ini)
def read_ini(filepath):
    if not os.path.exists(filepath):
        return None
    data = {}
    try:
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                if '=' in line and not line.startswith(';') and not line.startswith('#'):
                    key, val = line.split('=', 1)
                    val = val.strip().strip('\"')
                    data[key.strip()] = val
    except Exception as e:
        return {'error': str(e)}
    return data

# Helper to read othership.ini with Key(N)=Value and Key(N,M)=Value format
def read_othership(filepath):
    if not os.path.exists(filepath):
        return None
    vessels = {}
    try:
        with open(filepath, 'r') as f:
            lines = f.readlines()
        for line in lines:
            line = line.strip()
            # Match Key(VesselIdx, LegIdx)=Value OR Key(VesselIdx)=Value
            m = re.match(r'([a-zA-Z0-9]+)\(([0-9]+)(?:,\s*([0-9]+))?\)=(.+)', line)
            if m:
                key, v_idx, l_idx, val = m.groups()
                v_idx = int(v_idx)
                val = val.strip().strip('\"')
                if v_idx not in vessels:
                    vessels[v_idx] = {'legs': {}}
                if l_idx:
                    l_idx = int(l_idx)
                    if l_idx not in vessels[v_idx]['legs']:
                        vessels[v_idx]['legs'][l_idx] = {}
                    vessels[v_idx]['legs'][l_idx][key] = val
                else:
                    vessels[v_idx][key] = val
        # Flatten for export
        export_list = []
        for idx in sorted(vessels.keys()):
            v = vessels[idx]
            leg1 = v['legs'].get(1, {})
            try:
                item = {
                    'index': idx,
                    'type': v.get('Type', ''),
                    'lat': float(v.get('InitLat', 0)),
                    'long': float(v.get('InitLong', 0)),
                    'num_legs': int(v.get('Legs', 0)),
                    'leg1_speed': float(leg1.get('Speed', 0)),
                    'leg1_bearing': float(leg1.get('Bearing', 0)),
                    'leg1_distance': float(leg1.get('Distance', 0)),
                    'all_legs': {str(k): vv for k, vv in v['legs'].items()}
                }
                export_list.append(item)
            except Exception as e:
                export_list.append({'index': idx, 'error': str(e)})
        return export_list
    except Exception as e:
        return {'error': str(e)}

# Helper to read bc5.ini
def read_config(filepath):
    if not os.path.exists(filepath):
        return {}
    config = configparser.ConfigParser()
    try:
        config.read(filepath)
        return {s: dict(config.items(s)) for s in config.sections()}
    except:
        return read_ini(filepath)

# --- Gather Data ---
result = {
    'reconstruction': {
        'scenario_exists': os.path.isdir('$RECON_DIR'),
        'files': {}
    },
    'avoidance': {
        'scenario_exists': os.path.isdir('$AVOID_DIR'),
        'files': {}
    },
    'config': {},
    'report': {}
}

# 1. Parse Reconstruction Scenario
if result['reconstruction']['scenario_exists']:
    result['reconstruction']['files']['environment'] = read_ini(os.path.join('$RECON_DIR', 'environment.ini'))
    result['reconstruction']['files']['ownship'] = read_ini(os.path.join('$RECON_DIR', 'ownship.ini'))
    result['reconstruction']['files']['othership'] = read_othership(os.path.join('$RECON_DIR', 'othership.ini'))
    try:
        mtime = os.path.getmtime('$RECON_DIR')
        result['reconstruction']['created_after_start'] = mtime > $TASK_START_TIME
    except:
        result['reconstruction']['created_after_start'] = False

# 2. Parse Avoidance Scenario
if result['avoidance']['scenario_exists']:
    result['avoidance']['files']['environment'] = read_ini(os.path.join('$AVOID_DIR', 'environment.ini'))
    result['avoidance']['files']['ownship'] = read_ini(os.path.join('$AVOID_DIR', 'ownship.ini'))
    result['avoidance']['files']['othership'] = read_othership(os.path.join('$AVOID_DIR', 'othership.ini'))
    try:
        mtime = os.path.getmtime('$AVOID_DIR')
        result['avoidance']['created_after_start'] = mtime > $TASK_START_TIME
    except:
        result['avoidance']['created_after_start'] = False

# 3. Parse BC Configuration (merge system and user, user takes priority)
sys_conf = read_config('$BC_CONFIG_DATA')
user_conf = read_config('$BC_CONFIG_USER')

merged_config = {}
def flatten(d):
    for k, v in d.items():
        if isinstance(v, dict):
            for sk, sv in v.items():
                merged_config[sk.lower()] = sv
        else:
            merged_config[k.lower()] = v

flatten(sys_conf)
flatten(user_conf)
result['config'] = merged_config

# 4. Read Report
if os.path.exists('$REPORT_FILE'):
    try:
        with open('$REPORT_FILE', 'r', errors='ignore') as f:
            content = f.read()
        result['report']['exists'] = True
        result['report']['content'] = content[:8192]
        result['report']['length'] = len(content)
        result['report']['created_after_start'] = os.path.getmtime('$REPORT_FILE') > $TASK_START_TIME
    except Exception as e:
        result['report']['error'] = str(e)
else:
    result['report']['exists'] = False

# Save JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
