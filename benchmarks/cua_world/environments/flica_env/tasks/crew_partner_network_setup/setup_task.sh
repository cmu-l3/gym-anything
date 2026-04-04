#!/system/bin/sh
# Setup script for crew_partner_network_setup task

echo "=== Setting up crew_partner_network_setup ==="
PACKAGE="com.robert.fcView"
pm clear $PACKAGE 2>/dev/null
sleep 3
sh /sdcard/scripts/login_helper.sh 2>/dev/null
sleep 3
date +%s > /tmp/crew_partner_network_setup_start
screencap -p /tmp/crew_partner_network_setup_initial.png 2>/dev/null
echo "=== Setup Complete: clean state, agent must set name+Captain+ORD airports+3 friends ==="
