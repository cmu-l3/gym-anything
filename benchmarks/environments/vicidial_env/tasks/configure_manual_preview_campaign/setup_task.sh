#!/bin/bash
set -e
echo "=== Setting up Configure Manual Preview Campaign task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure Vicidial services are up
vicidial_ensure_running

# 1. Database Setup: Reset Campaign VIP_DIAL
# We drop it and recreate it with defaults (RATIO method, no preview) to ensure the agent has work to do.
echo "Resetting campaign VIP_DIAL..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_campaigns WHERE campaign_id='VIP_DIAL';"
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "INSERT INTO vicidial_campaigns (campaign_id, campaign_name, active, dial_method, auto_dial_level, lead_order, dial_statuses) VALUES ('VIP_DIAL', 'VIP Senator Outreach', 'Y', 'RATIO', '1.0', 'RANDOM', 'NEW');"

# 2. Database Setup: Clear List 9500 (Target List)
# Ensure it doesn't exist so the agent has to create/init it.
echo "Clearing list 9500..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_list WHERE list_id='9500';"
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_lists WHERE list_id='9500';"

# 3. Data Preparation: Create the "Vendor" CSV file
# We take the standard asset and rename headers/columns to force manual mapping.
SOURCE_CSV="/home/ga/Documents/VicidialData/us_senators_vicidial_leads_2026-02-14.csv"
TARGET_CSV="/home/ga/Documents/VicidialData/vendor_senators_vip.csv"
mkdir -p "$(dirname "$TARGET_CSV")"

# Ensure source exists (from env setup)
if [ ! -f "$SOURCE_CSV" ]; then
    echo "WARNING: Source data $SOURCE_CSV not found! Creating dummy data."
    # Create dummy source if asset missing (fallback)
    echo "phone_number,first_name,last_name,state" > "$SOURCE_CSV"
    echo "2025550101,John,Doe,NY" >> "$SOURCE_CSV"
fi

echo "Generating vendor CSV file..."
# Python script to transform the CSV
cat <<EOF | python3
import csv
import sys
import os

source_path = "$SOURCE_CSV"
target_path = "$TARGET_CSV"

try:
    with open(source_path, 'r', encoding='utf-8', errors='ignore') as fin, open(target_path, 'w', encoding='utf-8', newline='') as fout:
        reader = csv.reader(fin)
        writer = csv.writer(fout)
        
        # Write custom vendor header
        writer.writerow(['Gov_ID', 'Official_Name', 'Contact_Number', 'Home_State'])
        
        # Read header from source
        headers = next(reader, None)
        if not headers:
            sys.exit(0)
            
        # Find indices (flexible logic)
        try:
            # Try to find columns by name
            idx_phone = headers.index('phone_number')
            idx_first = headers.index('first_name')
            idx_last = headers.index('last_name')
            idx_state = headers.index('state')
        except ValueError:
            # Fallback for simple CSV or if headers don't match expectation
            # Assuming standard Vicidial export: 11=phone, 13=first, 15=last, 20=state (0-indexed)
            # Or if it's the simple dummy file created above: 0, 1, 2, 3
            if len(headers) == 4:
                 idx_phone, idx_first, idx_last, idx_state = 0, 1, 2, 3
            else:
                 # Default fallback
                 idx_phone, idx_first, idx_last, idx_state = 11, 13, 15, 20

        count = 0
        for i, row in enumerate(reader):
            if count >= 100: break # Limit to 100 for speed
            
            # Safe access
            if len(row) <= max(idx_phone, idx_first, idx_last, idx_state): continue
            
            p_num = row[idx_phone]
            if not p_num: continue
            
            f_name = row[idx_first]
            l_name = row[idx_last]
            full_name = f"{f_name} {l_name}".strip()
            
            state = row[idx_state]
            
            # Generate a fake Gov ID
            gov_id = f"SEN-{i+1000}"
            
            writer.writerow([gov_id, full_name, p_num, state])
            count += 1
            
    print(f"Created vendor CSV successfully with {count} records.")
except Exception as e:
    print(f"Error processing CSV: {e}")
    # Create simple fallback if python fails
    with open(target_path, 'w') as f:
        f.write("Gov_ID,Official_Name,Contact_Number,Home_State\n")
        f.write("SEN-1001,Test Senator,2025550199,DC\n")
EOF

chown ga:ga "$TARGET_CSV"

# 4. Standard App Launch
echo "Launching Firefox..."
pkill -f firefox 2>/dev/null || true

# Pre-auth via URL params if possible, or just go to admin
# Using xdotool to login in setup to ensure clean start state
su - ga -c "DISPLAY=:1 firefox 'http://localhost/vicidial/admin.php' > /dev/null 2>&1 &"

# Wait for window
wait_for_window "firefox\|mozilla\|vicidial" 30

# Maximize
maximize_active_window

# Login automation (Vicidial default: 6666/andromeda)
echo "Logging in..."
sleep 3
DISPLAY=:1 xdotool type "6666"
sleep 0.5
DISPLAY=:1 xdotool key Tab
sleep 0.5
DISPLAY=:1 xdotool type "andromeda"
sleep 0.5
DISPLAY=:1 xdotool key Return
sleep 5

# Navigate to Campaign screen to start (helpful context)
navigate_to_url "http://localhost/vicidial/admin.php?ADD=10"

# Record start time
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_list_count.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="