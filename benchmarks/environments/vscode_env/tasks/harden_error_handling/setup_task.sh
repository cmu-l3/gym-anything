#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Error Handling Task ==="

WORKSPACE_DIR="/home/ga/workspace/data_pipeline"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create requirements.txt
cat > "$WORKSPACE_DIR/requirements.txt" << 'EOF'
requests>=2.28.0
EOF

# Install requirements as ga user
echo "Installing Python requirements..."
sudo -u ga pip3 install --user --quiet requests 2>/dev/null || true

# Create the fragile Python script (NO error handling)
cat > "$WORKSPACE_DIR/fetch_data.py" << 'EOF'
#!/usr/bin/env python3
"""
Data fetching script - FRAGILE VERSION
This script fetches data from multiple sources and processes it.
Currently has NO error handling and crashes on any failure.
"""

import requests
import json
import os

def fetch_weather_data(city):
    """Fetch weather data from API - NO ERROR HANDLING"""
    url = f"https://api.weather.example.com/current?city={city}"
    response = requests.get(url, timeout=5)
    data = response.json()
    return data['main']['temp']  # Crashes if keys missing

def fetch_user_data(user_id):
    """Fetch user profile - NO ERROR HANDLING"""
    url = f"https://api.users.example.com/profile/{user_id}"
    response = requests.get(url, timeout=5)
    data = response.json()
    email = data['contact']['email']  # Crashes on KeyError
    return email

def load_config(filepath):
    """Load configuration file - NO ERROR HANDLING"""
    with open(filepath, 'r') as f:
        config = json.load(f)
    return config['settings']['api_key']  # Crashes if file missing or malformed

def save_results(filepath, data):
    """Save results to file - NO ERROR HANDLING"""
    with open(filepath, 'w') as f:
        json.dump(data, f, indent=2)
    print(f"Saved results to {filepath}")

def process_data_source(source_name, fetch_func, *args):
    """Process a single data source - NO ERROR HANDLING"""
    print(f"Processing {source_name}...")
    result = fetch_func(*args)
    print(f"✓ {source_name}: {result}")
    return result

def main():
    """Main function - NO ERROR HANDLING"""
    print("=== Data Pipeline Starting ===")
    
    results = {}
    
    # Fetch data from multiple sources (all will crash on failure)
    results['weather'] = process_data_source(
        "Weather API",
        fetch_weather_data,
        "London"
    )
    
    results['user_email'] = process_data_source(
        "User API", 
        fetch_user_data,
        12345
    )
    
    results['config'] = process_data_source(
        "Config File",
        load_config,
        "/tmp/config.json"
    )
    
    # Save results (crashes if permission denied)
    output_path = "/tmp/pipeline_results.json"
    save_results(output_path, results)
    
    print("=== Pipeline Complete ===")
    print(f"Processed {len(results)} data sources successfully")

if __name__ == '__main__':
    main()
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Create a sample config file for testing (optional)
cat > /tmp/config.json << 'EOF'
{
  "settings": {
    "api_key": "test_key_12345"
  }
}
EOF
sudo chown ga:ga /tmp/config.json

echo "Opening VSCode with the fragile script..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/fetch_data.py'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Error Handling Task Setup Complete ==="
echo "📝 Instructions:"
echo "  File to modify: /home/ga/workspace/data_pipeline/fetch_data.py"
echo ""
echo "  Add error handling for:"
echo "    • API calls (requests.get) - catch requests.RequestException, ConnectionError, Timeout"
echo "    • File operations (open) - catch FileNotFoundError, IOError, PermissionError"  
echo "    • JSON parsing (json.load, json.loads) - catch json.JSONDecodeError"
echo "    • Dictionary access - use .get() or handle KeyError"
echo ""
echo "  Requirements:"
echo "    • Add 'import logging' and configure logger"
echo "    • Use specific exception types (NO bare except:)"
echo "    • Include context in error messages (URLs, file paths)"
echo "    • Make script handle partial failures gracefully"
echo "    • Save file with Ctrl+S when done"