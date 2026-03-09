#!/system/bin/sh
# Setup script for adjust_app_permissions task
# Configures initial permission state (Location=Foreground, Mic=Granted)

echo "=== Setting up adjust_app_permissions task ==="

PACKAGE="com.robert.fcView"

# 1. Ensure App is logged in and ready (using helper)
echo "Running login helper..."
sh /sdcard/scripts/login_helper.sh
sleep 2

# 2. Configure Permissions to "Imperfect" State
echo "Configuring permissions..."

# Location: Set to "While using" (Foreground only)
# We grant fine location but revoke background location
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION
pm revoke $PACKAGE android.permission.ACCESS_BACKGROUND_LOCATION
# Force appops to foreground mode for location
appops set $PACKAGE FINE_LOCATION foreground
appops set $PACKAGE COARSE_LOCATION foreground

# Microphone: Grant it (so agent has to revoke it)
pm grant $PACKAGE android.permission.RECORD_AUDIO
appops set $PACKAGE RECORD_AUDIO allow

# Calendar/Contacts: Grant them (agent must NOT touch these)
pm grant $PACKAGE android.permission.READ_CALENDAR
pm grant $PACKAGE android.permission.READ_CONTACTS

# 3. Record Initial State for Anti-Gaming
date +%s > /sdcard/task_start_time.txt
dumpsys package $PACKAGE | grep "permission" > /sdcard/initial_permissions_dump.txt

echo "=== Task setup completed ==="
echo "State: Location=ForegroundOnly, Mic=Granted, Cal/Contacts=Granted"
echo "App is open on Friends page."