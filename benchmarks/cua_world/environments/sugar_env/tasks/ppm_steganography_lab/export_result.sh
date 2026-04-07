#!/bin/bash
echo "=== Exporting PPM Steganography Task Result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/task_final.png" 2>/dev/null || true

# Execute verification payload which embeds a reference decoder and encodes a hidden dynamic phrase
python3 << 'PYEOF' > /tmp/task_result.json
import json
import subprocess
import os

task_start = 0
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start = int(f.read().strip())
except Exception:
    pass

result = {
    "encode_py_exists": os.path.exists("/home/ga/Documents/encode.py"),
    "decode_py_exists": os.path.exists("/home/ga/Documents/decode.py"),
    "stego_image_exists": os.path.exists("/home/ga/Documents/stego_image.ppm"),
    "stego_image_size": 0,
    "stego_created_during_task": False,
    "valid_header": False,
    "matching_token_count": False,
    "agent_encoded_string": "",
    "decoder_execution_success": False,
    "decoder_output": "",
    "error_log": ""
}

def decode(ppm_file):
    try:
        with open(ppm_file, 'r', errors='ignore') as f:
            tokens = f.read().split()
        if not tokens or tokens[0] != 'P3':
            return ""
        tokens = tokens[4:]
        
        bits = ""
        chars = []
        for t in tokens:
            try:
                val = int(t)
            except ValueError:
                continue
            bits += str(val & 1)
            if len(bits) == 8:
                char_val = int(bits, 2)
                if char_val == 0:
                    break
                chars.append(chr(char_val))
                bits = ""
                # Prevent runaway on missing null byte
                if len(chars) > 1000:
                    break
        return "".join(chars)
    except Exception as e:
        return f"ERROR: {e}"

def encode(ppm_file, out_file, text):
    with open(ppm_file, 'r') as f:
        tokens = f.read().split()
    
    header = tokens[:4]
    data = tokens[4:]
    
    bits = ""
    for char in text:
        bits += format(ord(char), '08b')
    bits += "00000000"
    
    for i in range(len(bits)):
        if i < len(data):
            try:
                val = int(data[i])
                bit = int(bits[i])
                val = (val & ~1) | bit
                data[i] = str(val)
            except ValueError:
                pass
        
    with open(out_file, 'w') as f:
        f.write(f"{header[0]}\n{header[1]} {header[2]}\n{header[3]}\n")
        # Write in chunks to keep reasonable line lengths
        for i in range(0, len(data), 15):
            f.write(" ".join(data[i:i+15]) + "\n")

if result["stego_image_exists"]:
    result["stego_image_size"] = os.path.getsize("/home/ga/Documents/stego_image.ppm")
    mtime = os.path.getmtime("/home/ga/Documents/stego_image.ppm")
    result["stego_created_during_task"] = (mtime >= task_start)
    
    try:
        with open("/home/ga/Documents/cover_image.ppm", "r") as f:
            cover_tokens = f.read().split()
        with open("/home/ga/Documents/stego_image.ppm", "r") as f:
            stego_tokens = f.read().split()
        
        if len(stego_tokens) >= 4 and stego_tokens[0] == 'P3':
            result["valid_header"] = (stego_tokens[:4] == cover_tokens[:4])
        
        result["matching_token_count"] = (len(stego_tokens) == len(cover_tokens))
        result["agent_encoded_string"] = decode("/home/ga/Documents/stego_image.ppm")
    except Exception as e:
        result["error_log"] += f"Error checking stego image: {e}\n"

if result["decode_py_exists"]:
    try:
        # Dynamically evaluate agent's decoder with a fresh stego image
        encode("/home/ga/Documents/cover_image.ppm", "/tmp/test_stego.ppm", "VERIFICATION_SECRET_123")
        proc = subprocess.run(["python3", "/home/ga/Documents/decode.py", "/tmp/test_stego.ppm"], 
                              capture_output=True, text=True, timeout=10)
        result["decoder_execution_success"] = (proc.returncode == 0)
        result["decoder_output"] = proc.stdout.strip() if proc.stdout.strip() else proc.stderr.strip()
    except subprocess.TimeoutExpired:
        result["decoder_output"] = "EXECUTION ERROR: Timeout"
    except Exception as e:
        result["decoder_output"] = f"EXECUTION ERROR: {e}"

print(json.dumps(result))
PYEOF

chmod 666 /tmp/task_result.json
echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="