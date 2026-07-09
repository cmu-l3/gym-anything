#!/bin/bash
# Setup: raycast_calendar_visibility_revert
#
# Seeds real EventKit data: creates 4 calendars (Personal, Family, Work, Birthdays),
# wipes any events on next Thursday in those calendars, then inserts 7 real-looking
# events with mixed busy/tentative/free availability statuses. Opens a Mail compose
# window titled "Re: Coffee next week?" for the agent to paste into.

set -euo pipefail
echo "=== Setup: raycast_calendar_visibility_revert ==="

# --- 1. Ensure Raycast is running ---
if ! pgrep -x "Raycast" > /dev/null 2>&1; then
    open -a "Raycast" 2>/dev/null || open -b "com.raycast.macos" 2>/dev/null || true
    for i in $(seq 1 15); do
        if pgrep -x "Raycast" > /dev/null 2>&1; then break; fi
        sleep 2
    done
fi
sleep 3

# --- 2. Dismiss any macOS permission dialog (retry loop) ---
for _i in $(seq 1 6); do
    osascript << 'APPLEOF' 2>/dev/null || true
tell application "System Events"
    try
        if exists button "OK" of front window of application process "UserNotificationCenter" then
            click button "OK" of front window of application process "UserNotificationCenter"
        else if exists button "Allow" of front window of application process "UserNotificationCenter" then
            click button "Allow" of front window of application process "UserNotificationCenter"
        end if
    end try
end tell
APPLEOF
    sleep 1
done

# --- 3. Compute next Thursday (BSD date, macOS) ---
TODAY_DOW=$(date +%u)  # 1=Mon … 7=Sun
DAYS=$(( (4 - TODAY_DOW + 7) % 7 ))
if [ $DAYS -eq 0 ]; then DAYS=7; fi
NEXT_THU=$(date -v+${DAYS}d +%Y-%m-%d)
NEXT_THU_Y=$(date -j -f "%Y-%m-%d" "$NEXT_THU" +%Y)
NEXT_THU_M=$(date -j -f "%Y-%m-%d" "$NEXT_THU" +%-m)
NEXT_THU_D=$(date -j -f "%Y-%m-%d" "$NEXT_THU" +%-d)
NEXT_THU_HUMAN=$(date -j -f "%Y-%m-%d" "$NEXT_THU" "+%A, %B %-d, %Y")
echo "Next Thursday: $NEXT_THU ($NEXT_THU_HUMAN)"

# --- 4. Launch Calendar.app and let EventKit settle ---
open -a "Calendar" 2>/dev/null || true
sleep 4

# Dismiss any Calendar-access permission prompt that pops up now
for _i in $(seq 1 4); do
    osascript << 'APPLEOF' 2>/dev/null || true
tell application "System Events"
    try
        repeat with proc in (every application process whose frontmost is true)
            tell proc
                if exists button "Allow Full Access" of front window then
                    click button "Allow Full Access" of front window
                else if exists button "Allow" of front window then
                    click button "Allow" of front window
                else if exists button "OK" of front window then
                    click button "OK" of front window
                end if
            end tell
        end repeat
    end try
end tell
APPLEOF
    sleep 1
done

# --- 5. Create the 4 calendars if they don't exist ---
# NOTE: macOS has a system 'Birthdays' calendar that's read-only. We use the
# name 'Birthdays' but force-create our own CalDAV calendar with that display
# name. If a calendar with this name already exists (e.g., system Birthdays
# or one from a prior run), we keep using it.
for CAL in Personal Family Work "Family Birthdays"; do
    osascript << APPLEOF 2>/dev/null || true
tell application "Calendar"
    if not (exists calendar "$CAL") then
        make new calendar with properties {name:"$CAL"}
    end if
end tell
APPLEOF
    sleep 2
done

# --- 5b. Verify all 4 calendars exist; report names ---
CAL_LIST=$(osascript << 'APPLEOF' 2>/dev/null || echo ""
tell application "Calendar"
    set out to ""
    repeat with c in calendars
        set out to out & (name of c) & linefeed
    end repeat
    return out
end tell
APPLEOF
)
echo "--- Calendars present after creation ---"
echo "$CAL_LIST"
echo "--- end calendar list ---"

# --- 6. Wipe any existing events on next Thursday in these calendars (clean slate) ---
osascript << APPLEOF 2>/dev/null || true
tell application "Calendar"
    set dayStart to (current date)
    set year of dayStart to $NEXT_THU_Y
    set month of dayStart to $NEXT_THU_M
    set day of dayStart to $NEXT_THU_D
    set hours of dayStart to 0
    set minutes of dayStart to 0
    set seconds of dayStart to 0
    set dayEnd to dayStart + (24 * hours)
    repeat with calName in {"Personal", "Family", "Work", "Family Birthdays"}
        try
            tell calendar (calName as text)
                set evs to (every event whose start date >= dayStart and start date < dayEnd)
                repeat with ev in evs
                    delete ev
                end repeat
            end tell
        end try
    end repeat
end tell
APPLEOF
sleep 1

# --- 7. Seed the 7 events ---

seed_event() {
    local CAL="$1" TITLE="$2"
    local SH="$3" SM="$4" EH="$5" EM="$6"
    # No status/availability enum — those aren't reliably exposed via
    # AppleScript across macOS versions. Tentative-ness for the yoga
    # event is encoded directly in its title text ('(tentative)').
    osascript 2>&1 << APPLEOF || echo "  ERR seeding $CAL/$TITLE: \$?"
tell application "Calendar"
    set targetCal to first calendar whose name is "$CAL"
    set startD to (current date)
    set year of startD to $NEXT_THU_Y
    set month of startD to $NEXT_THU_M
    set day of startD to $NEXT_THU_D
    set hours of startD to $SH
    set minutes of startD to $SM
    set seconds of startD to 0
    set endD to (current date)
    set year of endD to $NEXT_THU_Y
    set month of endD to $NEXT_THU_M
    set day of endD to $NEXT_THU_D
    set hours of endD to $EH
    set minutes of endD to $EM
    set seconds of endD to 0
    set newEv to make new event at targetCal with properties {summary:"$TITLE", start date:startD, end date:endD}
    return "OK seeded: " & "$TITLE" & " in " & "$CAL"
end tell
APPLEOF
}

seed_event "Personal" "Lunch with Sarah"          12  0 13  0
seed_event "Personal" "Dentist appointment"       14  0 15  0
seed_event "Personal" "Evening yoga (tentative)"  17  0 18  0
seed_event "Family"   "Pick up kids from school"  15 30 16 30
seed_event "Work"     "Engineering standup"        9  0  9 30
seed_event "Work"     "Team retro"                13  0 14  0

# All-day birthday in our own 'Family Birthdays' calendar
osascript 2>&1 << APPLEOF || echo "  ERR seeding Family Birthdays/Mom's birthday"
tell application "Calendar"
    activate
    set targetCal to first calendar whose name is "Family Birthdays"
    set startD to (current date)
    set year of startD to $NEXT_THU_Y
    set month of startD to $NEXT_THU_M
    set day of startD to $NEXT_THU_D
    set hours of startD to 0
    set minutes of startD to 0
    set seconds of startD to 0
    set endD to startD + (24 * hours)
    set newEv to make new event at targetCal with properties {summary:"Mom's birthday", start date:startD, end date:endD, allday event:true}
    return "OK: Mom's birthday"
end tell
APPLEOF
sleep 1

# --- 8. Open Mail and create a compose draft ---
open -a "Mail" 2>/dev/null || true
sleep 3
# Dismiss any Mail welcome / account dialog
for _i in $(seq 1 4); do
    osascript << 'APPLEOF' 2>/dev/null || true
tell application "System Events"
    try
        repeat with proc in (every application process whose frontmost is true)
            tell proc
                if exists button "Not Now" of front window then
                    click button "Not Now" of front window
                else if exists button "Cancel" of front window then
                    click button "Cancel" of front window
                end if
            end tell
        end repeat
    end try
end tell
APPLEOF
    sleep 1
done

osascript 2>&1 << 'APPLEOF' || echo "  ERR creating Mail draft"
tell application "Mail"
    activate
    set bodyText to "Hi Alex," & linefeed & linefeed & ¬
        "Coffee next week sounds great. Here are the times that work for me next Thursday:" & linefeed & linefeed & linefeed & ¬
        "Let me know which works best for you." & linefeed & linefeed & ¬
        "Thanks,"
    set newDraft to make new outgoing message with properties {subject:"Re: Coffee next week?", visible:true}
    delay 1
    set content of newDraft to bodyText
    delay 1
    return "OK draft created; bodyText length=" & (count of bodyText) & " stored content length=" & (count of (content of newDraft))
end tell
APPLEOF
sleep 2

# --- 9. Record baseline ---
date +%s > /tmp/raycast_calendar_visibility_revert_start_ts
echo "$NEXT_THU"        > /tmp/raycast_calendar_visibility_revert_next_thu
echo "$NEXT_THU_HUMAN"  > /tmp/raycast_calendar_visibility_revert_next_thu_human

# --- 9b. Post-setup verification: query EventKit + Mail to confirm state ---
# Give Calendar.app time to flush new events to its store before querying.
sleep 4

echo "--- Event counts by calendar (all-time) ---"
osascript 2>&1 << 'APPLEOF' || echo "(broad query failed)"
tell application "Calendar"
    set output to ""
    repeat with c in calendars
        try
            set output to output & "  " & (name of c) & ": " & (count of events of c) & " events" & linefeed
        end try
    end repeat
    return output
end tell
APPLEOF
echo "--- end event counts ---"

echo "--- Events seeded on $NEXT_THU ---"
osascript 2>&1 << APPLEOF || echo "(query failed)"
tell application "Calendar"
    set dayStart to (current date)
    set year of dayStart to $NEXT_THU_Y
    set month of dayStart to $NEXT_THU_M
    set day of dayStart to $NEXT_THU_D
    set hours of dayStart to 0
    set minutes of dayStart to 0
    set seconds of dayStart to 0
    set dayEnd to dayStart + (24 * hours)
    set output to ""
    repeat with calName in {"Personal", "Family", "Work", "Family Birthdays"}
        try
            tell calendar (calName as text)
                set evs to (every event whose start date >= dayStart and start date < dayEnd)
                repeat with ev in evs
                    set output to output & "  [" & (calName as text) & "] " & (summary of ev) & " (" & (start date of ev as text) & " avail=" & (availability of ev as text) & ")" & linefeed
                end repeat
            end tell
        end try
    end repeat
    return output
end tell
APPLEOF
echo "--- end events ---"
echo "--- Mail drafts present ---"
osascript << 'APPLEOF' 2>/dev/null || echo "(query failed)"
tell application "Mail"
    set output to ""
    try
        repeat with msg in outgoing messages
            set output to output & "  Subject: " & (subject of msg) & " (length=" & (count of (content of msg)) & ")" & linefeed
        end repeat
    end try
    return output
end tell
APPLEOF
echo "--- end mail drafts ---"

echo "Task start ts:  $(cat /tmp/raycast_calendar_visibility_revert_start_ts)"
echo "Next Thursday: $NEXT_THU_HUMAN"
echo "=== Setup complete ==="
