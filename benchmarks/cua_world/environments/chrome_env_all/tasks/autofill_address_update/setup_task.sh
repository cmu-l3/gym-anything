#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Autofill Address Update Task Setup ==="
echo "Task: Remove old address and add new address to Chrome autofill"

# Install required utilities (SQLite for database manipulation, UUID for GUID generation)
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip sqlite3 uuid-runtime || true

# Ensure Python SQLite library is available
pip3 install -q --no-warn-script-location 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# CRITICAL: Close Chrome to safely modify Web Data database
echo "Stopping Chrome to modify autofill database..."
pkill -f "google-chrome" || true
pkill -f "chrome.*remote-debugging" || true
sleep 3

# Double-check Chrome is fully closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 2
fi

# Determine Chrome profile path
CHROME_PROFILE_CDP="/home/ga/.config/google-chrome-cdp/Default"
CHROME_PROFILE_STD="/home/ga/.config/google-chrome/Default"

# Check which profile exists
if [ -d "$CHROME_PROFILE_CDP" ]; then
    CHROME_PROFILE="$CHROME_PROFILE_CDP"
    echo "Using Chrome profile: $CHROME_PROFILE_CDP"
elif [ -d "$CHROME_PROFILE_STD" ]; then
    CHROME_PROFILE="$CHROME_PROFILE_STD"
    echo "Using Chrome profile: $CHROME_PROFILE_STD"
else
    echo "Chrome profile not found, creating default..."
    mkdir -p "$CHROME_PROFILE_STD"
    CHROME_PROFILE="$CHROME_PROFILE_STD"
fi

WEB_DATA="$CHROME_PROFILE/Web Data"

# Ensure Web Data database exists
if [ ! -f "$WEB_DATA" ]; then
    echo "Web Data database not found, Chrome may not have been launched yet"
    echo "Creating minimal Web Data database structure..."
    
    # Create basic Web Data structure
    sqlite3 "$WEB_DATA" <<'EOF'
CREATE TABLE IF NOT EXISTS autofill_profiles (
    guid VARCHAR PRIMARY KEY,
    company_name VARCHAR,
    street_address VARCHAR,
    dependent_locality VARCHAR,
    city VARCHAR,
    state VARCHAR,
    zipcode VARCHAR,
    sorting_code VARCHAR,
    country_code VARCHAR,
    date_modified INTEGER NOT NULL DEFAULT 0,
    origin VARCHAR DEFAULT '',
    language_code VARCHAR,
    use_count INTEGER NOT NULL DEFAULT 0,
    use_date INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS autofill_profile_addresses (
    guid VARCHAR,
    street_address VARCHAR,
    dependent_locality VARCHAR,
    city VARCHAR,
    state VARCHAR,
    zip_code VARCHAR,
    sorting_code VARCHAR,
    country_code VARCHAR
);

CREATE TABLE IF NOT EXISTS autofill_profile_names (
    guid VARCHAR,
    first_name VARCHAR,
    middle_name VARCHAR,
    last_name VARCHAR,
    full_name VARCHAR
);

CREATE TABLE IF NOT EXISTS autofill_profile_emails (
    guid VARCHAR,
    email VARCHAR
);

CREATE TABLE IF NOT EXISTS autofill_profile_phones (
    guid VARCHAR,
    number VARCHAR
);
EOF
    
    chown ga:ga "$WEB_DATA"
    echo "✓ Created Web Data database structure"
fi

# Generate GUID for old address profile
OLD_GUID=$(uuidgen)

echo "Seeding old address into autofill database..."
echo "  GUID: $OLD_GUID"
echo "  Address: 742 Evergreen Terrace, Springfield, IL 62704"

# Get current timestamp for date_modified
CURRENT_TIME=$(date +%s)
# Make it look like an old entry (6 months ago)
OLD_TIME=$((CURRENT_TIME - 15552000))

# Insert old address profile into Web Data database
sqlite3 "$WEB_DATA" <<EOF
-- Insert into autofill_profiles table
INSERT INTO autofill_profiles (
    guid, 
    company_name, 
    street_address, 
    city, 
    state, 
    zipcode, 
    country_code, 
    date_modified, 
    use_count, 
    use_date
) VALUES (
    '$OLD_GUID',
    '',
    '742 Evergreen Terrace',
    'Springfield',
    'IL',
    '62704',
    'US',
    $OLD_TIME,
    5,
    $OLD_TIME
);

-- Insert into autofill_profile_addresses table
INSERT INTO autofill_profile_addresses (
    guid,
    street_address,
    city,
    state,
    zip_code,
    country_code
) VALUES (
    '$OLD_GUID',
    '742 Evergreen Terrace',
    'Springfield',
    'IL',
    '62704',
    'US'
);

-- Insert into autofill_profile_names table
INSERT INTO autofill_profile_names (
    guid,
    first_name,
    middle_name,
    last_name,
    full_name
) VALUES (
    '$OLD_GUID',
    'Former',
    '',
    'Resident',
    'Former Resident'
);
EOF

# Verify the insertion
ADDRESS_COUNT=$(sqlite3 "$WEB_DATA" "SELECT COUNT(*) FROM autofill_profile_addresses WHERE street_address LIKE '%742 Evergreen%';")
if [ "$ADDRESS_COUNT" -gt 0 ]; then
    echo "✓ Successfully seeded old address into database"
    echo "  Verification: $ADDRESS_COUNT address(es) found"
else
    echo "⚠ Warning: Old address may not have been inserted correctly"
fi

# Set proper ownership
chown ga:ga "$WEB_DATA"

# Wait a moment for file system to settle
sleep 1

# Launch Chrome with autofill settings page
echo "Launching Chrome with autofill settings..."

# Start Chrome as ga user with autofill settings page
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh chrome://settings/addresses" &

# Wait for Chrome to initialize
sleep 5

# Verify Chrome is running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "✓ Chrome is running"
else
    echo "⚠ Warning: Chrome may not have started properly"
fi

# IMPORTANT: Focus Chrome window properly
echo "Focusing Chrome window..."

# Wait a bit more for Chrome to fully initialize
sleep 2

# Click at center to select desktop (multi-desktop environments)
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Chrome window using wmctrl
export DISPLAY=:1
wid=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | head -1 | awk '{print $1}')
if [ -z "$wid" ]; then
    echo "Warning: Could not find Chrome window"
else
    echo "Focusing Chrome window: $wid"
    wmctrl -i -a $wid || true
    sleep 1
fi

# Final focus using xdotool
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    
    # Get active tab URL to verify we're on settings page
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""')
    echo "  Active URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "Chrome is displaying the autofill addresses settings page."
echo "The old address (742 Evergreen Terrace) should be visible in the list."
echo ""
echo "Agent task:"
echo "  1. Identify the old address entry in the addresses list"
echo "  2. Click the three-dot menu (⋮) next to the old address"
echo "  3. Select 'Remove' or 'Delete' to remove the old address"
echo "  4. Click 'Add' button to add a new address"
echo "  5. Fill in the new address form:"
echo "     - Name: Sarah Chen"
echo "     - Street address: 1428 Elm Street, Apt 3B"
echo "     - City: Springfield"
echo "     - State: IL"
echo "     - ZIP code: 62701"
echo "     - Country: United States"
echo "  6. Click 'Save' to save the new address"
echo ""