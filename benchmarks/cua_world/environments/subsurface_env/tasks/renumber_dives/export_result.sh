#!/bin/bash
set -euo pipefail

echo "=== Exporting renumber_dives result ==="

export DISPLAY="${DISPLAY:-:1}"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Parse the final XML state and generate a JSON result file
python3 -c "
import xml.etree.ElementTree as ET
import json
import os

target_file = '/home/ga/Documents/dives.ssrf'
result = {
    'file_exists': False,
    'file_mtime': 0,
    'current_count': 0,
    'dive_numbers': [],
    'min_number': 0,
    'is_sequential': False,
    'all_ge_43': False
}

if os.path.exists(target_file):
    result['file_exists'] = True
    result['file_mtime'] = int(os.path.getmtime(target_file))
    try:
        tree = ET.parse(target_file)
        dives = tree.findall('.//dive')
        result['current_count'] = len(dives)
        
        numbers = []
        for d in dives:
            try:
                num = int(d.get('number', -1))
                if num != -1:
                    numbers.append(num)
            except:
                pass
        
        if numbers:
            numbers.sort()
            result['dive_numbers'] = numbers
            result['min_number'] = numbers[0]
            result['all_ge_43'] = all(n >= 43 for n in numbers)
            
            # Check if sequential (no gaps)
            is_seq = True
            for i in range(len(numbers) - 1):
                if numbers[i+1] != numbers[i] + 1:
                    is_seq = False
                    break
            result['is_sequential'] = is_seq
    except Exception as e:
        result['error'] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# Merge initial state data into the result for easy verification access
python3 -c "
import json
import os
try:
    with open('/tmp/task_result.json', 'r') as f:
        res = json.load(f)
    if os.path.exists('/tmp/initial_state.json'):
        with open('/tmp/initial_state.json', 'r') as f:
            init = json.load(f)
        res['initial_state'] = init
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(res, f)
except Exception as e:
    print('Merge error:', e)
"

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="