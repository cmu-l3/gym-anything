#!/bin/bash
echo "=== Exporting Progressive Training Suite Results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Python Script to Parse INI files and Generate JSON
# We use Python here because bash parsing of multiple INI files is fragile.
# This script inspects the file system and bc5.ini config.

cat > /tmp/parser.py << 'EOF'
import os
import json
import re
import glob

def parse_ini(filepath):
    """Parses a Bridge Command INI file into a dictionary."""
    data = {}
    if not os.path.exists(filepath):
        return None
    
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        current_section = None
        for line in f:
            line = line.strip()
            if not line or line.startswith(';'):
                continue
            
            # Handle sections
            if line.startswith('[') and line.endswith(']'):
                current_section = line[1:-1]
                continue
            
            # Handle key=value
            if '=' in line:
                key, val = line.split('=', 1)
                key = key.strip().lower()
                val = val.strip().strip('"')
                
                # Simple type inference
                try:
                    if '.' in val:
                        val = float(val)
                    else:
                        val = int(val)
                except ValueError:
                    pass # Keep as string
                
                if current_section:
                    if current_section not in data:
                        data[current_section] = {}
                    data[current_section][key] = val
                else:
                    data[key] = val
                    
    return data

def parse_othership(filepath):
    """Parses othership.ini which uses indexed keys (Type(1)=...)."""
    if not os.path.exists(filepath):
        return None
    
    ships = {}
    count = 0
    
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            line = line.strip()
            if '=' not in line: continue
            
            key, val = line.split('=', 1)
            key = key.strip()
            val = val.strip().strip('"')
            
            if key.lower() == 'number':
                try:
                    count = int(val)
                except:
                    count = 0
                continue
                
            # Parse Type(1)=...
            match = re.match(r'([A-Za-z]+)\((\d+)(?:,\s*(\d+))?\)', key)
            if match:
                prop = match.group(1).lower()
                ship_idx = int(match.group(2))
                leg_idx = match.group(3)
                
                if ship_idx not in ships:
                    ships[ship_idx] = {'legs': []}
                
                if leg_idx:
                    # It's leg data (Bearing(1,1)=...)
                    leg_idx = int(leg_idx)
                    # Ensure leg list is long enough
                    while len(ships[ship_idx]['legs']) < leg_idx:
                        ships[ship_idx]['legs'].append({})
                    ships[ship_idx]['legs'][leg_idx-1][prop] = val
                else:
                    # Ship property
                    ships[ship_idx][prop] = val

    return {'count': count, 'ships': ships}

def get_file_timestamp(filepath):
    try:
        return os.path.getmtime(filepath)
    except:
        return 0

results = {
    'scenarios': {},
    'config': {},
    'syllabus': {},
    'task_meta': {}
}

# --- 1. Parse Scenarios ---
base_dir = "/opt/bridgecommand/Scenarios"
target_dirs = {
    'L1': "p) Cadet Module L1 Familiarisation",
    'L2': "q) Cadet Module L2 Night Traffic",
    'L3': "r) Cadet Module L3 Restricted Vis"
}

for level, dirname in target_dirs.items():
    full_path = os.path.join(base_dir, dirname)
    exists = os.path.isdir(full_path)
    
    scenario_data = {
        'exists': exists,
        'environment': None,
        'ownship': None,
        'othership': None,
        'files_timestamp': 0
    }
    
    if exists:
        env_path = os.path.join(full_path, 'environment.ini')
        own_path = os.path.join(full_path, 'ownship.ini')
        other_path = os.path.join(full_path, 'othership.ini')
        
        scenario_data['environment'] = parse_ini(env_path)
        scenario_data['ownship'] = parse_ini(own_path)
        scenario_data['othership'] = parse_othership(other_path)
        
        # Get max timestamp to check against task start
        ts = max(
            get_file_timestamp(env_path),
            get_file_timestamp(own_path),
            get_file_timestamp(other_path)
        )
        scenario_data['files_timestamp'] = ts

    results['scenarios'][level] = scenario_data

# --- 2. Parse Config (bc5.ini) ---
# Check both user config and global config locations
config_locations = [
    "/home/ga/.config/Bridge Command/bc5.ini",
    "/opt/bridgecommand/bc5.ini"
]

final_config = {}
for loc in config_locations:
    conf = parse_ini(loc)
    if conf:
        # Merge, preferring later entries if duplicates (though list order prioritizes user)
        # Actually usually user config overrides global.
        # We'll just take the first valid one found for simplicity or merge.
        # Let's merge: Global first, then User overrides.
        pass 

# Since we want to verify the FINAL state, we check the user config primarily.
user_conf = parse_ini(config_locations[0])
if user_conf:
    final_config = user_conf
else:
    final_config = parse_ini(config_locations[1]) or {}

# Flatten config for easier checking (handle sections)
flat_config = {}
for k, v in final_config.items():
    if isinstance(v, dict):
        for sub_k, sub_v in v.items():
            flat_config[sub_k] = sub_v
    else:
        flat_config[k] = v

results['config'] = flat_config

# --- 3. Parse Syllabus ---
syllabus_path = "/home/ga/Documents/cadet_module_syllabus.txt"
if os.path.exists(syllabus_path):
    with open(syllabus_path, 'r', errors='ignore') as f:
        content = f.read()
        word_count = len(content.split())
        results['syllabus'] = {
            'exists': True,
            'word_count': word_count,
            'content_snippet': content[:1000],  # First 1000 chars for regex check
            'timestamp': os.path.getmtime(syllabus_path)
        }
else:
    results['syllabus'] = {'exists': False, 'word_count': 0}

# --- 4. Task Metadata ---
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        results['task_meta']['start_time'] = float(f.read().strip())
except:
    results['task_meta']['start_time'] = 0

print(json.dumps(results, indent=2))
EOF

# 3. Execute Parser
python3 /tmp/parser.py > /tmp/task_result.json

# 4. Display Result for Log
cat /tmp/task_result.json

echo "=== Export complete ==="