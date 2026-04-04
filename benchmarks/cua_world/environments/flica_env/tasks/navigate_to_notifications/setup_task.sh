#!/system/bin/sh
# Setup script for navigate_to_notifications task
# Ensures Flight Crew View is logged in and on the Friends page

echo "=== Setting up navigate_to_notifications task ==="

PACKAGE="com.robert.fcView"

# Run the login helper to get to the Friends page
sh /sdcard/scripts/login_helper.sh

echo "=== Task setup completed ==="
echo "App should be on the Friends page. Agent should navigate to Notifications."
