#!/bin/bash
echo "=== Setting up Configure Corridor Mode task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Refresh auth token to ensure API access
refresh_nx_token > /dev/null 2>&1 || true

echo "Identifying target cameras..."
# We need to map Original Names to IDs so we can verify them later even if names change
# Create a JSON map: {"Server Room Camera": "uuid1", "Entrance Camera": "uuid2", ...}

# Reset any previous runs (idempotency)
# We will iterate through all devices, reset rotation to 0, and remove [Corridor] from names
ALL_DEVICES=$(nx_api_get "/rest/v1/devices")

# Parse and reset
echo "$ALL_DEVICES" | python3 -c "
import sys, json, subprocess

def reset_camera(cam):
    cam_id = cam.get('id')
    name = cam.get('name', '')
    
    # Needs reset if rotation != 0 or name has [Corridor]
    needs_update = False
    
    # Check parameters
    params = cam.get('parameters', {})
    rotation = params.get('rotation', '0')
    
    new_name = name.replace(' [Corridor]', '')
    
    if rotation != '0' or new_name != name:
        print(f'Resetting camera: {name} ({cam_id})')
        # Construct patch data
        data = {
            'name': new_name,
            'parameters': {
                'rotation': '0'
            }
        }
        # Call API via subprocess to avoid complex bash quoting
        subprocess.run([
            'curl', '-sk', '-X', 'PATCH', 
            f'https://localhost:7001/rest/v1/devices/{cam_id}',
            '-H', f'Authorization: Bearer {sys.argv[1]}',
            '-H', 'Content-Type: application/json',
            '-d', json.dumps(data)
        ])

try:
    token = '$(cat /home/ga/nx_token.txt)'
    devices = json.load(sys.stdin)
    for d in devices:
        reset_camera(d)
except Exception as e:
    print(f'Error resetting cameras: {e}')
" "$(cat /home/ga/nx_token.txt)"

sleep 2

# Now capture the 'Clean' initial state mapping
echo "Exporting initial camera mapping..."
nx_api_get "/rest/v1/devices" | python3 -c "
import sys, json
try:
    devices = json.load(sys.stdin)
    mapping = {}
    for d in devices:
        mapping[d.get('name')] = d.get('id')
    with open('/tmp/initial_camera_map.json', 'w') as f:
        json.dump(mapping, f, indent=2)
    print('Map saved to /tmp/initial_camera_map.json')
except:
    print('Failed to map cameras')
"

# Open Firefox to the Cameras Settings page
echo "Launching Firefox..."
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/cameras"
sleep 5
maximize_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="