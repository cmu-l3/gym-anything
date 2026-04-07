#!/system/bin/sh
# Setup script for navigate_to_contact task
# Runs on Android via ADB shell

echo "=== Setting up navigate_to_contact task ==="

PACKAGE="com.sygic.aura"

# 1. Clean up: Force stop Sygic to ensure fresh state
am force-stop $PACKAGE
sleep 2

# 2. Record start time
date +%s > /sdcard/task_start_time.txt

# 3. Setup Contact Data
# We need to insert a contact named "Dr. Hameed" with address "Jalalabad" into the Android Contacts provider.
# This uses the 'content' command available in Android shell.

echo "Clearing existing contacts..."
pm clear com.android.providers.contacts
sleep 2

echo "Creating contact: Dr. Hameed..."
# Insert raw contact
RAW_URI=$(content insert --uri content://com.android.contacts/raw_contacts --bind account_type:s:null --bind account_name:s:null)
# Extract ID (hacky parsing for shell, but usually returns content://.../ID)
ID=${RAW_URI##*/}

if [ -z "$ID" ]; then
    echo "Failed to create raw contact, assuming ID 1"
    ID=1
fi

echo "Contact ID: $ID"

# Insert Name
content insert --uri content://com.android.contacts/data --bind raw_contact_id:i:$ID --bind mimetype:s:vnd.android.cursor.item/name --bind data1:s:"Dr. Hameed"

# Insert Address (Postal)
content insert --uri content://com.android.contacts/data --bind raw_contact_id:i:$ID --bind mimetype:s:vnd.android.cursor.item/postal-address_v2 --bind data1:s:"Jalalabad" --bind data4:s:"Jalalabad" --bind data7:s:"Afghanistan"

echo "Contact created."

# 4. Launch Sygic GPS Navigation
echo "Launching Sygic..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 15

# 5. Ensure we are on the map screen (handle any lingering dialogs)
# Press Back once just in case a menu was open
input keyevent KEYCODE_BACK
sleep 2

# Verify app is in foreground
CURRENT=$(dumpsys window | grep mCurrentFocus)
if ! echo "$CURRENT" | grep -q "$PACKAGE"; then
    echo "App lost focus, relaunching..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 5
fi

# 6. Take initial screenshot for evidence
screencap -p /sdcard/task_initial.png

echo "=== Setup complete ==="