#!/bin/bash
# setup_task.sh - Pre-task hook for autofill_profile_configuration
# Cleans existing autofill data and creates the source identity file

set -e
echo "=== Setting up Autofill Profile Configuration Task ==="

# Record task start time (Unix timestamp)
date +%s > /tmp/task_start_time.txt

# 1. Kill Edge to release database locks
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# 2. Clean existing Autofill Data (Web Data database)
# We want the agent to create a *new* profile, so we delete existing ones.
WEB_DATA_DB="/home/ga/.config/microsoft-edge/Default/Web Data"

if [ -f "$WEB_DATA_DB" ]; then
    echo "Cleaning existing autofill profiles..."
    # Copy to temp to avoid locking if edge somehow holds it (unlikely after kill)
    cp "$WEB_DATA_DB" /tmp/web_data_clean.db
    
    # Delete all rows from autofill_profiles
    sqlite3 /tmp/web_data_clean.db "DELETE FROM autofill_profiles;"
    sqlite3 /tmp/web_data_clean.db "DELETE FROM autofill_profile_names;"
    sqlite3 /tmp/web_data_clean.db "DELETE FROM autofill_profile_emails;"
    sqlite3 /tmp/web_data_clean.db "DELETE FROM autofill_profile_phones;"
    
    # Restore the cleaned DB
    cp /tmp/web_data_clean.db "$WEB_DATA_DB"
    rm /tmp/web_data_clean.db
    echo "Autofill database cleaned."
fi

# 3. Create the Identity Details file on Desktop
IDENTITY_FILE="/home/ga/Desktop/identity_details.txt"
cat > "$IDENTITY_FILE" << 'EOF'
IDENTITY FOR AUTOFILL CONFIGURATION
===================================

Please configure Microsoft Edge to use the following details for form autofill:

First Name: Jordan
Last Name: Rivera
Organization: Apex Logistics Solutions
Street Address: 4500 Harbour Pointe Blvd
City: Mukilteo
State: WA
Zip Code: 98275
Phone: 425-555-0199
Email: j.rivera@apexlogistics.test

Instructions:
1. Go to Settings > Personal info
2. Enable "Save and fill basic info"
3. Add a new Personal Info profile with these exact details.
EOF

chown ga:ga "$IDENTITY_FILE"
chmod 644 "$IDENTITY_FILE"
echo "Identity file created at $IDENTITY_FILE"

# 4. Launch Edge
echo "Launching Microsoft Edge..."
# Launch with specific flags to ensure clean test environment but ALLOW autofill features
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    --start-maximized \
    > /tmp/edge_launch.log 2>&1 &"

# Wait for Edge window
echo "Waiting for Edge window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "edge|microsoft"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
done

# Ensure window is focused and maximized
sleep 2
DISPLAY=:1 wmctrl -a "Microsoft Edge" 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Microsoft Edge" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Capture Initial State Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="