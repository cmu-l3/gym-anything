#!/bin/bash
echo "=== Exporting panoramic_visual_system_setup result ==="

CONFIG_DIR="/home/ga/Documents/config_deployment"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# We need to parse 3 INI files. We'll use a Python script to do this robustly
# and output a single JSON object.

python3 -c "
import configparser
import json
import os
import time

config_dir = '$CONFIG_DIR'
task_start = int('$TASK_START')
files = ['visual_left.ini', 'visual_center.ini', 'visual_right.ini']
result = {
    'files_found': {},
    'configs': {},
    'timestamps_valid': {}
}

for fname in files:
    fpath = os.path.join(config_dir, fname)
    if os.path.exists(fpath):
        result['files_found'][fname] = True
        
        # Check timestamp
        mtime = os.path.getmtime(fpath)
        result['timestamps_valid'][fname] = (mtime > task_start)
        
        # Parse INI
        # Bridge Command INI files sometimes don't have headers or use specific ones.
        # But usually they follow standard INI structure.
        # We'll use a loose parser or add a dummy header if missing, 
        # but standard bc5.ini has [Graphics], [Network] etc.
        try:
            parser = configparser.ConfigParser(strict=False)
            # Preserve case sensitivity if needed, though BC keys are usually lowercase
            try:
                parser.read(fpath)
            except configparser.MissingSectionHeaderError:
                # Fallback for headerless files
                with open(fpath, 'r') as f:
                    content = '[root]\n' + f.read()
                import io
                parser.read_file(io.StringIO(content))

            # Flatten config for easier verification
            cfg_flat = {}
            for section in parser.sections():
                for key, val in parser.items(section):
                    cfg_flat[key.lower()] = val
            
            result['configs'][fname] = cfg_flat
        except Exception as e:
            result['configs'][fname] = {'error': str(e)}
            
    else:
        result['files_found'][fname] = False
        result['timestamps_valid'][fname] = False

print(json.dumps(result, indent=2))
" > /tmp/task_result.json

# Copy to final location with permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json