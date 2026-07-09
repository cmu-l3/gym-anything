#!/bin/bash
# Setup: raycast_workspace_focus_traps
#
# Creates two real PDFs (lease-renewal + lease-old) with distinct content,
# opens them in Preview, and pre-launches Safari, Notes, Mail, Finder.
# Records the INITIAL position/size of the lease-old.pdf window so the
# verifier can check that the agent left it untouched.

set -euo pipefail
echo "=== Setup: raycast_workspace_focus_traps ==="

LEASE_DIR="/Users/lume/Documents/Lease"
mkdir -p "$LEASE_DIR"

# --- 1. Ensure Raycast running + dismiss permission dialogs ---
if ! pgrep -x "Raycast" > /dev/null 2>&1; then
    open -a "Raycast" 2>/dev/null || true
    for i in $(seq 1 15); do
        if pgrep -x "Raycast" > /dev/null 2>&1; then break; fi
        sleep 2
    done
fi
sleep 3
for _i in $(seq 1 4); do
    osascript << 'APPLEOF' 2>/dev/null || true
tell application "System Events"
    try
        repeat with proc in (every application process whose frontmost is true)
            tell proc
                if exists button "Allow" of front window then
                    click button "Allow" of front window
                else if exists button "OK" of front window then
                    click button "OK" of front window
                else if exists button "Don't Allow" of front window then
                    click button "Don't Allow" of front window
                end if
            end tell
        end repeat
    end try
end tell
APPLEOF
    sleep 1
done

# --- 2. Create two distinct real PDFs ---
# lease-renewal.pdf: REAL Oregon residential lease renewal language (template
# adapted from the Oregon Real Estate Forms Library — boilerplate clauses).
cat > /tmp/_lease_renewal.txt << 'EOF'
RESIDENTIAL LEASE RENEWAL AGREEMENT — STATE OF OREGON
This Lease Renewal Agreement ("Renewal") is made effective as of June 1, 2026.

Property: 1742 NW Glisan St, Portland, OR 97209
Landlord: Portland Heights Property Management LLC
Tenant:   Lume Household (current resident under prior 12-month lease)

TERMS:
1. The Renewal extends the existing lease for an additional 12 months,
   from June 1, 2026 through May 31, 2027.
2. Monthly rent shall be USD 2,450, payable on the first day of each month.
3. Security deposit of USD 2,450 currently on file shall continue to apply.
4. All other terms of the original lease (dated June 1, 2025) remain in force,
   including pet policy, utility responsibilities, and quiet-hours provisions.
5. ORS 90.427 notice requirements have been satisfied as of April 1, 2026.

Tenant initials: ______        Landlord signature: ______      Date: ______
EOF
cupsfilter -e /tmp/_lease_renewal.txt > "$LEASE_DIR/lease-renewal.pdf" 2>/dev/null || true

cat > /tmp/_lease_old.txt << 'EOF'
RESIDENTIAL LEASE AGREEMENT — STATE OF OREGON (ORIGINAL, June 2025)
This Lease Agreement was made effective as of June 1, 2025.

Property: 1742 NW Glisan St, Portland, OR 97209
Landlord: Portland Heights Property Management LLC
Tenant:   Lume Household

TERMS:
1. Initial 12-month lease from June 1, 2025 through May 31, 2026.
2. Monthly rent USD 2,375 payable on the first day of each month.
3. Security deposit USD 2,375.
4. Pet policy: 1 dog allowed, weight under 35 lbs, no additional deposit.
5. Quiet hours: 10:00 PM – 8:00 AM weekdays.

Tenant signature: ______        Landlord signature: ______      Date: 6/1/2025
EOF
cupsfilter -e /tmp/_lease_old.txt > "$LEASE_DIR/lease-old.pdf" 2>/dev/null || true

ls -la "$LEASE_DIR/" || true

# --- 3. Open both PDFs in Preview ---
open -a "Preview" "$LEASE_DIR/lease-old.pdf" 2>/dev/null || true
sleep 2
open -a "Preview" "$LEASE_DIR/lease-renewal.pdf" 2>/dev/null || true
sleep 3

# --- 4. Pre-launch Safari, Notes, Mail, Finder ---
open -a "Safari" 2>/dev/null || true
sleep 1
open -a "Notes" 2>/dev/null || true
sleep 1
open -a "Mail" 2>/dev/null || true
sleep 1
osascript -e 'tell application "Finder" to open home' 2>/dev/null || true
sleep 2

# --- 5. Record initial position of lease-old.pdf Preview window ---
# Iterate through Preview windows, find the one whose title contains "lease-old"
LEASE_OLD_FRAME=$(osascript << 'APPLEOF' 2>/dev/null || echo ""
tell application "System Events"
    try
        tell process "Preview"
            set winList to every window
            repeat with w in winList
                set t to (name of w as text)
                if t contains "lease-old" then
                    set p to position of w
                    set s to size of w
                    return ((item 1 of p) as string) & "," & ((item 2 of p) as string) & "," & ((item 1 of s) as string) & "," & ((item 2 of s) as string)
                end if
            end repeat
        end tell
    end try
    return ""
end tell
APPLEOF
)

# Get screen bounds
SCREEN_BOUNDS=$(osascript -e 'tell application "Finder" to get bounds of window of desktop' 2>/dev/null || echo "")

# --- 6. Record baseline ---
date +%s > /tmp/raycast_workspace_focus_traps_start_ts
echo "$LEASE_OLD_FRAME"  > /tmp/raycast_workspace_focus_traps_lease_old_initial
echo "$SCREEN_BOUNDS"    > /tmp/raycast_workspace_focus_traps_screen_bounds

echo "Task start ts:        $(cat /tmp/raycast_workspace_focus_traps_start_ts)"
echo "lease-old initial frame: $LEASE_OLD_FRAME"
echo "Screen bounds:        $SCREEN_BOUNDS"
echo "=== Setup complete ==="
