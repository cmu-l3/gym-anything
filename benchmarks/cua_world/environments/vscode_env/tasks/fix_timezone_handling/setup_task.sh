#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fix Timezone Handling Task ==="

WORKSPACE_DIR="/home/ga/workspace/scheduler_app"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create buggy scheduler.py file
cat > "$WORKSPACE_DIR/scheduler.py" << 'EOF'
from datetime import datetime
import models

def create_appointment(user_id, title, scheduled_time):
    """Create a new appointment"""
    appointment = {
        'user_id': user_id,
        'title': title,
        'scheduled_time': scheduled_time,
        'created_at': datetime.now()  # BUG: Naive datetime!
    }
    return models.save_appointment(appointment)

def get_upcoming_appointments(user_id):
    """Get user's upcoming appointments"""
    all_appointments = models.get_appointments(user_id)
    current_time = datetime.now()  # BUG: Naive datetime!
    
    upcoming = [
        apt for apt in all_appointments 
        if apt['scheduled_time'] > current_time
    ]
    return upcoming

def is_past_due(appointment):
    """Check if appointment is in the past"""
    return appointment['scheduled_time'] < datetime.now()  # BUG: Naive!

def format_appointment(appointment):
    """Format appointment for display"""
    return f"{appointment['title']} at {appointment['scheduled_time']}"
EOF

# Create buggy models.py file
cat > "$WORKSPACE_DIR/models.py" << 'EOF'
from datetime import datetime

def save_appointment(appointment_data):
    """Save appointment to database (mock)"""
    # BUG: Should ensure UTC before storage
    appointment_data['stored_at'] = datetime.now()
    
    # Mock database save
    print(f"Saving appointment: {appointment_data['title']}")
    return appointment_data

def get_appointments(user_id):
    """Retrieve appointments (mock)"""
    # Mock data return
    return []

def delete_appointment(appointment_id):
    """Delete an appointment"""
    print(f"Deleting appointment: {appointment_id}")
    return True
EOF

# Create utils.py (helper file, no bugs here)
cat > "$WORKSPACE_DIR/utils.py" << 'EOF'
"""Utility functions for scheduler app"""

def validate_time_format(time_str):
    """Validate time string format"""
    # Helper function - no timezone issues here
    return True

def format_duration(minutes):
    """Format duration in minutes to human readable"""
    hours = minutes // 60
    mins = minutes % 60
    return f"{hours}h {mins}m"
EOF

# Create config.py
cat > "$WORKSPACE_DIR/config.py" << 'EOF'
"""Configuration settings"""

DATABASE_URL = "sqlite:///scheduler.db"
DEFAULT_TIMEZONE = "UTC"
APP_NAME = "Appointment Scheduler"
EOF

# Create requirements.txt
cat > "$WORKSPACE_DIR/requirements.txt" << 'EOF'
python-dateutil==2.8.2
pytz==2023.3
EOF

# Create README for the app
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Appointment Scheduler

A simple scheduling application with timezone handling.

## Known Issues

- Timezone bugs causing incorrect time displays
- Naive datetime usage in scheduler.py and models.py
- Need to convert to timezone-aware datetime objects
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/scheduler.py'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Fix Timezone Handling Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Use Find in Files (Ctrl+Shift+F) to search for 'datetime.now()'"
echo "  2. Examine scheduler.py and models.py for timezone bugs"
echo "  3. Add 'from datetime import timezone' import"
echo "  4. Replace datetime.now() with datetime.now(timezone.utc)"
echo "  5. Fix at least 3 instances in critical functions"
echo "  6. Save all files (Ctrl+S or Ctrl+K S)"