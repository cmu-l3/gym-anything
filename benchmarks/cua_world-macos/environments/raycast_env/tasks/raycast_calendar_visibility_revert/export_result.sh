#!/bin/bash
# Export: raycast_calendar_visibility_revert
# Reads (a) the Mail draft content (where the agent pastes availability),
# (b) actual EventKit events for next Thursday (ground truth),
# (c) best-effort Raycast WAL signal for "settings touched".

set -euo pipefail
echo "=== Export: raycast_calendar_visibility_revert ==="

RESULT_FILE="/tmp/raycast_calendar_visibility_revert_result.json"
START_TS=$(cat /tmp/raycast_calendar_visibility_revert_start_ts 2>/dev/null || echo "0")
NEXT_THU=$(cat /tmp/raycast_calendar_visibility_revert_next_thu 2>/dev/null || echo "")
NEXT_THU_HUMAN=$(cat /tmp/raycast_calendar_visibility_revert_next_thu_human 2>/dev/null || echo "")

# --- 1. Read Mail draft content ---
MAIL_DRAFT_CONTENT=$(osascript << 'APPLEOF' 2>/dev/null || echo ""
tell application "Mail"
    try
        set draftContent to ""
        repeat with msg in outgoing messages
            if (subject of msg) contains "Coffee next week" then
                set draftContent to content of msg
                exit repeat
            end if
        end repeat
        return draftContent
    on error
        return ""
    end try
end tell
APPLEOF
)

# --- 2. Read EventKit events for next Thursday across all 4 calendars (ground truth) ---
EVENTS_RAW=""
if [ -n "$NEXT_THU" ]; then
    NEXT_THU_Y=$(date -j -f "%Y-%m-%d" "$NEXT_THU" +%Y)
    NEXT_THU_M=$(date -j -f "%Y-%m-%d" "$NEXT_THU" +%-m)
    NEXT_THU_D=$(date -j -f "%Y-%m-%d" "$NEXT_THU" +%-d)
    EVENTS_RAW=$(osascript << APPLEOF 2>/dev/null || echo ""
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
                    set evTitle to summary of ev
                    set evStart to start date of ev
                    set evEnd to end date of ev
                    set evAvail to availability of ev as text
                    set evAllDay to (allday event of ev) as text
                    set sh to (hours of evStart) as text
                    set sm to (minutes of evStart) as text
                    set eh to (hours of evEnd) as text
                    set em to (minutes of evEnd) as text
                    if (count of sh) < 2 then set sh to "0" & sh
                    if (count of sm) < 2 then set sm to "0" & sm
                    if (count of eh) < 2 then set eh to "0" & eh
                    if (count of em) < 2 then set em to "0" & em
                    set output to output & (calName as text) & "|" & evTitle & "|" & sh & ":" & sm & "|" & eh & ":" & em & "|" & evAvail & "|" & evAllDay & linefeed
                end repeat
            end tell
        end try
    end repeat
    return output
end tell
APPLEOF
    )
fi

# --- 3. Best-effort Raycast settings touch signal (encrypted DB → can only check mtime) ---
RAYCAST_DB_WAL="/Users/lume/Library/Application Support/com.raycast.macos/raycast-enc.sqlite-wal"
WAL_SIZE=$(stat -f%z "$RAYCAST_DB_WAL" 2>/dev/null || echo "0")
WAL_MTIME=$(stat -f%m "$RAYCAST_DB_WAL" 2>/dev/null || echo "0")

# --- 4. Assemble result JSON ---
export MAIL_DRAFT_CONTENT_FROM_ENV="$MAIL_DRAFT_CONTENT"
export EVENTS_RAW_FROM_ENV="$EVENTS_RAW"
MAIL_DRAFT_LEN=${#MAIL_DRAFT_CONTENT}

python3 - "$RESULT_FILE" "$START_TS" "$NEXT_THU" "$NEXT_THU_HUMAN" "$WAL_SIZE" "$WAL_MTIME" "$MAIL_DRAFT_LEN" << 'PYEOF'
import json, os, sys

result_file, start_ts, next_thu, next_thu_human, wal_size, wal_mtime, mail_draft_len = sys.argv[1:8]
mail_content = os.environ.get("MAIL_DRAFT_CONTENT_FROM_ENV", "")
events_raw   = os.environ.get("EVENTS_RAW_FROM_ENV", "")

events = []
for line in events_raw.splitlines():
    parts = line.split("|")
    if len(parts) >= 6:
        events.append({
            "calendar":     parts[0],
            "title":        parts[1],
            "start":        parts[2],
            "end":          parts[3],
            "availability": parts[4],
            "all_day":      parts[5].strip().lower() == "true",
        })

result = {
    "task_start":          int(start_ts),
    "next_thursday":       next_thu,
    "next_thursday_human": next_thu_human,
    "mail_draft_present":  int(mail_draft_len) > 0,
    "mail_draft_content":  mail_content,
    "mail_draft_length":   int(mail_draft_len),
    "events_seen":         events,
    "event_count":         len(events),
    "raycast_wal_size_bytes":          int(wal_size),
    "raycast_wal_mtime":               int(wal_mtime),
    "raycast_wal_changed_after_setup": int(wal_mtime) > int(start_ts),
}

with open(result_file, "w") as f:
    json.dump(result, f, indent=2)

print(f"WROTE {result_file}: mail_len={mail_draft_len} events={len(events)} wal_changed={int(wal_mtime) > int(start_ts)}")
PYEOF

echo "=== Export complete ==="
