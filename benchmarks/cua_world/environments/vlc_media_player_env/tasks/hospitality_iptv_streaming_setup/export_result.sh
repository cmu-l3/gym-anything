#!/bin/bash
echo "=== Exporting task results ==="

# Give active streams a moment to initialize if the agent just started them
sleep 3

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run Python script to probe streams and check processes
cat > /tmp/probe_streams.py << 'EOF'
import os
import json
import subprocess

def probe_stream(url):
    try:
        # Probe the HTTP stream to verify transcoding actually worked
        cmd = ['ffprobe', '-v', 'error', '-show_format', '-show_streams', '-of', 'json', url]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        if res.returncode == 0:
            return json.loads(res.stdout)
        else:
            return {"error": "ffprobe returned non-zero", "stderr": res.stderr}
    except subprocess.TimeoutExpired:
        return {"error": "ffprobe timed out (stream might be unresponsive)"}
    except Exception as e:
        return {"error": str(e)}

def get_process_on_port(port):
    try:
        # Check ss first
        res = subprocess.run(['ss', '-tlnp'], capture_output=True, text=True)
        for line in res.stdout.split('\n'):
            if f":{port}" in line:
                return line
        
        # Fallback if ss doesn't show the name: check ps aux
        res2 = subprocess.run(['ps', 'aux'], capture_output=True, text=True)
        for line in res2.stdout.split('\n'):
            if 'vlc' in line.lower() and str(port) in line:
                return f"Fallback detected: vlc running with port {port} in command line"
    except Exception as e:
        return str(e)
    return ""

def read_file(path):
    if os.path.exists(path):
        try:
            with open(path, 'r') as f:
                return f.read()
        except:
            pass
    return ""

result = {
    "task_start": int(os.environ.get("TASK_START", 0)),
    "task_end": int(os.environ.get("TASK_END", 0)),
    "promo_probe": probe_stream("http://127.0.0.1:8080/promo"),
    "ambient_probe": probe_stream("http://127.0.0.1:8081/ambient"),
    "port_8080_proc": get_process_on_port(8080),
    "port_8081_proc": get_process_on_port(8081),
    "promo_script": read_file("/home/ga/Documents/start_promo.sh"),
    "ambient_script": read_file("/home/ga/Documents/start_ambient.sh"),
    "screenshot_exists": os.path.exists("/tmp/task_final.png")
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

export TASK_START
export TASK_END
python3 /tmp/probe_streams.py

# Ensure permissions so copy_from_env can grab it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="