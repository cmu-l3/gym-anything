#!/bin/bash
# Setup: raycast_aichat_constrained_context

set -euo pipefail
echo "=== Setup: raycast_aichat_constrained_context ==="

TRIP_HTML="/tmp/portland_trip.html"

# --- 1. Ensure Raycast running + dialogs ---
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
                if exists button "Allow" of front window then click button "Allow" of front window
                if exists button "OK" of front window then click button "OK" of front window
            end tell
        end repeat
    end try
end tell
APPLEOF
    sleep 1
done

# --- 2. Create real trip HTML (Portland Saturday itinerary) ---
cat > "$TRIP_HTML" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Portland day trip — Saturday plan</title>
<style>body{font-family:-apple-system,Helvetica,sans-serif;max-width:640px;margin:32px auto;line-height:1.5;color:#222} h1{margin:0} h2{margin-top:24px;font-size:16px} ul{padding-left:18px}</style>
</head>
<body>
<h1>Portland day trip — Saturday plan</h1>
<p><b>Date:</b> today &nbsp;|&nbsp; <b>Weather:</b> rain, 56°F → cooling to 49°F at night</p>

<h2>Itinerary</h2>
<ul>
  <li><b>8:00 AM</b> — Coffee at Coava (1300 SE Grand Ave). Indoor seating.</li>
  <li><b>9:30 AM</b> — Hike at Forest Park (Lower Macleay Trail entrance). 4 miles, partial mud expected.</li>
  <li><b>12:30 PM</b> — Lunch at Pok Pok Wing (Northeast 28th Ave). Reservation under last name.</li>
  <li><b>2:00 PM</b> — Powell's City of Books (Burnside). Indoors.</li>
  <li><b>5:00 PM</b> — Drive to Multnomah Falls. Park at Lot B, paid lot, $5 cash only.</li>
  <li><b>9:30 PM</b> — Late dessert at Salt &amp; Straw (Division). Outdoor lines expected; dress warm.</li>
</ul>

<h2>Notes</h2>
<ul>
  <li>You will be outdoors at the Forest Park hike and the Multnomah Falls stop; both involve wet conditions.</li>
  <li>Cash needed for the Falls parking lot ($5 minimum).</li>
  <li>Phone signal at Falls is unreliable; download offline maps before driving.</li>
</ul>
</body>
</html>
EOF

# --- 3. Open Safari at the trip page ---
osascript -e 'tell application "Safari" to quit' 2>/dev/null || true
sleep 2
open -a "Safari" "file://$TRIP_HTML"
sleep 4

# --- 4. Seed today's calendar with a few events that may conflict ---
# Create/ensure a 'Personal' calendar exists; add 2-3 events for today.
open -a "Calendar" 2>/dev/null || true
sleep 3
for _i in $(seq 1 3); do
    osascript << 'APPLEOF' 2>/dev/null || true
tell application "System Events"
    try
        repeat with proc in (every application process whose frontmost is true)
            tell proc
                if exists button "Allow Full Access" of front window then click button "Allow Full Access" of front window
                if exists button "Allow" of front window then click button "Allow" of front window
                if exists button "OK" of front window then click button "OK" of front window
            end tell
        end repeat
    end try
end tell
APPLEOF
    sleep 1
done

osascript << 'APPLEOF' 2>/dev/null || true
tell application "Calendar"
    if not (exists calendar "Personal") then
        make new calendar with properties {name:"Personal"}
    end if
end tell
APPLEOF
sleep 1

TODAY_Y=$(date +%Y)
TODAY_M=$(date +%-m)
TODAY_D=$(date +%-d)

# Wipe existing 'Personal' calendar events for today (clean slate)
osascript << APPLEOF 2>/dev/null || true
tell application "Calendar"
    set dayStart to (current date)
    set year of dayStart to $TODAY_Y
    set month of dayStart to $TODAY_M
    set day of dayStart to $TODAY_D
    set hours of dayStart to 0
    set minutes of dayStart to 0
    set seconds of dayStart to 0
    set dayEnd to dayStart + (24 * hours)
    try
        tell calendar "Personal"
            set evs to (every event whose start date >= dayStart and start date < dayEnd)
            repeat with ev in evs
                delete ev
            end repeat
        end tell
    end try
end tell
APPLEOF
sleep 1

# Seed a 4 PM conference call that conflicts with the Multnomah Falls drive (5 PM)
seed_event() {
    local TITLE="$1" SH="$2" SM="$3" EH="$4" EM="$5"
    osascript 2>&1 << APPLEOF || echo "  ERR seeding $TITLE"
tell application "Calendar"
    set targetCal to first calendar whose name is "Personal"
    set startD to (current date)
    set year of startD to $TODAY_Y
    set month of startD to $TODAY_M
    set day of startD to $TODAY_D
    set hours of startD to $SH
    set minutes of startD to $SM
    set seconds of startD to 0
    set endD to (current date)
    set year of endD to $TODAY_Y
    set month of endD to $TODAY_M
    set day of endD to $TODAY_D
    set hours of endD to $EH
    set minutes of endD to $EM
    set seconds of endD to 0
    set newEv to make new event at targetCal with properties {summary:"$TITLE", start date:startD, end date:endD}
    return "OK seeded: $TITLE"
end tell
APPLEOF
}

seed_event "Quarterly check-in call with Sam" 16 0 17 0
seed_event "Vet appointment for Cooper"       19 30 20 30

# Verify calendar event count for today
sleep 3
echo "--- Personal calendar events for today ($TODAY_Y-$TODAY_M-$TODAY_D) ---"
osascript 2>&1 << 'APPLEOF' || echo "(query failed)"
tell application "Calendar"
    try
        tell (first calendar whose name is "Personal")
            set evs to every event
            set output to ""
            repeat with ev in evs
                set output to output & "  - " & (summary of ev) & " on " & (start date of ev as text) & linefeed
            end repeat
            return output
        end tell
    end try
end tell
APPLEOF
echo "--- end Personal events ---"

# --- 5. Create / replace the Apple Note 'Packing constraints' ---
open -a "Notes" 2>/dev/null || true
sleep 3
for _i in $(seq 1 3); do
    osascript << 'APPLEOF' 2>/dev/null || true
tell application "System Events"
    try
        repeat with proc in (every application process whose frontmost is true)
            tell proc
                if exists button "Not Now" of front window then click button "Not Now" of front window
                if exists button "Continue" of front window then click button "Continue" of front window
            end tell
        end repeat
    end try
end tell
APPLEOF
    sleep 1
done

osascript << 'APPLEOF' 2>/dev/null || true
tell application "Notes"
    try
        set existing to (every note whose name is "Packing constraints")
        repeat with n in existing
            delete n
        end repeat
    end try
    make new note with properties {name:"Packing constraints", body:"Packing constraints<br><br>Day-pack capacity: 18L<br>Weight max: 8 lbs<br>Must include: rain shell, change of socks, water bottle, $20 cash, snack bar<br>Constraints:<br>- Must NOT be outdoors after 9 PM (early dog feeding)<br>- Cooper has a vet appointment at 7:30 PM tonight<br>- Battery pack — phone charging only (Falls has no signal)<br>"}
end tell
APPLEOF
sleep 2

# --- 6. Record baseline + initial note content ---
INITIAL_NOTE_BODY=$(osascript << 'APPLEOF' 2>/dev/null || echo ""
tell application "Notes"
    try
        repeat with n in notes
            if name of n is "Packing constraints" then
                return body of n
            end if
        end repeat
        return ""
    end try
end tell
APPLEOF
)

INITIAL_NOTE_LEN=${#INITIAL_NOTE_BODY}

date +%s > /tmp/raycast_aichat_constrained_context_start_ts
echo "$INITIAL_NOTE_LEN" > /tmp/raycast_aichat_constrained_context_initial_note_len

echo "Initial note length: $INITIAL_NOTE_LEN"
echo "Today's date: $TODAY_Y-$TODAY_M-$TODAY_D"
echo "=== Setup complete ==="
