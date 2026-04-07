#!/bin/bash
echo "=== Exporting configure_fdsnws_serve_data result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Create a robust Python script to evaluate state and parse XML
cat << 'EOF' > /tmp/export_helper.py
import os
import json
import time
import subprocess
import urllib.request
import xml.etree.ElementTree as ET

SEISCOMP_ROOT = os.environ.get('SEISCOMP_ROOT', '/home/ga/seiscomp')
TEST_DIR = os.path.expanduser('~/fdsnws_test')
RESULT_FILE = '/tmp/task_result.json'

result = {}

# Get task start time
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        result['task_start'] = int(f.read().strip())
except:
    result['task_start'] = 0

# 1. Check Configuration File
cfg_path = os.path.join(SEISCOMP_ROOT, 'etc/fdsnws.cfg')
result['config_exists'] = os.path.exists(cfg_path)
result['config_serveEvent'] = False
result['config_serveStation'] = False
result['config_serveDataSelect'] = False
result['config_port'] = False

if result['config_exists']:
    with open(cfg_path, 'r') as f:
        content = f.read().replace(' ', '')
        result['config_serveEvent'] = 'serveEvent=true' in content or 'serveEvent=1' in content
        result['config_serveStation'] = 'serveStation=true' in content or 'serveStation=1' in content
        result['config_serveDataSelect'] = 'serveDataSelect=true' in content or 'serveDataSelect=1' in content
        result['config_port'] = 'port=8080' in content or '8080' in content

# 2. Check Service Status
try:
    env = os.environ.copy()
    env['SEISCOMP_ROOT'] = SEISCOMP_ROOT
    status_out = subprocess.check_output(
        ['su', '-', 'ga', '-c', f'SEISCOMP_ROOT={SEISCOMP_ROOT} {SEISCOMP_ROOT}/bin/seiscomp status fdsnws'],
        stderr=subprocess.STDOUT
    ).decode()
    result['service_running'] = 'is running' in status_out
except Exception as e:
    result['service_running'] = False

# 3. Live Endpoint Verification
try:
    req = urllib.request.urlopen('http://localhost:8080/fdsnws/dataselect/1/version', timeout=5)
    result['live_endpoint_200'] = req.getcode() == 200
except:
    result['live_endpoint_200'] = False

# 4. Analyze Downloaded Test Files
def analyze_file(filename):
    path = os.path.join(TEST_DIR, filename)
    exists = os.path.exists(path)
    mtime = os.path.getmtime(path) if exists else 0
    size = os.path.getsize(path) if exists else 0
    return {'exists': exists, 'mtime': mtime, 'size': size, 'path': path}

events = analyze_file('events.xml')
result['events_file'] = events
result['events_valid_quakeml'] = False
result['events_has_noto'] = False

if events['exists'] and events['size'] > 0:
    try:
        # Avoid full parsing to protect against giant files, just scan string
        with open(events['path'], 'r') as f:
            xml_str = f.read(100000).lower()
        if 'quakeml' in xml_str and 'event' in xml_str:
            result['events_valid_quakeml'] = True
        if '>7.' in xml_str or 'noto' in xml_str or 'japan' in xml_str:
            result['events_has_noto'] = True
    except:
        pass

stations = analyze_file('stations.xml')
result['stations_file'] = stations
result['stations_valid_stationxml'] = False
result['stations_has_ge'] = False

if stations['exists'] and stations['size'] > 0:
    try:
        with open(stations['path'], 'r') as f:
            xml_str = f.read(100000).lower()
        if 'fdsnstationxml' in xml_str or 'stationxml' in xml_str:
            result['stations_valid_stationxml'] = True
        if 'ge' in xml_str and 'network' in xml_str:
            result['stations_has_ge'] = True
    except:
        pass

dataselect = analyze_file('dataselect_version.txt')
result['dataselect_file'] = dataselect
result['dataselect_has_content'] = False

if dataselect['exists'] and dataselect['size'] > 0:
    with open(dataselect['path'], 'r') as f:
        result['dataselect_has_content'] = len(f.read().strip()) > 0

# Save output
with open(RESULT_FILE, 'w') as f:
    json.dump(result, f, indent=2)

EOF

python3 /tmp/export_helper.py

# Ensure correct permissions for the framework to read
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="