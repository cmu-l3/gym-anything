#!/bin/bash
# Setup for Edge Kiosk Policy Config task
set -e

echo "=== Setting up Edge Kiosk Policy Config ==="

# 1. Kill any running Edge instances
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
sleep 1

# 2. Clean up previous state
# Remove existing policies to ensure clean start
if [ -d "/etc/microsoft-edge/policies/managed" ]; then
    rm -f /etc/microsoft-edge/policies/managed/*.json
fi
# Remove report if exists
rm -f /home/ga/Desktop/kiosk_deploy_report.txt

# 3. Create Requirements Document
cat > /home/ga/Desktop/kiosk_requirements.txt << 'EOF'
PUBLIC ACCESS KIOSK - BROWSER CONFIGURATION REQUIREMENTS
Department of Social Services - Eligibility Office

PURPOSE: Configure Microsoft Edge on public-facing kiosk terminals
used by citizens to access government benefit eligibility tools.

REQUIREMENTS:

1. HOMEPAGE: Set to https://www.usa.gov/benefits
2. NEW TAB PAGE: Set to https://www.ssa.gov
3. URL BLOCKLIST: Block access to the following domains:
   - facebook.com
   - twitter.com
   - youtube.com
   - tiktok.com
   - instagram.com
   - reddit.com
4. DOWNLOAD RESTRICTIONS: All downloads must be blocked (policy value: 3)
5. DEVELOPER TOOLS: Must be completely disabled (policy value: 2)
6. INPRIVATE MODE: Must be disabled (policy value: 1)
7. PASSWORD SAVING: Must be disabled
8. BOOKMARK BAR: Must always be visible
9. BROWSER SIGN-IN: Must be disabled (policy value: 0)

DEPLOYMENT:
- All configurations must be enforced via enterprise policy (not user-changeable).
- On Linux, Edge enterprise policies are deployed as JSON files in:
  /etc/microsoft-edge/policies/managed/
- After deployment, restart Edge and verify at edge://policy

DELIVERABLE:
- Write a deployment confirmation report to /home/ga/Desktop/kiosk_deploy_report.txt
  listing each policy applied and its configured value.
EOF
chown ga:ga /home/ga/Desktop/kiosk_requirements.txt
chmod 644 /home/ga/Desktop/kiosk_requirements.txt

# 4. Record start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 5. Launch Edge (Clean state)
# We launch it so the agent sees the "before" state
su - ga -c "DISPLAY=:1 microsoft-edge --no-first-run --no-default-browser-check &" 2>/dev/null

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Edge"; then
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Edge" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="