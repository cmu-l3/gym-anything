#!/bin/bash
echo "=== Exporting morse_code_translator result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Capture final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/task_final.png" 2>/dev/null || true

# Extract everything via a Python script to build a structured JSON report
python3 << 'PYEOF' > /tmp/task_result.json
import json
import os
import stat
import subprocess
import time

result = {
    "dir_exists": False,
    "reference_exists": False,
    "reference_size": 0,
    "reference_content": "",
    "encode_exists": False,
    "encode_size": 0,
    "encode_executable": False,
    "decode_exists": False,
    "decode_size": 0,
    "decode_executable": False,
    "encoded_output_content": "",
    "decoded_output_content": "",
    "roundtrip_output_content": "",
    "novel_encode_output": "",
    "novel_encode_success": False,
    "novel_decode_output": "",
    "novel_decode_success": False,
    "files_created_after_start": False,
    "error": None
}

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        start_time = int(f.read().strip())
except:
    start_time = 0

morse_dir = "/home/ga/Documents/morse"
ref_file = os.path.join(morse_dir, "morse_reference.txt")
encode_script = os.path.join(morse_dir, "encode.sh")
decode_script = os.path.join(morse_dir, "decode.sh")
encoded_out = os.path.join(morse_dir, "encoded_output.txt")
decoded_out = os.path.join(morse_dir, "decoded_output.txt")
roundtrip_out = os.path.join(morse_dir, "roundtrip_output.txt")

try:
    if os.path.isdir(morse_dir):
        result["dir_exists"] = True
        
        # Check Reference
        if os.path.exists(ref_file):
            result["reference_exists"] = True
            result["reference_size"] = os.path.getsize(ref_file)
            if os.path.getmtime(ref_file) >= start_time:
                result["files_created_after_start"] = True
            with open(ref_file, 'r', errors='ignore') as f:
                result["reference_content"] = f.read()[:5000] # Limit size
                
        # Check Encode Script
        if os.path.exists(encode_script):
            result["encode_exists"] = True
            result["encode_size"] = os.path.getsize(encode_script)
            st = os.stat(encode_script)
            result["encode_executable"] = bool(st.st_mode & stat.S_IXUSR)
            
        # Check Decode Script
        if os.path.exists(decode_script):
            result["decode_exists"] = True
            result["decode_size"] = os.path.getsize(decode_script)
            st = os.stat(decode_script)
            result["decode_executable"] = bool(st.st_mode & stat.S_IXUSR)

        # Read Static Outputs
        if os.path.exists(encoded_out):
            with open(encoded_out, 'r', errors='ignore') as f:
                result["encoded_output_content"] = f.read().strip()
                
        if os.path.exists(decoded_out):
            with open(decoded_out, 'r', errors='ignore') as f:
                result["decoded_output_content"] = f.read().strip()
                
        if os.path.exists(roundtrip_out):
            with open(roundtrip_out, 'r', errors='ignore') as f:
                result["roundtrip_output_content"] = f.read().strip()

        # Run Novel Tests
        # We run them securely via subprocess in the correct working directory
        if result["encode_exists"]:
            try:
                cmd = ["bash", "encode.sh", "TEST"] if not result["encode_executable"] else ["./encode.sh", "TEST"]
                proc = subprocess.run(cmd, cwd=morse_dir, capture_output=True, text=True, timeout=3)
                result["novel_encode_output"] = proc.stdout.strip()
                if proc.returncode == 0:
                    result["novel_encode_success"] = True
            except Exception as e:
                result["novel_encode_output"] = f"ERROR: {str(e)}"

        if result["decode_exists"]:
            try:
                cmd = ["bash", "decode.sh", "-.-. --- -.. ."] if not result["decode_executable"] else ["./decode.sh", "-.-. --- -.. ."]
                proc = subprocess.run(cmd, cwd=morse_dir, capture_output=True, text=True, timeout=3)
                result["novel_decode_output"] = proc.stdout.strip()
                if proc.returncode == 0:
                    result["novel_decode_success"] = True
            except Exception as e:
                result["novel_decode_output"] = f"ERROR: {str(e)}"

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

chmod 666 /tmp/task_result.json
echo "Result JSON saved."
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="