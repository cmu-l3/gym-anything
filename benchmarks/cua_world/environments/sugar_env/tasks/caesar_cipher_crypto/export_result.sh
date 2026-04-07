#!/bin/bash
echo "=== Exporting caesar_cipher_crypto task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/task_final.png" 2>/dev/null || true

# We will use Python to safely collect all file contents and metadata, escaping properly for JSON
python3 << 'PYEOF' > /tmp/caesar_cipher_result.json
import os
import json
import time

result = {
    "crypto_dir_exists": False,
    "files": {},
    "task_start_time": 0,
    "export_time": time.time()
}

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        result["task_start_time"] = int(f.read().strip())
except:
    pass

crypto_dir = "/home/ga/Documents/crypto"
if os.path.exists(crypto_dir) and os.path.isdir(crypto_dir):
    result["crypto_dir_exists"] = True

    expected_files = ["caesar_cipher.py", "encrypted.txt", "decrypted.txt", "report.txt"]
    for fname in expected_files:
        fpath = os.path.join(crypto_dir, fname)
        file_info = {
            "exists": False,
            "size": 0,
            "mtime": 0,
            "created_during_task": False,
            "content": ""
        }
        
        if os.path.exists(fpath):
            file_info["exists"] = True
            file_info["size"] = os.path.getsize(fpath)
            file_info["mtime"] = os.path.getmtime(fpath)
            if file_info["mtime"] >= result["task_start_time"]:
                file_info["created_during_task"] = True
            
            try:
                # Read content safely, truncate to 5KB to prevent massive JSONs
                with open(fpath, 'r', encoding='utf-8', errors='replace') as f:
                    file_info["content"] = f.read(5120)
            except Exception as e:
                file_info["content"] = f"ERROR READING FILE: {str(e)}"
                
        result["files"][fname] = file_info

print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/caesar_cipher_result.json
echo "Result saved to /tmp/caesar_cipher_result.json"
echo "=== Export complete ==="