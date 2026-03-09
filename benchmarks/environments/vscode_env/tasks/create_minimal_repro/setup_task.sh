#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Minimal Reproduction Task ==="

WORKSPACE="/home/ga/workspace"
PROJECT_DIR="$WORKSPACE/myapp"

# Clean up any existing directories
sudo rm -rf "$PROJECT_DIR" "$WORKSPACE/bug-reproduction" 2>/dev/null || true

# Create main application directory with complex structure
sudo -u ga mkdir -p "$PROJECT_DIR"/{src,tests,config,data}

# Create a Python application with multiple files (simulating real complexity)
cat > "$PROJECT_DIR/src/main.py" << 'EOF'
import json
from datetime import datetime
from dateutil.parser import parse as parse_date
from utils import load_config, get_user_data
from validators import validate_timestamp

def process_user_events(user_id):
    """Main business logic for processing user events"""
    config = load_config()
    user_data = get_user_data(user_id)
    
    events = []
    for entry in user_data['events']:
        # This is where the bug manifests!
        # When parsing dates with timezone abbreviations, dateutil behaves unexpectedly
        event_time = parse_date("2024-01-15 14:30:00 PST")
        
        if validate_timestamp(event_time, config):
            events.append({
                'user': user_id,
                'timestamp': event_time.isoformat(),
                'data': entry
            })
    
    return events

if __name__ == "__main__":
    result = process_user_events(12345)
    print(json.dumps(result, indent=2))
EOF

cat > "$PROJECT_DIR/src/utils.py" << 'EOF'
import json
import os

def load_config():
    """Load application configuration"""
    config_path = os.path.join(os.path.dirname(__file__), '..', 'config', 'app.json')
    with open(config_path) as f:
        return json.load(f)

def get_user_data(user_id):
    """Fetch user data from database (simulated)"""
    return {
        'user_id': user_id,
        'events': [
            {'type': 'login', 'ip': '192.168.1.1'},
            {'type': 'action', 'details': 'clicked_button'},
        ]
    }
EOF

cat > "$PROJECT_DIR/src/validators.py" << 'EOF'
from datetime import datetime

def validate_timestamp(ts, config):
    """Validate timestamp is within acceptable range"""
    if not isinstance(ts, datetime):
        return False
    return ts.year >= config.get('min_year', 2020)
EOF

cat > "$PROJECT_DIR/config/app.json" << 'EOF'
{
    "min_year": 2020,
    "max_events": 1000,
    "timezone": "UTC"
}
EOF

cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
python-dateutil==2.8.2
pytz==2023.3
requests==2.31.0
flask==2.3.0
sqlalchemy==2.0.0
EOF

# Create __init__.py files to make it a proper package
touch "$PROJECT_DIR/src/__init__.py"

# Create a README with the discovered issue description
cat > "$PROJECT_DIR/README.md" << 'EOF'
# MyApp

Our main application with lots of features.

## Known Issue

We've discovered that when parsing dates with timezone abbreviations like "PST", 
the dateutil library produces unexpected results. See src/main.py line 15.

**TODO**: Create a minimal reproduction to report this to the dateutil maintainers.
The reproduction should be in a separate folder called 'bug-reproduction' in the workspace.
EOF

sudo chown -R ga:ga "$PROJECT_DIR"

# Initialize git repo (optional, makes it more realistic)
cd "$PROJECT_DIR"
sudo -u ga git init
sudo -u ga git config user.email "dev@example.com"
sudo -u ga git config user.name "Developer"
sudo -u ga git add .
sudo -u ga git commit -m "Initial commit with known dateutil bug" 2>/dev/null || true

# Create instructions file in workspace root
cat > "$WORKSPACE/INSTRUCTIONS.txt" << 'EOF'
TASK: Create Minimal Reproduction

You've discovered a bug in python-dateutil library. Your task is to create
a minimal reproducible example in: /home/ga/workspace/bug-reproduction

Your minimal reproduction must include:

1. repro.py - Single Python file (<20 lines) that:
   - Imports ONLY python-dateutil
   - Contains minimal code demonstrating the issue
   - Has a comment explaining unexpected behavior
   - Is executable: python repro.py

2. README.md - Must include sections:
   - "Steps to Reproduce" with exact commands
   - "Expected Behavior"
   - "Actual Behavior"
   - Python version and OS info

3. requirements.txt - Contains ONLY:
   - python-dateutil==2.8.2

The bug is in /home/ga/workspace/myapp/src/main.py around line 15
where dates with timezone abbreviations like 'PST' behave unexpectedly.

Strip away ALL unnecessary complexity while preserving the bug.
EOF

sudo chown ga:ga "$WORKSPACE/INSTRUCTIONS.txt"

# Install python-dateutil if not already installed
echo "Installing python-dateutil..."
sudo -u ga python3 -m pip install --user python-dateutil==2.8.2 pytz 2>/dev/null || true

# Open VSCode with workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE' '$PROJECT_DIR/src/main.py'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Create Minimal Reproduction Task Setup Complete ==="
echo "📝 Task: Extract the dateutil bug into /home/ga/workspace/bug-reproduction"
echo "   Required files: repro.py, README.md, requirements.txt"
echo "   See INSTRUCTIONS.txt for details"