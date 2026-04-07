#!/bin/bash
echo "=== Exporting whisper_retention_policy_optimization result ==="

# Record task end timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 1. Export the storage-schemas.conf file from the container
docker cp graphite:/opt/graphite/conf/storage-schemas.conf /tmp/storage-schemas.conf.txt 2>/dev/null

# 2. Extract Whisper DB info via Python script executed inside the container
# This uses the official `whisper` library inside the container to get structural info
cat << 'PYSCRIPT' > /tmp/get_whisper_info.py
import whisper
import json
import os

paths = [
    "/opt/graphite/storage/whisper/servers/web_traffic/speed_sensor_1.wsp",
    "/opt/graphite/storage/whisper/servers/web_traffic/speed_sensor_2.wsp"
]
results = {}
for p in paths:
    basename = os.path.basename(p)
    if os.path.exists(p):
        try:
            info = whisper.info(p)
            results[basename] = info
        except Exception as e:
            results[basename] = {"error": str(e)}
    else:
        results[basename] = {"error": "not found"}

print(json.dumps(results))
PYSCRIPT

docker cp /tmp/get_whisper_info.py graphite:/tmp/get_whisper_info.py 2>/dev/null
WHISPER_INFO=$(docker exec graphite python3 /tmp/get_whisper_info.py 2>/dev/null || echo "{}")

# 3. Query the Render API to ensure historical data was preserved
# -24h ensures we look at data that existed before the agent started
DATA_1=$(curl -s "http://localhost/render?target=servers.web_traffic.speed_sensor_1&from=-24h&format=json" 2>/dev/null || echo "[]")
DATA_2=$(curl -s "http://localhost/render?target=servers.web_traffic.speed_sensor_2&from=-24h&format=json" 2>/dev/null || echo "[]")

# Create JSON result package
cat << EOF > /tmp/whisper_task_result.json
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "whisper_info": $WHISPER_INFO,
    "data_1": $DATA_1,
    "data_2": $DATA_2
}
EOF

# Fix permissions
chmod 666 /tmp/whisper_task_result.json
chmod 666 /tmp/storage-schemas.conf.txt

echo "Export package written to /tmp/whisper_task_result.json"
echo "=== Export complete ==="