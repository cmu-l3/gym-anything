#!/bin/bash
# Setup for "create_user_account" task
# Opens Firefox to EventLog Analyzer Settings > Technicians & Roles

echo "=== Setting up Create User Account task ==="

# Do NOT use set -euo pipefail (cross-cutting pattern #25)
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Ensure EventLog Analyzer is running
wait_for_eventlog_analyzer

# Navigate to dashboard first (AppHome.do#/settings fails as direct URL due to SPA routing)
# Must go via AppsHome.do (main app) then click Settings tab
ensure_firefox_on_ela "/event/AppsHome.do#/home/dashboard/0"
sleep 4

# Dismiss any "What's New" or onboarding dialog with Escape
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape
sleep 1

# Focus Firefox window and click Settings tab at (618, 203) in 1920x1080
WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -ia "$WID" 2>/dev/null || true
fi
sleep 0.5
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool mousemove 618 203 click 1
echo "Clicked Settings tab"
sleep 4

# Click "Technicians & Roles" link at (214, 631) in 1920x1080
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool mousemove 214 631 click 1
echo "Clicked Technicians and Roles"
sleep 3

# Take initial screenshot
take_screenshot /tmp/create_user_account_start.png

echo ""
echo "=== Create User Account Task Ready ==="
echo ""
echo "Instructions:"
echo "  EventLog Analyzer Settings page is open in Firefox."
echo "  You are logged in as admin."
echo "  Click on 'Technicians & Roles' under Admin Settings > Management."
echo "  Click the '+ Add Technician' button."
echo "  Create a new technician with:"
echo "    - Username: analyst01"
echo "    - Full Name: Security Analyst"
echo "    - Email: analyst01@company.local"
echo "    - Role: Operator"
echo ""
