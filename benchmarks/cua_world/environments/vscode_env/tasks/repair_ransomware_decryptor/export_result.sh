#!/bin/bash
set -e

echo "=== Exporting Repair Ransomware Decryptor Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# Save any open files in VSCode
focus_vscode_window 2>/dev/null || true
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 1

# Generate the result JSON via Python
python3 << 'PYEXPORT'
import json
import os
import hashlib

def hash_file(path):
    with open(path, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest()

result = {
    'decryptor_code': '',
    'recovered_files': {},
    'ground_truth': {}
}

# Export the modified script
try:
    with open("/home/ga/workspace/ransomware_recovery/decryptor.py", "r") as f:
        result['decryptor_code'] = f.read()
except Exception as e:
    result['decryptor_code'] = f"ERROR: {e}"

# Hash all ground truth files
gt_dir = "/var/lib/app/ground_truth"
for root, _, files in os.walk(gt_dir):
    for file in files:
        rel = os.path.relpath(os.path.join(root, file), gt_dir)
        result['ground_truth'][rel] = hash_file(os.path.join(root, file))

# Hash all recovered files (files without .crypt26 extension)
rec_dir = "/home/ga/workspace/ransomware_recovery/infected_drive"
for root, _, files in os.walk(rec_dir):
    for file in files:
        if not file.endswith('.crypt26'):
            rel = os.path.relpath(os.path.join(root, file), rec_dir)
            result['recovered_files'][rel] = hash_file(os.path.join(root, file))

# Save to temp file
with open("/tmp/ransomware_result.tmp.json", "w") as f:
    json.dump(result, f, indent=2)
PYEXPORT

# Safely move JSON to final location
mv /tmp/ransomware_result.tmp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Saved to /tmp/task_result.json"