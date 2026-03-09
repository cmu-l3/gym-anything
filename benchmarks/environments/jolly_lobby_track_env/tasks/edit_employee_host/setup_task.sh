#!/bin/bash
echo "=== Setting up edit_employee_host task ==="

source /workspace/scripts/task_utils.sh

# 1. Record start time
date +%s > /tmp/task_start_time.txt

# 2. Launch Lobby Track and wait for it
launch_lobbytrack
sleep 5

# 3. Automate Data Entry (Create the initial "Sarah Mitchell" record)
# We need to navigate to the Host/Employee section and add the record.
# Assuming keyboard navigation:
# - Alt+d (Database) -> H (Hosts) or similar, or Ctrl+Shift+H if available.
# Since we don't know exact shortcuts, we'll try standard navigation.

echo "Populating initial host record..."

# Focus window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "lobby" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    sleep 1

    # Navigate to Database > People (Hosts usually under People/Database)
    # We'll try a sequence to open the Add Person dialog.
    # Often Ctrl+N or clicking "Add".
    # Blind attempt to reach "Add" via Tab or accelerators.
    
    # Send Alt to focus menu, then arrow keys/enter if needed.
    # But Lobby Track often has a big "Add" button on the toolbar.
    
    # We will try to simulate a user adding a person.
    # Note: If this is too fragile, we might just assume the agent
    # starts with the app open and we rely on the DB file being pre-seeded
    # by the install script (which copies /workspace/data).
    #
    # However, to be safe and ensure the record exists, we'll try to add it.
    
    # Attempt to open "Add Person" dialog
    # Try Ctrl+N
    DISPLAY=:1 xdotool key ctrl+n
    sleep 2
    
    # Type Name: Sarah
    DISPLAY=:1 xdotool type "Sarah"
    DISPLAY=:1 xdotool key Tab
    # Type Last: Mitchell
    DISPLAY=:1 xdotool type "Mitchell"
    DISPLAY=:1 xdotool key Tab
    
    # Skip optional fields to get to Dept/Phone/Email
    # We'll tab through fields. This depends on tab order.
    # Assuming: First -> Middle -> Last -> Title -> Company -> Dept
    
    # Tab 3 times to get past Middle/Title/Company (adjust as needed)
    DISPLAY=:1 xdotool key Tab Tab Tab
    
    # Department: Marketing
    DISPLAY=:1 xdotool type "Marketing"
    DISPLAY=:1 xdotool key Tab
    
    # Phone: 555-123-4567
    DISPLAY=:1 xdotool type "555-123-4567"
    DISPLAY=:1 xdotool key Tab
    
    # Email: sarah.mitchell@marketing.example.com
    DISPLAY=:1 xdotool type "sarah.mitchell@marketing.example.com"
    
    sleep 1
    # Save (Enter or Ctrl+S)
    DISPLAY=:1 xdotool key Return
    sleep 2
    
    # Close any confirmation dialogs (Esc)
    DISPLAY=:1 xdotool key Escape
    sleep 1
    
    # Return to main screen (Esc closes dialogs/windows often)
    DISPLAY=:1 xdotool key Escape
    sleep 1
fi

# 4. Identify the Database File
# We look for the main DB file to track changes.
DB_FILE=$(find /home/ga/.wine/drive_c -name "*.mdb" -o -name "*.sdf" 2>/dev/null | head -1)
if [ -n "$DB_FILE" ]; then
    echo "Database found: $DB_FILE"
    echo "$DB_FILE" > /tmp/db_location.txt
    
    # Record initial hash/timestamp
    md5sum "$DB_FILE" > /tmp/initial_db_hash.txt
    stat -c %Y "$DB_FILE" > /tmp/initial_db_mtime.txt
else
    echo "WARNING: No database file found automatically."
fi

# 5. Capture Initial State
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="