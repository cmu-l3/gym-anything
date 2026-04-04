#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Extract Hardcoded Secrets Task ==="

WORKSPACE_DIR="/home/ga/workspace/weather_api_project"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Initialize Git repository
cd "$WORKSPACE_DIR"
if [ ! -d ".git" ]; then
    sudo -u ga git init
    sudo -u ga git config user.name "GA User"
    sudo -u ga git config user.email "ga@localhost"
fi

# Create main.py with hardcoded API key
cat > "$WORKSPACE_DIR/main.py" << 'EOF'
import requests
import json

# TODO: Move this to environment variable!
API_KEY = "sk_live_51HxKQp2eZvKliHJxN9mYfB3K"

def get_weather(city):
    """Fetch weather data for a given city"""
    url = f"https://api.weatherservice.com/v1/weather"
    headers = {
        "Authorization": f"Bearer {API_KEY}",
        "Content-Type": "application/json"
    }
    
    params = {"city": city, "units": "metric"}
    response = requests.get(url, headers=headers, params=params)
    
    if response.status_code == 200:
        return response.json()
    else:
        print(f"Error: {response.status_code}")
        return None

if __name__ == "__main__":
    weather = get_weather("San Francisco")
    if weather:
        print(json.dumps(weather, indent=2))
EOF

# Create requirements.txt
cat > "$WORKSPACE_DIR/requirements.txt" << 'EOF'
requests==2.31.0
python-dotenv==1.0.0
EOF

# Create .gitignore WITHOUT .env (this is the problem!)
cat > "$WORKSPACE_DIR/.gitignore" << 'EOF'
__pycache__/
*.pyc
*.pyo
.pytest_cache/
.coverage
EOF

# Set ownership
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Make initial commit
cd "$WORKSPACE_DIR"
sudo -u ga git add .
sudo -u ga git commit -m "Initial commit" || true

# Open VSCode to the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2

# Open main.py so the agent can see the hardcoded key
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/main.py'" || true
sleep 1

focus_vscode_window

echo "=== Extract Hardcoded Secrets Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Notice the hardcoded API_KEY in main.py (security issue!)"
echo "  2. Create .env file with: API_KEY=<the_key_value>"
echo "  3. Add .env to .gitignore to prevent committing secrets"
echo "  4. Refactor main.py to use os.getenv('API_KEY')"
echo "  5. Import load_dotenv and call it at the top of main.py"
echo "  6. Remove the hardcoded secret from main.py"
echo "  7. Save all files"