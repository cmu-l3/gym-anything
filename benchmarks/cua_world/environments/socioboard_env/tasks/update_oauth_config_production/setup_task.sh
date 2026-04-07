#!/bin/bash
echo "=== Setting up update_oauth_config_production task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure the Socioboard config files are strictly set to the "local/staging" baseline
# This prevents pre-existing configuration from causing false positives
echo "Injecting baseline local/staging configuration..."

python3 << 'PYEOF'
import json
import os

services = ['user', 'feeds', 'publish', 'notification']
base_dir = '/opt/socioboard/socioboard-api/'

def enforce_baseline(obj, svc_name):
    if isinstance(obj, dict):
        for k, v in obj.items():
            if isinstance(v, str):
                key_lower = k.lower()
                # Target URL fields (callback URLs, redirect URLs)
                if 'url' in key_lower or 'callback' in key_lower or 'redirect' in key_lower:
                    if 'app.socioboard.com' in v:
                        obj[k] = v.replace('https://app.socioboard.com', 'http://localhost:3000')
                    elif v.startswith('/') and 'callback' in v:
                        # Some might be relative, ensure they are absolute for the test if needed
                        pass
            else:
                enforce_baseline(v, svc_name)
    elif isinstance(obj, list):
        for item in obj:
            enforce_baseline(item, svc_name)

for svc in services:
    path = os.path.join(base_dir, svc, 'config', 'development.json')
    if os.path.exists(path):
        try:
            with open(path, 'r') as f:
                data = json.load(f)
            
            enforce_baseline(data, svc)
            
            # Specifically inject the dummy Google client ID in the user service
            if svc == 'user':
                if 'google_api' not in data:
                    data['google_api'] = {}
                data['google_api']['client_id'] = 'dummy-staging-client-id.apps.googleusercontent.com'
                if 'redirect_url' not in data['google_api']:
                    data['google_api']['redirect_url'] = 'http://localhost:3000/v1/auth/google/callback'
                else:
                    data['google_api']['redirect_url'] = 'http://localhost:3000/v1/auth/google/callback'

            with open(path, 'w') as f:
                json.dump(data, f, indent=4)
            print(f"Successfully configured baseline for {svc}")
        except Exception as e:
            print(f"Error configuring baseline for {svc}: {e}")
PYEOF

# Fix permissions
chown -R ga:ga /opt/socioboard/socioboard-api/*/config/development.json 2>/dev/null || true

# Open a terminal in the target directory for the agent
su - ga -c "DISPLAY=:1 x-terminal-emulator --working-directory=/opt/socioboard/socioboard-api/ &"
sleep 2

# Maximize and focus the terminal
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take an initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="